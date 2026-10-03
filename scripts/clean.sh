#!/bin/bash

awsl() {
  aws --endpoint-url=http://localhost:4566 "$@"
}

export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION=us-east-1

echo "=== 1. Eliminando API Gateway ==="
API_ID=$(awsl apigatewayv2 get-apis --query "Items[?Name=='gamecloud-api'].ApiId | [0]" --output text)
if [ -n "$API_ID" ] && [ "$API_ID" != "None" ]; then
  awsl apigatewayv2 delete-api --api-id "$API_ID"
  echo "API Gateway $API_ID eliminado."
fi

echo "=== 2. Eliminando Mapeo de Eventos (SQS -> Lambda) ==="
MAPPINGS=$(awsl lambda list-event-source-mappings --query "EventSourceMappings[*].UUID" --output text)
for MAPPING in $MAPPINGS; do
  if [ "$MAPPING" != "None" ] && [ -n "$MAPPING" ]; then
    awsl lambda delete-event-source-mapping --uuid "$MAPPING" >/dev/null 2>&1
  fi
done

echo "=== 3. Eliminando Funciones Lambda ==="
awsl lambda delete-function --function-name ranking >/dev/null 2>&1 || true
awsl lambda delete-function --function-name recibir_puntaje >/dev/null 2>&1 || true
awsl lambda delete-function --function-name procesar_puntaje >/dev/null 2>&1 || true

echo "=== 4. Eliminando Politica y Rol IAM ==="
awsl iam delete-role-policy --role-name gamecloud-lambda-role --policy-name gamecloud-lambda-policy >/dev/null 2>&1 || true
awsl iam delete-role --role-name gamecloud-lambda-role >/dev/null 2>&1 || true

echo "=== 5. Eliminando Colas SQS ==="
awsl sqs delete-queue --queue-url http://localhost:4566/000000000000/puntajes >/dev/null 2>&1 || true
awsl sqs delete-queue --queue-url http://localhost:4566/000000000000/puntajes-dlq >/dev/null 2>&1 || true

echo "=== 6. Eliminando Tabla DynamoDB ==="
awsl dynamodb delete-table --table-name Puntajes >/dev/null 2>&1 || true

echo "=== 7. Vaciando y Eliminando Bucket S3 ==="
awsl s3 rm s3://gamecloud-web --recursive >/dev/null 2>&1 || true
awsl s3 rb s3://gamecloud-web >/dev/null 2>&1 || true

echo "=== 8. Eliminando Distribuciones de CloudFront ==="
DISTS=$(awsl cloudfront list-distributions --query "DistributionList.Items[*].Id" --output text 2>/dev/null || true)
for DIST in $DISTS; do
  if [ "$DIST" != "None" ] && [ -n "$DIST" ]; then
    awsl cloudfront delete-distribution --id "$DIST" >/dev/null 2>&1 || true
  fi
done

echo "=== 9. Eliminando archivo de configuración generado ==="
rm -f web/config.js

echo "¡Limpieza completa de la infraestructura finalizada con éxito!"
