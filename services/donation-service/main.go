// donation-service — processamento de doações (hot path da SolidaryTech).
//
// Código recebido do repositório oficial do Hackathon. Rotas, payloads,
// regras de negócio e variáveis de ambiente foram mantidos. Mudanças de
// engenharia de plataforma (detalhes no README.md do serviço):
//   - logs estruturados em JSON, com trace_id (telemetry.go);
//   - tracing OpenTelemetry opcional, ligado só quando há endpoint OTLP;
//   - spans do PostgreSQL e da publicação na SQS, com o contexto W3C na
//     mensagem (sqs.go);
//   - desligamento gracioso em SIGTERM: termina as requisições e os eventos
//     SQS em andamento antes de sair;
//   - endpoint da AWS configurável (AWS_ENDPOINT_URL) para testes locais.
package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"sync"
	"syscall"
	"time"

	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/session"
	"github.com/aws/aws-sdk-go/service/sqs"
	_ "github.com/jackc/pgx/v5/stdlib"
	"github.com/joho/godotenv"
)

type Donation struct {
	ID        int       `json:"id"`
	NgoID     int       `json:"ngo_id"`
	Amount    float64   `json:"amount"`
	DonorName string    `json:"donor_name"`
	Status    string    `json:"status"`
	CreatedAt time.Time `json:"created_at"`
}

type App struct {
	DB          *sql.DB
	SqsSvc      messageSender // nil quando a SQS não está configurada
	SqsQueueURL string
	// producers conta as publicações SQS em andamento; o desligamento
	// gracioso espera por elas antes de encerrar o processo.
	producers sync.WaitGroup
}

func main() {
	_ = godotenv.Load()

	// O contexto é cancelado no SIGTERM (Kubernetes) ou no Ctrl+C (local).
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	shutdown, err := initTelemetry(ctx, "donation-service")
	if err != nil {
		// Sem tracing o serviço continua funcionando: só registra o motivo.
		slog.Warn("otel.init.failed", "reason", err.Error())
	}

	port := os.Getenv("PORT")
	if port == "" {
		port = "8082"
	}

	dbURL := os.Getenv("DATABASE_URL")
	if dbURL == "" {
		fatal("DATABASE_URL é obrigatória")
	}

	db, err := sql.Open("pgx", dbURL)
	if err == nil {
		err = db.Ping()
	}
	if err != nil {
		// Só o tipo do erro: a mensagem do driver pode trazer host e usuário.
		fatal("Erro ao conectar ao banco de dados", "error.type", fmt.Sprintf("%T", err))
	}
	slog.Info("Conectado ao PostgreSQL (donation-service).")

	var sqsSvc messageSender
	queueURL := os.Getenv("AWS_SQS_URL")
	region := os.Getenv("AWS_REGION")
	if queueURL != "" && region != "" {
		cfg := &aws.Config{Region: aws.String(region)}
		// Teste local (Moto/LocalStack): aponta o SDK para o emulador.
		// Na AWS a variável fica vazia e o SDK usa o endpoint oficial.
		if endpoint := os.Getenv("AWS_ENDPOINT_URL"); endpoint != "" {
			cfg.Endpoint = aws.String(endpoint)
		}
		sess, err := session.NewSession(cfg)
		if err != nil {
			fatal("Erro ao criar a sessão AWS", "error.type", fmt.Sprintf("%T", err))
		}
		sqsSvc = sqs.New(sess)
		slog.Info("Integração com AWS SQS ativada.")
	}

	app := &App{DB: db, SqsSvc: sqsSvc, SqsQueueURL: queueURL}

	slog.Info("donation-service rodando", "port", port)
	// Bloqueia até o SIGTERM; depois drena requisições e eventos SQS.
	serveErr := serveHTTP(ctx, ":"+port, app.routes(), app.producers.Wait)

	shutdownTelemetry(shutdown)
	_ = db.Close()
	if serveErr != nil {
		fatal("Servidor HTTP encerrado com erro", "error.type", fmt.Sprintf("%T", serveErr))
	}
	slog.Info("donation-service encerrado")
}

// routes monta o roteador com as mesmas rotas do código original, envolvido
// pela instrumentação (span por requisição e log JSON). Os testes usam este
// mesmo método, para validar exatamente o que roda em produção.
func (a *App) routes() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("/health", a.HealthHandler)
	mux.HandleFunc("/donations", a.DonationHandler)
	return instrumentHandler(mux)
}

// fatal registra o erro em JSON e encerra com código 1 (como o log.Fatal original).
func fatal(event string, args ...any) {
	slog.Error(event, args...)
	os.Exit(1)
}

func (a *App) HealthHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write([]byte(`{"status":"ok","service":"donation-service"}`))
}

func (a *App) DonationHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	ctx := r.Context()

	if r.Method == http.MethodPost {
		var d Donation
		if err := json.NewDecoder(r.Body).Decode(&d); err != nil {
			http.Error(w, `{"error":"Payload inválido"}`, http.StatusBadRequest)
			return
		}

		d.Status = "APPROVED" // Simulação de gateway de pagamento
		dbCtx, span := dbSpan(ctx, "INSERT", "donations")
		err := a.DB.QueryRowContext(dbCtx,
			"INSERT INTO donations (ngo_id, amount, donor_name, status) VALUES ($1, $2, $3, $4) RETURNING id, created_at",
			d.NgoID, d.Amount, d.DonorName, d.Status,
		).Scan(&d.ID, &d.CreatedAt)
		if err != nil {
			slog.ErrorContext(ctx, "Erro ao salvar doação", "error.type", markError(span, "db.insert", err))
			span.End()
			http.Error(w, `{"error":"Erro interno"}`, http.StatusInternalServerError)
			return
		}
		span.End()

		// Publicação assíncrona, como no original (só se a SQS estiver ativa).
		a.publishDonationEvent(ctx, d)

		w.WriteHeader(http.StatusCreated)
		_ = json.NewEncoder(w).Encode(d)
		return
	}

	if r.Method == http.MethodGet {
		dbCtx, span := dbSpan(ctx, "SELECT", "donations")
		defer span.End()
		rows, err := a.DB.QueryContext(dbCtx, "SELECT id, ngo_id, amount, donor_name, status, created_at FROM donations ORDER BY id DESC")
		if err != nil {
			slog.ErrorContext(ctx, "Erro ao buscar doações", "error.type", markError(span, "db.select", err))
			http.Error(w, `{"error":"Erro interno"}`, http.StatusInternalServerError)
			return
		}
		// Devolve a conexão ao pool em qualquer saída. O erro do Close chega
		// depois de a resposta ser escrita e não mudaria nada nela: é
		// descartado de propósito, como os outros "_ =" deste arquivo.
		defer func() { _ = rows.Close() }()

		donations := []Donation{}
		for rows.Next() {
			var d Donation
			// Como no original, uma linha que não converte não interrompe a listagem.
			_ = rows.Scan(&d.ID, &d.NgoID, &d.Amount, &d.DonorName, &d.Status, &d.CreatedAt)
			donations = append(donations, d)
		}

		_ = json.NewEncoder(w).Encode(donations)
		return
	}

	http.Error(w, `{"error":"Método não permitido"}`, http.StatusMethodNotAllowed)
}
