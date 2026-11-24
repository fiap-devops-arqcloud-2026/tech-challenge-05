package main

// Testes do donation-service: rotas, regras de negócio preservadas,
// publicação na SQS (com contexto de trace), tracing, logs e desligamento
// gracioso. O banco é simulado com go-sqlmock e a SQS com um fake; nenhum
// teste precisa de PostgreSQL, AWS ou rede externa.

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"net"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/DATA-DOG/go-sqlmock"
	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/request"
	"github.com/aws/aws-sdk-go/service/sqs"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/propagation"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
	"go.opentelemetry.io/otel/sdk/trace/tracetest"
	"go.opentelemetry.io/otel/trace"
)

const testQueueURL = "https://sqs.us-east-2.amazonaws.com/000000000000/solidary-donations"

// fakeSender registra as mensagens que iriam para a SQS.
type fakeSender struct {
	mu       sync.Mutex
	messages []*sqs.SendMessageInput
	err      error
}

func (f *fakeSender) SendMessageWithContext(_ aws.Context, in *sqs.SendMessageInput, _ ...request.Option) (*sqs.SendMessageOutput, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.messages = append(f.messages, in)
	if f.err != nil {
		return nil, f.err
	}
	return &sqs.SendMessageOutput{MessageId: aws.String("msg-1")}, nil
}

func (f *fakeSender) sent() []*sqs.SendMessageInput {
	f.mu.Lock()
	defer f.mu.Unlock()
	return append([]*sqs.SendMessageInput(nil), f.messages...)
}

// newTestApp cria o App com banco simulado. sender pode ser nil (SQS desligada).
func newTestApp(t *testing.T, sender messageSender) (*App, sqlmock.Sqlmock) {
	t.Helper()
	db, mock, err := sqlmock.New()
	if err != nil {
		t.Fatalf("sqlmock: %v", err)
	}
	t.Cleanup(func() { _ = db.Close() })
	return &App{DB: db, SqsSvc: sender, SqsQueueURL: testQueueURL}, mock
}

// useInMemoryTracer liga um TracerProvider que guarda os spans em memória
// e restaura o estado global no fim do teste.
func useInMemoryTracer(t *testing.T) *tracetest.InMemoryExporter {
	t.Helper()
	exporter := tracetest.NewInMemoryExporter()
	provider := sdktrace.NewTracerProvider(sdktrace.WithSyncer(exporter))
	previousProvider, previousPropagator := otel.GetTracerProvider(), otel.GetTextMapPropagator()
	otel.SetTracerProvider(provider)
	otel.SetTextMapPropagator(propagation.TraceContext{})
	t.Cleanup(func() {
		_ = provider.Shutdown(context.Background())
		otel.SetTracerProvider(previousProvider)
		otel.SetTextMapPropagator(previousPropagator)
	})
	return exporter
}

func doRequest(handler http.Handler, method, path, body string) *httptest.ResponseRecorder {
	req := httptest.NewRequest(method, path, strings.NewReader(body))
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)
	return rec
}

func expectInsert(mock sqlmock.Sqlmock, createdAt time.Time) {
	mock.ExpectQuery("INSERT INTO donations").
		WithArgs(1, 50.5, "Maria", "APPROVED").
		WillReturnRows(sqlmock.NewRows([]string{"id", "created_at"}).AddRow(7, createdAt))
}

func TestHealth(t *testing.T) {
	app, _ := newTestApp(t, nil)
	rec := doRequest(app.routes(), http.MethodGet, "/health", "")

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, esperado 200", rec.Code)
	}
	if got := rec.Header().Get("Content-Type"); got != "application/json" {
		t.Errorf("Content-Type = %q", got)
	}
	if got := strings.TrimSpace(rec.Body.String()); got != `{"status":"ok","service":"donation-service"}` {
		t.Errorf("corpo = %s", got)
	}
}

func TestCreateDonationApprovesAndPublishes(t *testing.T) {
	sender := &fakeSender{}
	app, mock := newTestApp(t, sender)
	createdAt := time.Date(2026, 11, 20, 12, 0, 0, 0, time.UTC)
	expectInsert(mock, createdAt)

	rec := doRequest(app.routes(), http.MethodPost, "/donations", `{"ngo_id":1,"amount":50.5,"donor_name":"Maria"}`)
	app.producers.Wait() // a publicação é assíncrona

	if rec.Code != http.StatusCreated {
		t.Fatalf("status = %d, esperado 201; corpo: %s", rec.Code, rec.Body.String())
	}
	var got Donation
	if err := json.Unmarshal(rec.Body.Bytes(), &got); err != nil {
		t.Fatalf("resposta não é JSON: %v", err)
	}
	want := Donation{ID: 7, NgoID: 1, Amount: 50.5, DonorName: "Maria", Status: "APPROVED", CreatedAt: createdAt}
	if got != want {
		t.Errorf("doação = %+v, esperado %+v", got, want)
	}

	messages := sender.sent()
	if len(messages) != 1 {
		t.Fatalf("mensagens SQS = %d, esperado 1", len(messages))
	}
	if aws.StringValue(messages[0].QueueUrl) != testQueueURL {
		t.Errorf("QueueUrl = %s", aws.StringValue(messages[0].QueueUrl))
	}
	// Contrato preservado: o corpo é o JSON da doação, como no original.
	var event Donation
	if err := json.Unmarshal([]byte(aws.StringValue(messages[0].MessageBody)), &event); err != nil || event != want {
		t.Errorf("corpo da mensagem = %s (erro %v)", aws.StringValue(messages[0].MessageBody), err)
	}
	// Sem tracing ativo não há contexto para propagar.
	if messages[0].MessageAttributes != nil {
		t.Errorf("MessageAttributes deveria ser nil sem tracing: %v", messages[0].MessageAttributes)
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Error(err)
	}
}

func TestCreateDonationPropagatesTraceContext(t *testing.T) {
	exporter := useInMemoryTracer(t)
	sender := &fakeSender{}
	app, mock := newTestApp(t, sender)
	expectInsert(mock, time.Now().UTC())

	rec := doRequest(app.routes(), http.MethodPost, "/donations", `{"ngo_id":1,"amount":50.5,"donor_name":"Maria"}`)
	app.producers.Wait()
	if rec.Code != http.StatusCreated {
		t.Fatalf("status = %d", rec.Code)
	}

	spans := exporter.GetSpans()
	byKind := map[trace.SpanKind]tracetest.SpanStub{}
	for _, s := range spans {
		byKind[s.SpanKind] = s
	}
	server, client, producer := byKind[trace.SpanKindServer], byKind[trace.SpanKindClient], byKind[trace.SpanKindProducer]
	if len(spans) != 3 || server.Name == "" || client.Name != "INSERT donations" || producer.Name != "send solidary-donations" {
		t.Fatalf("spans inesperados: %+v", spans)
	}
	traceID := server.SpanContext.TraceID()
	if client.SpanContext.TraceID() != traceID || producer.SpanContext.TraceID() != traceID {
		t.Errorf("os spans não pertencem ao mesmo trace")
	}
	route := ""
	for _, kv := range server.Attributes {
		if kv.Key == "http.route" {
			route = kv.Value.AsString()
		}
	}
	if route != "/donations" {
		t.Errorf("http.route = %q, esperado /donations", route)
	}

	// O traceparent da mensagem aponta para o span PRODUCER.
	messages := sender.sent()
	if len(messages) != 1 || messages[0].MessageAttributes["traceparent"] == nil {
		t.Fatalf("mensagem sem traceparent: %+v", messages)
	}
	traceparent := aws.StringValue(messages[0].MessageAttributes["traceparent"].StringValue)
	wantPrefix := "00-" + traceID.String() + "-" + producer.SpanContext.SpanID().String()
	if !strings.HasPrefix(traceparent, wantPrefix) {
		t.Errorf("traceparent = %s, esperado prefixo %s", traceparent, wantPrefix)
	}
}

func TestCreateDonationInvalidPayload(t *testing.T) {
	sender := &fakeSender{}
	app, mock := newTestApp(t, sender)

	rec := doRequest(app.routes(), http.MethodPost, "/donations", `{"ngo_id":`)
	app.producers.Wait()

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, esperado 400", rec.Code)
	}
	if len(sender.sent()) != 0 {
		t.Error("payload inválido não pode publicar evento")
	}
	if err := mock.ExpectationsWereMet(); err != nil {
		t.Error(err)
	}
}

func TestCreateDonationDatabaseError(t *testing.T) {
	sender := &fakeSender{}
	app, mock := newTestApp(t, sender)
	mock.ExpectQuery("INSERT INTO donations").WillReturnError(errors.New("conexão perdida"))

	rec := doRequest(app.routes(), http.MethodPost, "/donations", `{"ngo_id":1,"amount":50.5,"donor_name":"Maria"}`)
	app.producers.Wait()

	if rec.Code != http.StatusInternalServerError {
		t.Fatalf("status = %d, esperado 500", rec.Code)
	}
	if len(sender.sent()) != 0 {
		t.Error("doação não gravada não pode publicar evento")
	}
}

func TestCreateDonationWithoutSQS(t *testing.T) {
	app, mock := newTestApp(t, nil)
	expectInsert(mock, time.Now().UTC())

	rec := doRequest(app.routes(), http.MethodPost, "/donations", `{"ngo_id":1,"amount":50.5,"donor_name":"Maria"}`)
	app.producers.Wait()

	if rec.Code != http.StatusCreated {
		t.Fatalf("status = %d, esperado 201", rec.Code)
	}
}

func TestSQSFailureDoesNotChangeResponse(t *testing.T) {
	sender := &fakeSender{err: errors.New("fila indisponível")}
	app, mock := newTestApp(t, sender)
	expectInsert(mock, time.Now().UTC())

	rec := doRequest(app.routes(), http.MethodPost, "/donations", `{"ngo_id":1,"amount":50.5,"donor_name":"Maria"}`)
	app.producers.Wait()

	// Como no original: a doação já foi gravada; a falha da fila só é registrada.
	if rec.Code != http.StatusCreated || len(sender.sent()) != 1 {
		t.Fatalf("status = %d, tentativas = %d", rec.Code, len(sender.sent()))
	}
}

func TestListDonations(t *testing.T) {
	app, mock := newTestApp(t, nil)
	now := time.Date(2026, 11, 20, 12, 0, 0, 0, time.UTC)
	mock.ExpectQuery("SELECT id, ngo_id, amount, donor_name, status, created_at FROM donations").
		WillReturnRows(sqlmock.NewRows([]string{"id", "ngo_id", "amount", "donor_name", "status", "created_at"}).
			AddRow(2, 1, 10.0, "Ana", "APPROVED", now).
			AddRow(1, 2, 25.5, "Bruno", "APPROVED", now))

	rec := doRequest(app.routes(), http.MethodGet, "/donations", "")

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d", rec.Code)
	}
	var got []Donation
	if err := json.Unmarshal(rec.Body.Bytes(), &got); err != nil {
		t.Fatalf("resposta não é JSON: %v", err)
	}
	if len(got) != 2 || got[0].ID != 2 || got[1].DonorName != "Bruno" {
		t.Errorf("lista = %+v", got)
	}
}

func TestListDonationsEmptyReturnsArray(t *testing.T) {
	app, mock := newTestApp(t, nil)
	mock.ExpectQuery("SELECT id").WillReturnRows(sqlmock.NewRows([]string{"id", "ngo_id", "amount", "donor_name", "status", "created_at"}))

	rec := doRequest(app.routes(), http.MethodGet, "/donations", "")

	if got := strings.TrimSpace(rec.Body.String()); got != "[]" {
		t.Errorf("lista vazia = %s, esperado []", got)
	}
}

func TestMethodNotAllowed(t *testing.T) {
	app, _ := newTestApp(t, nil)
	rec := doRequest(app.routes(), http.MethodDelete, "/donations", "")
	if rec.Code != http.StatusMethodNotAllowed {
		t.Fatalf("status = %d, esperado 405", rec.Code)
	}
}

func TestHealthIsNotTraced(t *testing.T) {
	exporter := useInMemoryTracer(t)
	app, _ := newTestApp(t, nil)

	doRequest(app.routes(), http.MethodGet, "/health", "")

	if spans := exporter.GetSpans(); len(spans) != 0 {
		t.Errorf("/health gerou %d span(s)", len(spans))
	}
}

func TestJSONLoggerAddsTraceID(t *testing.T) {
	useInMemoryTracer(t)
	var buf bytes.Buffer
	logger := newJSONLogger(&buf, "donation-service")
	ctx, span := otel.Tracer("teste").Start(context.Background(), "operacao")
	logger.InfoContext(ctx, "evento.teste")
	span.End()

	var record map[string]any
	if err := json.Unmarshal(buf.Bytes(), &record); err != nil {
		t.Fatalf("log não é JSON: %v (%s)", err, buf.String())
	}
	if record["message"] != "evento.teste" || record["service.name"] != "donation-service" {
		t.Errorf("campos = %v", record)
	}
	if record["trace_id"] != span.SpanContext().TraceID().String() {
		t.Errorf("trace_id = %v, esperado %s", record["trace_id"], span.SpanContext().TraceID())
	}
}

func TestGracefulShutdownWaitsForInFlightWork(t *testing.T) {
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	started := make(chan struct{})
	var mu sync.Mutex
	order := []string{}
	handler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		close(started)
		time.Sleep(300 * time.Millisecond) // requisição lenta em andamento
		w.WriteHeader(http.StatusOK)
		mu.Lock()
		order = append(order, "handler")
		mu.Unlock()
	})

	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan error, 1)
	go func() {
		done <- serveHTTPListener(ctx, listener, handler, func() {
			mu.Lock()
			order = append(order, "afterRequests")
			mu.Unlock()
		})
	}()

	response := make(chan int, 1)
	go func() {
		resp, err := http.Get("http://" + listener.Addr().String() + "/donations")
		if err != nil {
			response <- -1
			return
		}
		_ = resp.Body.Close()
		response <- resp.StatusCode
	}()

	<-started
	cancel() // simula o SIGTERM no meio da requisição

	if code := <-response; code != http.StatusOK {
		t.Fatalf("requisição em andamento foi cortada (status %d)", code)
	}
	if err := <-done; err != nil {
		t.Fatalf("serveHTTPListener retornou erro: %v", err)
	}
	mu.Lock()
	defer mu.Unlock()
	// afterRequests (espera dos eventos SQS) só roda depois do handler terminar.
	if len(order) != 2 || order[0] != "handler" || order[1] != "afterRequests" {
		t.Errorf("ordem = %v, esperado [handler afterRequests]", order)
	}
}

func TestQueueName(t *testing.T) {
	cases := map[string]string{
		testQueueURL: "solidary-donations",
		"http://moto:5000/000000000000/fila-local": "fila-local",
		"":                     "sqs",
		"https://sqs.example/": "sqs",
	}
	for url, want := range cases {
		if got := queueName(url); got != want {
			t.Errorf("queueName(%q) = %q, esperado %q", url, got, want)
		}
	}
}
