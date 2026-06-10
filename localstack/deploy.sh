#!/bin/bash
# LocalStack deployment script for the Payment Fraud Detection API
# Deploys: DynamoDB table, EventBridge bus, Lambda function, API Gateway
set -e

REGION="us-east-1"
ENDPOINT="http://localhost:4566"
TABLE_NAME="FraudDetection"
EVENT_BUS_NAME="fraud-detection"
LAMBDA_NAME="FraudDetectionHandler"
API_NAME="FraudDetectionAPI"
LAMBDA_ZIP="$(cd "$(dirname "$0")/.." && pwd)/build/distributions/fraud-detection-lambda.zip"

export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION=$REGION

echo "=== Deploying to LocalStack ==="

# Wait for LocalStack to be ready
echo "Waiting for LocalStack to be ready..."
for i in $(seq 1 30); do
  if aws --endpoint-url=$ENDPOINT sts get-caller-identity >/dev/null 2>&1; then
    echo "LocalStack is ready!"
    break
  fi
  if [ $i -eq 30 ]; then
    echo "ERROR: LocalStack did not become ready in time"
    exit 1
  fi
  sleep 2
done

# 1. Create DynamoDB table
echo ""
echo "--- Creating DynamoDB table: $TABLE_NAME ---"
aws --endpoint-url=$ENDPOINT dynamodb create-table \
  --table-name "$TABLE_NAME" \
  --key-schema \
    AttributeName=pk,KeyType=HASH \
    AttributeName=sk,KeyType=RANGE \
  --attribute-definitions \
    AttributeName=pk,AttributeType=S \
    AttributeName=sk,AttributeType=S \
    AttributeName=gsiPk,AttributeType=S \
    AttributeName=gsiSk,AttributeType=S \
  --global-secondary-indexes '[{
    "IndexName": "DecisionAuditGSI",
    "KeySchema": [
      {"AttributeName": "gsiPk", "KeyType": "HASH"},
      {"AttributeName": "gsiSk", "KeyType": "RANGE"}
    ],
    "Projection": {"ProjectionType": "ALL"}
  }]' \
  --billing-mode PAY_PER_REQUEST \
  2>/dev/null || echo "Table already exists"

echo "DynamoDB table created."

# 2. Create EventBridge bus
echo ""
echo "--- Creating EventBridge bus: $EVENT_BUS_NAME ---"
aws --endpoint-url=$ENDPOINT events create-event-bus \
  --name "$EVENT_BUS_NAME" \
  2>/dev/null || echo "Event bus already exists"

echo "EventBridge bus created."

# 3. Create Lambda function
echo ""
echo "--- Creating Lambda function: $LAMBDA_NAME ---"
aws --endpoint-url=$ENDPOINT lambda delete-function \
  --function-name "$LAMBDA_NAME" 2>/dev/null || true

aws --endpoint-url=$ENDPOINT lambda create-function \
  --function-name "$LAMBDA_NAME" \
  --runtime java17 \
  --handler "com.frauddetection.handler.FraudDetectionHandler::handleRequest" \
  --role "arn:aws:iam::000000000000:role/lambda-role" \
  --zip-file "fileb://$LAMBDA_ZIP" \
  --timeout 30 \
  --memory-size 512 \
  --environment "Variables={FRAUD_DETECTION_TABLE=$TABLE_NAME,EVENT_BUS_NAME=$EVENT_BUS_NAME,AWS_REGION=$REGION}" \
  --no-cli-pager

echo "Lambda function created."

# 4. Create REST API Gateway
echo ""
echo "--- Creating API Gateway: $API_NAME ---"

# Delete existing API if present
EXISTING_APIS=$(aws --endpoint-url=$ENDPOINT apigateway get-rest-apis --query "items[?name=='$API_NAME'].id" --output text 2>/dev/null || echo "")
for api_id in $EXISTING_APIS; do
  aws --endpoint-url=$ENDPOINT apigateway delete-rest-api --rest-api-id "$api_id" 2>/dev/null || true
done

# Create new REST API
API_ID=$(aws --endpoint-url=$ENDPOINT apigateway create-rest-api \
  --name "$API_NAME" \
  --query 'id' --output text)

echo "API ID: $API_ID"

# Get root resource ID
ROOT_ID=$(aws --endpoint-url=$ENDPOINT apigateway get-resources \
  --rest-api-id "$API_ID" \
  --query 'items[?path==`/`].id' --output text)

# Create /fraud-check resource
FRAUD_CHECK_ID=$(aws --endpoint-url=$ENDPOINT apigateway create-resource \
  --rest-api-id "$API_ID" \
  --parent-id "$ROOT_ID" \
  --path-part "fraud-check" \
  --query 'id' --output text)

# Create POST method on /fraud-check
aws --endpoint-url=$ENDPOINT apigateway put-method \
  --rest-api-id "$API_ID" \
  --resource-id "$FRAUD_CHECK_ID" \
  --http-method POST \
  --authorization-type NONE \
  --no-cli-pager

# Create Lambda integration for /fraud-check POST
LAMBDA_ARN="arn:aws:lambda:$REGION:000000000000:function:$LAMBDA_NAME"
aws --endpoint-url=$ENDPOINT apigateway put-integration \
  --rest-api-id "$API_ID" \
  --resource-id "$FRAUD_CHECK_ID" \
  --http-method POST \
  --type AWS_PROXY \
  --integration-http-method POST \
  --uri "arn:aws:apigateway:$REGION:lambda:path/2015-03-31/functions/$LAMBDA_ARN/invocations" \
  --no-cli-pager

# Create /confirm-payment resource
CONFIRM_ID=$(aws --endpoint-url=$ENDPOINT apigateway create-resource \
  --rest-api-id "$API_ID" \
  --parent-id "$ROOT_ID" \
  --path-part "confirm-payment" \
  --query 'id' --output text)

# Create POST method on /confirm-payment
aws --endpoint-url=$ENDPOINT apigateway put-method \
  --rest-api-id "$API_ID" \
  --resource-id "$CONFIRM_ID" \
  --http-method POST \
  --authorization-type NONE \
  --no-cli-pager

# Create Lambda integration for /confirm-payment POST
aws --endpoint-url=$ENDPOINT apigateway put-integration \
  --rest-api-id "$API_ID" \
  --resource-id "$CONFIRM_ID" \
  --http-method POST \
  --type AWS_PROXY \
  --integration-http-method POST \
  --uri "arn:aws:apigateway:$REGION:lambda:path/2015-03-31/functions/$LAMBDA_ARN/invocations" \
  --no-cli-pager

# Deploy the API
aws --endpoint-url=$ENDPOINT apigateway create-deployment \
  --rest-api-id "$API_ID" \
  --stage-name "local" \
  --no-cli-pager

API_URL="$ENDPOINT/restapis/$API_ID/local/_user_request_"

echo ""
echo "=== Deployment Complete ==="
echo ""
echo "API Gateway URL: $API_URL"
echo "Fraud Check endpoint: $API_URL/fraud-check"
echo "Confirm Payment endpoint: $API_URL/confirm-payment"
echo ""
echo "To use with the frontend, set:"
echo "  window.API_BASE_URL = '$API_URL'"
echo ""
echo "Or update frontend/index.html <body> tag:"
echo "  <body data-api-base-url=\"$API_URL\">"
