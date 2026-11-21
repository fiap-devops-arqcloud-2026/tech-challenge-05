package main

// sqs.go — publicação do evento de doação na fila SQS.
//
// O contrato com a fila é o mesmo do código original: o corpo da mensagem é
// o JSON da doação. A única novidade é o contexto de trace W3C
// (traceparent/tracestate) nas MessageAttributes, fora do corpo, para que um
// consumidor futuro continue o mesmo trace sem mudar o formato do evento.

import (
	"context"
	"encoding/json"
	"log/slog"
	"strings"
	"time"

	"github.com/aws/aws-sdk-go/aws"
	"github.com/aws/aws-sdk-go/aws/request"
	"github.com/aws/aws-sdk-go/service/sqs"
	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/propagation"
	"go.opentelemetry.io/otel/trace"
)

// publishTimeout limita o tempo de cada publicação: um evento preso não
// segura o desligamento do Pod para sempre.
const publishTimeout = 5 * time.Second

// messageSender é a parte do cliente SQS que o serviço usa. O *sqs.SQS do
// SDK satisfaz a interface; os testes usam um fake com a mesma assinatura.
type messageSender interface {
	SendMessageWithContext(aws.Context, *sqs.SendMessageInput, ...request.Option) (*sqs.SendMessageOutput, error)
}

// publishDonationEvent dispara a publicação em segundo plano, como no
// original (a resposta HTTP não espera a fila). Diferenças:
//   - o contexto mantém o span da requisição, mas não o cancelamento dela
//     (context.WithoutCancel): a publicação continua depois da resposta;
//   - cada publicação é contada em a.producers, para o desligamento gracioso
//     esperar os eventos em voo.
func (a *App) publishDonationEvent(ctx context.Context, d Donation) {
	if a.SqsSvc == nil {
		return // SQS não configurada: mesma regra do código original
	}
	a.producers.Add(1)
	publishCtx, cancel := context.WithTimeout(context.WithoutCancel(ctx), publishTimeout)
	go func() {
		defer a.producers.Done()
		defer cancel()
		a.sendNotificationEvent(publishCtx, d)
	}()
}

// sendNotificationEvent publica a doação na fila, dentro de um span PRODUCER.
func (a *App) sendNotificationEvent(ctx context.Context, d Donation) {
	ctx, span := otel.Tracer(tracerName).Start(ctx, "send "+queueName(a.SqsQueueURL),
		trace.WithSpanKind(trace.SpanKindProducer),
		trace.WithAttributes(
			attribute.String("messaging.system", "aws_sqs"),
			attribute.String("messaging.operation.type", "send"),
			attribute.String("messaging.operation.name", "SendMessage"),
			attribute.String("messaging.destination.name", queueName(a.SqsQueueURL)),
		))
	defer span.End()

	body, err := json.Marshal(d)
	if err != nil {
		slog.ErrorContext(ctx, "Falha ao serializar evento SQS", "error.type", markError(span, "sqs.encode", err))
		return
	}

	// Injeta o contexto W3C do span atual nos atributos da mensagem.
	carrier := propagation.MapCarrier{}
	otel.GetTextMapPropagator().Inject(ctx, carrier)
	var attrs map[string]*sqs.MessageAttributeValue
	for _, key := range []string{"traceparent", "tracestate"} {
		if value := carrier.Get(key); value != "" {
			if attrs == nil {
				attrs = make(map[string]*sqs.MessageAttributeValue, 2)
			}
			attrs[key] = &sqs.MessageAttributeValue{DataType: aws.String("String"), StringValue: aws.String(value)}
		}
	}

	_, err = a.SqsSvc.SendMessageWithContext(ctx, &sqs.SendMessageInput{
		MessageBody:       aws.String(string(body)),
		QueueUrl:          aws.String(a.SqsQueueURL),
		MessageAttributes: attrs,
	})
	if err != nil {
		slog.ErrorContext(ctx, "Falha ao despachar evento SQS", "error.type", markError(span, "sqs.send", err))
		return
	}
	slog.InfoContext(ctx, "sqs.message.sent")
}

// queueName extrai o nome da fila do fim da URL
// (https://sqs.<região>.amazonaws.com/<conta>/<nome>).
func queueName(queueURL string) string {
	if i := strings.LastIndex(queueURL, "/"); i >= 0 && i < len(queueURL)-1 {
		return queueURL[i+1:]
	}
	return "sqs"
}
