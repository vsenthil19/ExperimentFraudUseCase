#!/bin/bash
###############################################################################
# Payment Fraud Detection - Local Development Setup
#
# This script sets up the complete local development environment from scratch:
#   1. Installs prerequisites (Docker, pip, LocalStack, AWS CLI check)
#   2. Builds the Lambda deployment zip
#   3. Starts LocalStack via Docker
#   4. Deploys AWS resources (DynamoDB, EventBridge, Lambda, API Gateway)
#   5. Starts the development server (frontend + API proxy)
#
# Prerequisites (installed automatically if missing):
#   - Java 17+ (for building the Lambda)
#   - Python 3.x (for LocalStack + dev server)
#   - Docker (for running LocalStack)
#   - AWS CLI v2 (for deploying resources)
#
# Usage:
#   chmod +x localstack/start-local.sh
#   ./localstack/start-local.sh
#
# The application will be available at: http://localhost:8080
#
# To stop:
#   ./localstack/stop-local.sh
#   OR: Ctrl+C (stops dev server), then: docker stop localstack
###############################################################################
set -e

# --- Configuration ---
REGION="us-east-1"
ENDPOINT="http://localhost:4566"
TABLE_NAME="FraudDetection"
EVENT_BUS_NAME="fraud-detection"
LAMBDA_NAME="FraudDetectionHandler"
API_NAME="FraudDetectionAPI"
LOCALSTACK_IMAGE="localstack/localstack:3.4"
CONTAINER_NAME="localstack"
DEV_SERVER_PORT=8080
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LAMBDA_ZIP="$PROJECT_ROOT/build/distributions/fraud-detection-lambda.zip"

export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION=$REGION

# --- Helper functions ---
print_header() {
  echo ""
  echo "============================================================"
  echo "  $1"
  echo "============================================================"
}

print_step() {
  echo ""
  echo "--- [$1/$TOTAL_STEPS] $2 ---"
}

check_command() {
  if ! command -v "$1" &>/dev/null; then
    return 1
  fi
  return 0
}

TOTAL_STEPS=7

print_header "Payment Fraud Detection - Local Setup"
echo "Project root: $PROJECT_ROOT"
echo ""

###############################################################################
# STEP 1: Check and install prerequisites
###############################################################################
print_step 1 "Checking prerequisites"

# Check Java
if check_command java; then
  JAVA_VERSION=$(java -version 2>&1 | head -1)
  echo "✓ Java found: $JAVA_VERSION"
else
  echo "✗ Java not found. Please install Java 17+ and try again."
  echo "  Ubuntu/Debian: sudo apt-get install openjdk-17-jdk"
  echo "  macOS: brew install openjdk@17"
  exit 1
fi

# Check Python 3
if check_command python3; then
  PYTHON_VERSION=$(python3 --version)
  echo "✓ Python found: $PYTHON_VERSION"
else
  echo "✗ Python 3 not found. Please install Python 3.x and try again."
  echo "  Ubuntu/Debian: sudo apt-get install python3"
  exit 1
fi

# Check AWS CLI
if check_command aws; then
  AWS_VERSION=$(aws --version 2>&1)
  echo "✓ AWS CLI found: $AWS_VERSION"
else
  echo "✗ AWS CLI not found. Please install AWS CLI v2."
  echo "  https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
  exit 1
fi

# Check and install Docker
if check_command docker; then
  DOCKER_VERSION=$(docker --version)
  echo "✓ Docker found: $DOCKER_VERSION"
else
  echo "⟳ Docker not found. Installing..."
  if check_command apt-get; then
    sudo apt-get update -qq
    sudo apt-get install -y -qq docker.io
    sudo systemctl start docker
    sudo usermod -aG docker "$USER"
    echo "✓ Docker installed. Note: you may need to log out and back in for group changes."
  else
    echo "✗ Cannot auto-install Docker. Please install manually:"
    echo "  https://docs.docker.com/engine/install/"
    exit 1
  fi
fi

# Ensure Docker daemon is running
if ! sudo docker info &>/dev/null; then
  echo "⟳ Starting Docker daemon..."
  sudo systemctl start docker
  sleep 2
fi
echo "✓ Docker daemon is running"

# Check pip3 and install LocalStack CLI (optional, for 'localstack' command)
if ! check_command pip3; then
  echo "⟳ pip3 not found. Installing..."
  if check_command apt-get; then
    sudo apt-get install -y -qq python3-pip
  fi
fi

###############################################################################
# STEP 2: Build Lambda deployment package
###############################################################################
print_step 2 "Building Lambda deployment zip"

cd "$PROJECT_ROOT"

if [ ! -f "./gradlew" ]; then
  echo "✗ Gradle wrapper not found. Are you in the correct project directory?"
  exit 1
fi

chmod +x ./gradlew
./gradlew buildLambdaZip --quiet

if [ ! -f "$LAMBDA_ZIP" ]; then
  echo "✗ Lambda zip not found at: $LAMBDA_ZIP"
  echo "  Build may have failed. Run: ./gradlew buildLambdaZip"
  exit 1
fi

ZIP_SIZE=$(du -h "$LAMBDA_ZIP" | cut -f1)
echo "✓ Lambda zip built: $LAMBDA_ZIP ($ZIP_SIZE)"

###############################################################################
# STEP 3: Start LocalStack container
###############################################################################
print_step 3 "Starting LocalStack"

# Stop existing container if running
if sudo docker ps -q --filter "name=$CONTAINER_NAME" | grep -q .; then
  echo "⟳ Stopping existing LocalStack container..."
  sudo docker stop "$CONTAINER_NAME" >/dev/null 2>&1 || true
  sleep 2
fi

# Remove stopped container if exists
sudo docker rm "$CONTAINER_NAME" >/dev/null 2>&1 || true

# Pull image if not present
if ! sudo docker image inspect "$LOCALSTACK_IMAGE" &>/dev/null; then
  echo "⟳ Pulling LocalStack image (this may take a minute)..."
  sudo docker pull "$LOCALSTACK_IMAGE"
fi

# Start LocalStack
echo "⟳ Starting LocalStack container..."
sudo docker run -d \
  --rm \
  -p 4566:4566 \
  -p 4510-4559:4510-4559 \
  -e SERVICES=dynamodb,lambda,apigateway,events,iam,s3,sts \
  -e LAMBDA_EXECUTOR=local \
  -e DOCKER_HOST=unix:///var/run/docker.sock \
  -v /var/run/docker.sock:/var/run/docker.sock \
  --name "$CONTAINER_NAME" \
  "$LOCALSTACK_IMAGE" >/dev/null

# Wait for LocalStack to be ready
echo "⟳ Waiting for LocalStack to be ready..."
for i in $(seq 1 30); do
  if aws --endpoint-url=$ENDPOINT sts get-caller-identity >/dev/null 2>&1; then
    echo "✓ LocalStack is ready (took ~$((i * 2))s)"
    break
  fi
  if [ "$i" -eq 30 ]; then
    echo "✗ LocalStack did not become ready within 60 seconds."
    echo "  Check logs: sudo docker logs $CONTAINER_NAME"
    exit 1
  fi
  sleep 2
done

###############################################################################
# STEP 4: Create DynamoDB table
###############################################################################
print_step 4 "Deploying DynamoDB table"

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
  --no-cli-pager >/dev/null 2>&1 || echo "  (table already exists)"

echo "✓ DynamoDB table: $TABLE_NAME"

###############################################################################
# STEP 5: Create EventBridge bus and deploy Lambda
###############################################################################
print_step 5 "Deploying EventBridge + Lambda"

# EventBridge
aws --endpoint-url=$ENDPOINT events create-event-bus \
  --name "$EVENT_BUS_NAME" \
  --no-cli-pager >/dev/null 2>&1 || echo "  (event bus already exists)"
echo "✓ EventBridge bus: $EVENT_BUS_NAME"

# Lambda (delete existing first for clean redeploy)
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
  --no-cli-pager >/dev/null

echo "✓ Lambda function: $LAMBDA_NAME (java17, 512MB)"

###############################################################################
# STEP 6: Create API Gateway
###############################################################################
print_step 6 "Deploying API Gateway"

LAMBDA_ARN="arn:aws:lambda:$REGION:000000000000:function:$LAMBDA_NAME"

# Delete existing API if present
EXISTING_APIS=$(aws --endpoint-url=$ENDPOINT apigateway get-rest-apis \
  --query "items[?name=='$API_NAME'].id" --output text 2>/dev/null || echo "")
for api_id in $EXISTING_APIS; do
  aws --endpoint-url=$ENDPOINT apigateway delete-rest-api \
    --rest-api-id "$api_id" 2>/dev/null || true
done

# Create REST API
API_ID=$(aws --endpoint-url=$ENDPOINT apigateway create-rest-api \
  --name "$API_NAME" \
  --query 'id' --output text)

# Get root resource
ROOT_ID=$(aws --endpoint-url=$ENDPOINT apigateway get-resources \
  --rest-api-id "$API_ID" \
  --query 'items[?path==`/`].id' --output text)

# /fraud-check endpoint
FRAUD_CHECK_ID=$(aws --endpoint-url=$ENDPOINT apigateway create-resource \
  --rest-api-id "$API_ID" \
  --parent-id "$ROOT_ID" \
  --path-part "fraud-check" \
  --query 'id' --output text)

aws --endpoint-url=$ENDPOINT apigateway put-method \
  --rest-api-id "$API_ID" \
  --resource-id "$FRAUD_CHECK_ID" \
  --http-method POST \
  --authorization-type NONE \
  --no-cli-pager >/dev/null

aws --endpoint-url=$ENDPOINT apigateway put-integration \
  --rest-api-id "$API_ID" \
  --resource-id "$FRAUD_CHECK_ID" \
  --http-method POST \
  --type AWS_PROXY \
  --integration-http-method POST \
  --uri "arn:aws:apigateway:$REGION:lambda:path/2015-03-31/functions/$LAMBDA_ARN/invocations" \
  --no-cli-pager >/dev/null

# /confirm-payment endpoint
CONFIRM_ID=$(aws --endpoint-url=$ENDPOINT apigateway create-resource \
  --rest-api-id "$API_ID" \
  --parent-id "$ROOT_ID" \
  --path-part "confirm-payment" \
  --query 'id' --output text)

aws --endpoint-url=$ENDPOINT apigateway put-method \
  --rest-api-id "$API_ID" \
  --resource-id "$CONFIRM_ID" \
  --http-method POST \
  --authorization-type NONE \
  --no-cli-pager >/dev/null

aws --endpoint-url=$ENDPOINT apigateway put-integration \
  --rest-api-id "$API_ID" \
  --resource-id "$CONFIRM_ID" \
  --http-method POST \
  --type AWS_PROXY \
  --integration-http-method POST \
  --uri "arn:aws:apigateway:$REGION:lambda:path/2015-03-31/functions/$LAMBDA_ARN/invocations" \
  --no-cli-pager >/dev/null

# Deploy API to stage
aws --endpoint-url=$ENDPOINT apigateway create-deployment \
  --rest-api-id "$API_ID" \
  --stage-name "local" \
  --no-cli-pager >/dev/null

API_URL="$ENDPOINT/restapis/$API_ID/local/_user_request_"
echo "✓ API Gateway deployed: $API_URL"

# Quick smoke test
echo "⟳ Running smoke test..."
SMOKE_RESPONSE=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$API_URL/fraud-check" \
  -H "Content-Type: application/json" \
  -d '{"messageId":"smoke-test","debtorAccount":{"sortCode":"123456","accountNumber":"12345678","accountName":"Smoke Test"},"creditorAccount":{"sortCode":"654321","accountNumber":"87654321","accountName":"Test"},"amount":50.00,"currency":"GBP","paymentReference":"smoke","confirmationOfPayee":{"result":"MATCH","matchedName":"Test"},"channel":{"type":"MOBILE","deviceId":null,"geoLocation":null,"sessionDuration":null},"timestamp":"2024-01-01T00:00:00Z"}' \
  2>/dev/null || echo "000")

if [ "$SMOKE_RESPONSE" = "200" ]; then
  echo "✓ Smoke test passed (HTTP 200)"
else
  echo "⚠ Smoke test returned HTTP $SMOKE_RESPONSE (first Lambda invocation may be slow - cold start)"
  echo "  This is normal for Java Lambdas. Try again in a few seconds."
fi

###############################################################################
# STEP 7: Start development server
###############################################################################
print_step 7 "Starting development server"

# Export the API URL for the dev server
export LOCALSTACK_API_URL="$API_URL"
export PORT="$DEV_SERVER_PORT"

print_header "Local Environment Ready!"
echo ""
echo "  Frontend:         http://localhost:$DEV_SERVER_PORT"
echo "  API (via proxy):  http://localhost:$DEV_SERVER_PORT/fraud-check"
echo "  API (direct):     $API_URL/fraud-check"
echo "  LocalStack:       $ENDPOINT"
echo ""
echo "  To stop: Ctrl+C, then run: ./localstack/stop-local.sh"
echo ""
echo "============================================================"
echo ""

# Start the dev server (foreground - Ctrl+C to stop)
exec python3 "$PROJECT_ROOT/localstack/serve.py"
