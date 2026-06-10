# Local Development Environment

Run the full Payment Fraud Detection stack locally using LocalStack.

## Quick Start

```bash
./localstack/start-local.sh
```

This single command handles everything:
1. Checks prerequisites (Java 17+, Python 3, Docker, AWS CLI)
2. Installs Docker if missing (Ubuntu/Debian only)
3. Builds the Lambda deployment zip via Gradle
4. Starts LocalStack in Docker
5. Creates DynamoDB table (`FraudDetection`) with GSI
6. Creates EventBridge bus (`fraud-detection`)
7. Deploys the `FraudDetectionHandler` Lambda (Java 17, 512MB)
8. Creates API Gateway with `/fraud-check` and `/confirm-payment` routes
9. Runs a smoke test against the deployed API
10. Starts the development server at http://localhost:8080

## Stopping

```bash
./localstack/stop-local.sh
```

Or: `Ctrl+C` to stop the dev server, then `docker stop localstack`.

## Architecture

```
Browser (http://localhost:8080)
    │
    ├── GET /* ──────────────────► Python dev server (serves frontend/ files)
    │
    ├── POST /fraud-check ──────► Proxy ──► LocalStack API Gateway ──► Lambda
    │
    └── POST /confirm-payment ──► Stub response (backend not yet implemented)
```

The dev server (`serve.py`) acts as a reverse proxy that:
- Serves static frontend files from `frontend/`
- Proxies `/fraud-check` requests to the LocalStack API Gateway
- Stubs `/confirm-payment` with a success response (no backend handler exists yet)
- Adds CORS headers to all responses

## Prerequisites

| Tool | Version | Purpose |
|------|---------|---------|
| Java | 17+ | Build the Lambda zip |
| Python | 3.x | Run the dev server |
| Docker | Any | Run LocalStack |
| AWS CLI | v2 | Deploy resources to LocalStack |
| Gradle | (wrapper) | Build system (included in project) |

## Configuration

Environment variables (all optional):

| Variable | Default | Description |
|----------|---------|-------------|
| `PORT` | `8080` | Dev server port |
| `LOCALSTACK_API_URL` | Auto-detected | Override LocalStack API URL |

## File Overview

| File | Purpose |
|------|---------|
| `start-local.sh` | Complete setup from scratch |
| `stop-local.sh` | Tear down the local environment |
| `deploy.sh` | Deploy AWS resources only (assumes LocalStack is running) |
| `serve.py` | Dev server with API proxy |

## Troubleshooting

### First Lambda call is slow
Java 17 Lambdas have a cold start of 5-15 seconds on LocalStack. Subsequent calls are fast.

### "Unable to connect" in the browser
The dev server proxy handles CORS. Make sure the frontend `data-api-base-url` is set to `""` (empty string) in `index.html` so API calls go through the same-origin proxy.

### Docker permission denied
Run `sudo usermod -aG docker $USER` and log out/in, or prefix docker commands with `sudo`.

### Port 8080 already in use
Set a different port: `PORT=9090 ./localstack/start-local.sh`

### LocalStack container won't start
Check if the port is in use: `lsof -i :4566`
Check Docker logs: `docker logs localstack`
