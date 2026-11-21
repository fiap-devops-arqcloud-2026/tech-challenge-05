package main

// telemetry.go — logs JSON, tracing OpenTelemetry e servidor HTTP com
// desligamento gracioso.
//
// Adaptado da Fase 4 (auth-service/telemetry.go). Princípios:
//   - Tracing é opt-in: só liga quando existe endpoint OTLP configurado
//     (OTEL_EXPORTER_OTLP_ENDPOINT ou OTEL_EXPORTER_OTLP_TRACES_ENDPOINT).
//     Sem endpoint, o serviço funciona igual, com um tracer "noop".
//   - Os logs saem sempre em JSON no stdout, com trace_id/span_id quando há
//     span ativo: é o que liga um log no Loki ao trace no APM.
//   - Nada de dados do usuário em atributos de span ou logs (nem corpo da
//     requisição, nem mensagem de erro do banco): só rota, método, status e
//     o tipo do erro.

import (
	"context"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net"
	"net/http"
	"os"
	"strings"
	"sync"
	"time"

	"go.opentelemetry.io/contrib/instrumentation/net/http/otelhttp"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/codes"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp"
	"go.opentelemetry.io/otel/propagation"
	"go.opentelemetry.io/otel/sdk/resource"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	"go.opentelemetry.io/otel/trace"
	"go.opentelemetry.io/otel/trace/noop"
)

const (
	// serviceNamespace agrupa as três entidades da plataforma no APM.
	serviceNamespace = "solidarytech"
	// tracerName identifica a biblioteca que cria os spans manuais.
	tracerName = "solidarytech/donation-service"
	// healthPath fica fora dos traces e dos logs de requisição: é chamado a
	// cada poucos segundos pelas probes e só geraria ruído (e custo no APM).
	healthPath = "/health"
)

// initTelemetry configura o logger JSON padrão e, se houver endpoint OTLP,
// o TracerProvider que exporta spans por OTLP/HTTP. Devolve a função de
// desligamento, que esvazia o lote de spans pendentes antes de o processo sair.
func initTelemetry(ctx context.Context, defaultService string) (func(context.Context) error, error) {
	service := os.Getenv("OTEL_SERVICE_NAME")
	if service == "" {
		service = defaultService
	}
	slog.SetDefault(newJSONLogger(os.Stdout, service))

	// Só o contexto W3C (traceparent/tracestate). Baggage fica de fora de
	// propósito: poderia carregar dados de usuário sem necessidade.
	otel.SetTextMapPropagator(propagation.TraceContext{})
	otel.SetTracerProvider(noop.NewTracerProvider())
	noShutdown := func(context.Context) error { return nil }

	if strings.EqualFold(os.Getenv("OTEL_SDK_DISABLED"), "true") ||
		(os.Getenv("OTEL_EXPORTER_OTLP_ENDPOINT") == "" && os.Getenv("OTEL_EXPORTER_OTLP_TRACES_ENDPOINT") == "") {
		return noShutdown, nil
	}

	// O exporter lê as variáveis OTEL_EXPORTER_OTLP_*: o endpoint base recebe
	// o sufixo /v1/traces; o TRACES_ENDPOINT é usado como está.
	exporter, err := otlptracehttp.New(ctx)
	if err != nil {
		return noShutdown, errors.New("não foi possível inicializar o exporter OTLP/HTTP")
	}
	res, err := resource.New(ctx,
		resource.WithFromEnv(), // OTEL_RESOURCE_ATTRIBUTES, se houver
		resource.WithTelemetrySDK(),
		resource.WithAttributes(
			attribute.String("service.name", service),
			attribute.String("service.namespace", serviceNamespace),
		),
	)
	if err != nil {
		_ = exporter.Shutdown(ctx)
		return noShutdown, errors.New("não foi possível montar o resource do OpenTelemetry")
	}

	// Batcher: envia spans em lote, fora do caminho da requisição.
	provider := sdktrace.NewTracerProvider(sdktrace.WithResource(res), sdktrace.WithBatcher(exporter))
	otel.SetTracerProvider(provider)
	// Erros de transporte podem conter URL e cabeçalhos (com a chave do APM):
	// registrar só que a exportação falhou.
	otel.SetErrorHandler(otel.ErrorHandlerFunc(func(error) { slog.Warn("otel.export.failed") }))
	return provider.Shutdown, nil
}

// newJSONLogger cria o logger JSON: a chave "msg" vira "message" (o mesmo
// nome usado pelos serviços Python, para o Loki ler os três do mesmo jeito)
// e todo registro leva service.name (e trace_id/span_id quando houver span).
func newJSONLogger(output io.Writer, service string) *slog.Logger {
	jsonHandler := slog.NewJSONHandler(output, &slog.HandlerOptions{ReplaceAttr: func(groups []string, attr slog.Attr) slog.Attr {
		if len(groups) == 0 && attr.Key == slog.MessageKey {
			attr.Key = "message"
		}
		return attr
	}})
	return slog.New(correlationHandler{Handler: jsonHandler}).With("service.name", service)
}

// correlationHandler acrescenta trace_id e span_id do contexto ao registro.
type correlationHandler struct{ slog.Handler }

func (h correlationHandler) Handle(ctx context.Context, record slog.Record) error {
	if sc := trace.SpanContextFromContext(ctx); sc.IsValid() {
		record.AddAttrs(slog.String("trace_id", sc.TraceID().String()), slog.String("span_id", sc.SpanID().String()))
	}
	return h.Handler.Handle(ctx, record)
}

func (h correlationHandler) WithAttrs(attrs []slog.Attr) slog.Handler {
	return correlationHandler{Handler: h.Handler.WithAttrs(attrs)}
}

func (h correlationHandler) WithGroup(name string) slog.Handler {
	return correlationHandler{Handler: h.Handler.WithGroup(name)}
}

// statusWriter guarda o status HTTP escrito pelo handler, para o log.
type statusWriter struct {
	http.ResponseWriter
	status int
	wrote  bool
}

func (w *statusWriter) WriteHeader(status int) {
	if !w.wrote {
		w.status, w.wrote = status, true
		w.ResponseWriter.WriteHeader(status)
	}
}

func (w *statusWriter) Write(body []byte) (int, error) {
	if !w.wrote {
		w.WriteHeader(http.StatusOK)
	}
	return w.ResponseWriter.Write(body)
}

// Unwrap permite que o http.ResponseController alcance o writer original.
func (w *statusWriter) Unwrap() http.ResponseWriter { return w.ResponseWriter }

// instrumentHandler envolve o roteador com:
//   - um span SERVER por requisição (otelhttp), exceto /health;
//   - o atributo http.route com a rota-modelo (nunca o caminho com dados);
//   - um log JSON "http.request.completed" por requisição.
func instrumentHandler(next http.Handler) http.Handler {
	logged := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		status := &statusWriter{ResponseWriter: w, status: http.StatusOK}
		next.ServeHTTP(status, r)
		if r.URL.Path == healthPath {
			return
		}
		// r.Pattern é preenchido pelo ServeMux com o padrão que casou.
		route := r.Pattern
		if route == "" {
			route = "unmatched"
		}
		trace.SpanFromContext(r.Context()).SetAttributes(attribute.String("http.route", route))
		slog.InfoContext(r.Context(), "http.request.completed",
			"http.method", r.Method, "http.route", route, "http.status_code", status.status)
	})
	return otelhttp.NewHandler(logged, "http.request",
		otelhttp.WithFilter(func(r *http.Request) bool { return r.URL.Path != healthPath }))
}

// serveHTTP escuta em addr e atende até o contexto ser cancelado (SIGTERM).
func serveHTTP(ctx context.Context, addr string, handler http.Handler, afterRequests func()) error {
	listener, err := net.Listen("tcp", addr)
	if err != nil {
		return err
	}
	return serveHTTPListener(ctx, listener, handler, afterRequests)
}

// serveHTTPListener implementa o desligamento gracioso, nesta ordem:
//  1. ao cancelar o contexto, para de aceitar conexões (server.Shutdown);
//  2. espera as requisições em andamento terminarem (até 10 s);
//  3. chama afterRequests (aqui: esperar os eventos SQS em voo).
//
// Assim, um Pod encerrado pelo Kubernetes não corta uma doação no meio.
func serveHTTPListener(ctx context.Context, listener net.Listener, handler http.Handler, afterRequests func()) error {
	var requests sync.WaitGroup
	server := &http.Server{
		// Protege contra clientes que abrem a conexão e não mandam cabeçalho (Slowloris).
		ReadHeaderTimeout: 5 * time.Second,
		Handler: http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			requests.Add(1)
			defer requests.Done()
			handler.ServeHTTP(w, r)
		}),
	}
	result := make(chan error, 1)
	go func() { result <- server.Serve(listener) }()

	var serveErr error
	select {
	case serveErr = <-result:
	case <-ctx.Done():
	}

	// Contexto novo: o do sinal já foi cancelado.
	shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := server.Shutdown(shutdownCtx); err != nil {
		slog.Warn("http.shutdown.timeout")
		_ = server.Close()
	}
	requests.Wait()
	if afterRequests != nil {
		afterRequests()
	}
	if errors.Is(serveErr, http.ErrServerClosed) {
		return nil
	}
	return serveErr
}

// dbSpan abre um span CLIENT para uma operação no PostgreSQL, com os
// atributos das convenções semânticas (sem o texto da query nem parâmetros).
func dbSpan(ctx context.Context, operation, table string) (context.Context, trace.Span) {
	return otel.Tracer(tracerName).Start(ctx, operation+" "+table,
		trace.WithSpanKind(trace.SpanKindClient),
		trace.WithAttributes(
			attribute.String("db.system.name", "postgresql"),
			attribute.String("db.operation.name", operation),
			attribute.String("db.collection.name", table),
		))
}

// markError marca o span como erro e devolve o tipo do erro para o log.
// Só o tipo vai para o span: a mensagem pode conter dados da conexão.
func markError(span trace.Span, operation string, err error) string {
	errorType := fmt.Sprintf("%T", err)
	span.SetStatus(codes.Error, operation+" failed")
	span.SetAttributes(attribute.String("error.type", errorType))
	return errorType
}

// shutdownTelemetry esvazia os spans pendentes com prazo próprio.
func shutdownTelemetry(shutdown func(context.Context) error) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := shutdown(ctx); err != nil {
		slog.Warn("otel.shutdown.failed")
	}
}
