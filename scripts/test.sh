#!/bin/bash
set -e

awsl() {
  aws --endpoint-url=http://localhost:4566 "$@"
}

export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION=us-east-1

echo "=== 1. Obteniendo API_ID de API Gateway ==="
API_ID=$(awsl apigatewayv2 get-apis --query "Items[?Name=='gamecloud-api'].ApiId | [0]" --output text)

if [ -z "$API_ID" ] || [ "$API_ID" == "None" ]; then
  echo "Error: No se encontró la API 'gamecloud-api'. Ejecuta primero scripts/deploy.sh."
  exit 1
fi

API_URL="http://$API_ID.execute-api.localhost:4566"
echo "API URL detectada: $API_URL"

echo "=== 2. Enviando puntajes de prueba para Doom y Pac-Man (POST /scores) ==="
echo "Enviando puntaje Doom - Slayer99..."
curl -s -X POST "$API_URL/scores" -H "Content-Type: application/json" -d '{"juego": "doom", "jugador": "Slayer99", "puntaje": 9500}'
echo ""

echo "Enviando puntaje Doom - Marine..."
curl -s -X POST "$API_URL/scores" -H "Content-Type: application/json" -d '{"juego": "doom", "jugador": "Marine", "puntaje": 12000}'
echo ""

echo "Enviando puntaje Pac-Man - GhostBuster..."
curl -s -X POST "$API_URL/scores" -H "Content-Type: application/json" -d '{"juego": "pacman", "jugador": "GhostBuster", "puntaje": 4300}'
echo ""

echo "Enviando puntaje Pac-Man - PacFan..."
curl -s -X POST "$API_URL/scores" -H "Content-Type: application/json" -d '{"juego": "pacman", "jugador": "PacFan", "puntaje": 8100}'
echo ""

echo "=== 3. Esperando procesamiento asíncrono (SQS -> procesar_puntaje -> DynamoDB)... ==="
sleep 4

echo "=== 4. Consultando Ranking de Doom (GET /ranking?juego=doom) ==="
curl -s "$API_URL/ranking?juego=doom"
echo ""

echo "=== 5. Consultando Ranking de Pac-Man (GET /ranking?juego=pacman) ==="
curl -s "$API_URL/ranking?juego=pacman"
echo ""

echo "=== 6. Verificando registros guardados en la tabla DynamoDB 'Puntajes' ==="
awsl dynamodb scan --table-name Puntajes

echo "=== 7. Verificando métricas de mensajes en Colas SQS ==="
echo "Mensajes pendientes en cola principal:"
awsl sqs get-queue-attributes --queue-url http://localhost:4566/000000000000/puntajes --attribute-names ApproximateNumberOfMessages ApproximateNumberOfMessagesNotVisible

echo "Mensajes en Dead Letter Queue (DLQ):"
awsl sqs get-queue-attributes --queue-url http://localhost:4566/000000000000/puntajes-dlq --attribute-names ApproximateNumberOfMessages

echo "=== 8. Verificando hosting estático en S3 (gamecloud-web) ==="
awsl s3 ls s3://gamecloud-web/

echo "¡Pruebas del flujo completo E2E finalizadas exitosamente!"
