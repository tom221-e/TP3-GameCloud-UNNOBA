#!/bin/bash
set -e

# Configuración de función aux para comandos awsl
awsl() {
  aws --endpoint-url=http://localhost:4566 "$@"
}

echo "=== 1. Exportando variables de entorno ==="
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION=us-east-1

echo "=== 2. Creando Bucket S3 y subiendo el Frontend ==="
awsl s3 mb s3://gamecloud-web
awsl s3 website s3://gamecloud-web/ --index-document index.html
awsl s3 cp web/index.html s3://gamecloud-web/

echo "=== 3. Creando distribución en CloudFront ==="
awsl cloudfront create-distribution --origin-domain-name gamecloud-web.s3.amazonaws.com

echo "=== 4. Creando tabla DynamoDB (Puntajes) ==="
awsl dynamodb create-table \
  --table-name Puntajes \
  --attribute-definitions \
      AttributeName=juego,AttributeType=S \
      AttributeName=jugador,AttributeType=S \
  --key-schema \
      AttributeName=juego,KeyType=HASH \
      AttributeName=jugador,KeyType=RANGE \
  --billing-mode PAY_PER_REQUEST

echo "=== 5. Creando Colas SQS (DLQ y Principal) ==="
awsl sqs create-queue --queue-name puntajes-dlq

DLQ_ARN=$(awsl sqs get-queue-attributes \
  --queue-url http://localhost:4566/000000000000/puntajes-dlq \
  --attribute-names QueueArn \
  --query "Attributes.QueueArn" --output text)

awsl sqs create-queue --queue-name puntajes \
  --attributes '{"VisibilityTimeout":"30","RedrivePolicy":"{\"deadLetterTargetArn\":\"'"$DLQ_ARN"'\",\"maxReceiveCount\":\"3\"}"}'

echo "=== 6. Creando Rol e Integración IAM ==="
awsl iam create-role \
  --role-name gamecloud-lambda-role \
  --assume-role-policy-document file://iam/trust-lambda.json

awsl iam put-role-policy \
  --role-name gamecloud-lambda-role \
  --policy-name gamecloud-lambda-policy \
  --policy-document file://iam/politica-lambdas.json

echo "=== 7. Empaquetando y Desplegando Funciones Lambda ==="
# Generar archivos .zip
(cd lambdas && zip -q ranking.zip ranking.py)
(cd lambdas && zip -q recibir.zip recibir_puntaje.py)
(cd lambdas && zip -q procesar.zip procesar_puntaje.py)

# Lambda: ranking
awsl lambda create-function \
  --function-name ranking \
  --runtime python3.12 \
  --role arn:aws:iam::000000000000:role/gamecloud-lambda-role \
  --handler ranking.lambda_handler \
  --zip-file fileb://lambdas/ranking.zip \
  --environment "Variables={TABLE_NAME=Puntajes}"

# Lambda: recibir_puntaje
awsl lambda create-function \
  --function-name recibir_puntaje \
  --runtime python3.12 \
  --role arn:aws:iam::000000000000:role/gamecloud-lambda-role \
  --handler recibir_puntaje.lambda_handler \
  --zip-file fileb://lambdas/recibir.zip \
  --environment "Variables={QUEUE_URL=http://localhost:4566/000000000000/puntajes}"

# Lambda: procesar_puntaje
awsl lambda create-function \
  --function-name procesar_puntaje \
  --runtime python3.12 \
  --role arn:aws:iam::000000000000:role/gamecloud-lambda-role \
  --handler procesar_puntaje.lambda_handler \
  --zip-file fileb://lambdas/procesar.zip \
  --environment "Variables={TABLE_NAME=Puntajes}"

echo "=== 8. Vinculando SQS con Lambda Procesar ==="
QUEUE_ARN=$(awsl sqs get-queue-attributes \
  --queue-url http://localhost:4566/000000000000/puntajes \
  --attribute-names QueueArn \
  --query "Attributes.QueueArn" --output text)

awsl lambda create-event-source-mapping \
  --function-name procesar_puntaje \
  --event-source-arn $QUEUE_ARN \
  --batch-size 10

echo "=== 9. Configurando API Gateway ==="
API_ID=$(awsl apigatewayv2 create-api \
  --name gamecloud-api \
  --protocol-type HTTP \
  --cors-configuration AllowMethods="GET,POST,OPTIONS",AllowOrigins="*",AllowHeaders="*" \
  --query 'ApiId' --output text)

RANKING_ARN=$(awsl lambda get-function --function-name ranking --query 'Configuration.FunctionArn' --output text)
RECIBIR_ARN=$(awsl lambda get-function --function-name recibir_puntaje --query 'Configuration.FunctionArn' --output text)

INT_RANKING=$(awsl apigatewayv2 create-integration --api-id $API_ID --integration-type AWS_PROXY --integration-uri $RANKING_ARN --payload-format-version 2.0 --query 'IntegrationId' --output text)
INT_RECIBIR=$(awsl apigatewayv2 create-integration --api-id $API_ID --integration-type AWS_PROXY --integration-uri $RECIBIR_ARN --payload-format-version 2.0 --query 'IntegrationId' --output text)

awsl apigatewayv2 create-route --api-id $API_ID --route-key "GET /ranking" --target "integrations/$INT_RANKING"
awsl apigatewayv2 create-route --api-id $API_ID --route-key "POST /scores" --target "integrations/$INT_RECIBIR"

awsl lambda add-permission --function-name ranking --statement-id apigw-get --action lambda:InvokeFunction --principal apigateway.amazonaws.com --source-arn "arn:aws:execute-api:us-east-1:000000000000:$API_ID/*/*/ranking"
awsl lambda add-permission --function-name recibir_puntaje --statement-id apigw-post --action lambda:InvokeFunction --principal apigateway.amazonaws.com --source-arn "arn:aws:execute-api:us-east-1:000000000000:$API_ID/*/*/scores"

awsl apigatewayv2 create-stage \
  --api-id $API_ID \
  --stage-name '$default' \
  --auto-deploy \
  --default-route-settings ThrottlingBurstLimit=200,ThrottlingRateLimit=100

echo "=== 10. Inyectando API_ID en config.js y subiendo a S3 ==="
echo "window.GAMECLOUD_API = \"http://$API_ID.execute-api.localhost:4566\";" > web/config.js
awsl s3 cp web/config.js s3://gamecloud-web/

echo "¡Despliegue automatizado finalizado con éxito!"
