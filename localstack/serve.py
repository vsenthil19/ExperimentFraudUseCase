#!/usr/bin/env python3
"""
Local development server that serves the frontend files and proxies API requests
to LocalStack, handling CORS properly.

Usage: python3 localstack/serve.py
Frontend: http://localhost:8080
API proxy: http://localhost:8080/fraud-check -> LocalStack
"""
import http.server
import json
import os
import sys
import urllib.request
import urllib.error

FRONTEND_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "frontend")
LOCALSTACK_API_URL = os.environ.get("LOCALSTACK_API_URL", "")
PORT = int(os.environ.get("PORT", "8080"))

# Auto-detect the LocalStack API URL if not set
if not LOCALSTACK_API_URL:
    import subprocess
    try:
        result = subprocess.run(
            ["aws", "--endpoint-url=http://localhost:4566", "apigateway", "get-rest-apis",
             "--query", "items[0].id", "--output", "text", "--region", "us-east-1"],
            capture_output=True, text=True,
            env={**os.environ, "AWS_ACCESS_KEY_ID": "test", "AWS_SECRET_ACCESS_KEY": "test"}
        )
        api_id = result.stdout.strip()
        if api_id and api_id != "None":
            LOCALSTACK_API_URL = f"http://localhost:4566/restapis/{api_id}/local/_user_request_"
            print(f"Auto-detected LocalStack API: {LOCALSTACK_API_URL}")
        else:
            print("WARNING: Could not detect LocalStack API. API proxying will not work.")
            LOCALSTACK_API_URL = ""
    except Exception as e:
        print(f"WARNING: Could not detect LocalStack API: {e}")
        LOCALSTACK_API_URL = ""


class DevHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=FRONTEND_DIR, **kwargs)

    def do_OPTIONS(self):
        """Handle CORS preflight."""
        self.send_response(200)
        self._add_cors_headers()
        self.end_headers()

    def do_POST(self):
        """Proxy POST requests to LocalStack API."""
        if self.path == "/fraud-check":
            self._proxy_to_localstack()
        elif self.path == "/confirm-payment":
            self._handle_confirm_payment()
        else:
            self.send_error(404)

    def _handle_confirm_payment(self):
        """Stub for confirm-payment — backend doesn't implement this yet.
        Returns a success response so the UI flow works end-to-end."""
        content_length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(content_length) if content_length > 0 else b""
        try:
            data = json.loads(body) if body else {}
        except json.JSONDecodeError:
            data = {}
        
        response = json.dumps({
            "messageId": data.get("messageId", "unknown"),
            "status": "CONFIRMED",
            "message": "Payment confirmed and submitted for processing"
        })
        self.send_response(200)
        self._add_cors_headers()
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(response.encode())

    def _proxy_to_localstack(self):
        if not LOCALSTACK_API_URL:
            self.send_response(503)
            self._add_cors_headers()
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({"error": "LocalStack API not available"}).encode())
            return

        # Read request body
        content_length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(content_length) if content_length > 0 else b""

        # Forward to LocalStack
        target_url = LOCALSTACK_API_URL + self.path
        req = urllib.request.Request(
            target_url,
            data=body,
            headers={"Content-Type": "application/json"},
            method="POST"
        )

        try:
            with urllib.request.urlopen(req, timeout=15) as resp:
                response_body = resp.read()
                self.send_response(resp.status)
                self._add_cors_headers()
                self.send_header("Content-Type", "application/json")
                self.end_headers()
                self.wfile.write(response_body)
        except urllib.error.HTTPError as e:
            response_body = e.read()
            self.send_response(e.code)
            self._add_cors_headers()
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(response_body)
        except urllib.error.URLError as e:
            self.send_response(502)
            self._add_cors_headers()
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({"error": f"Backend unavailable: {e.reason}"}).encode())
        except Exception as e:
            self.send_response(500)
            self._add_cors_headers()
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({"error": str(e)}).encode())

    def _add_cors_headers(self):
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")

    def log_message(self, format, *args):
        """Cleaner log output."""
        sys.stderr.write(f"[{self.log_date_time_string()}] {format % args}\n")


if __name__ == "__main__":
    server = http.server.HTTPServer(("0.0.0.0", PORT), DevHandler)
    print(f"\n{'='*50}")
    print(f"Payment Fraud UI - Local Development Server")
    print(f"{'='*50}")
    print(f"Frontend:  http://localhost:{PORT}")
    print(f"API Proxy: http://localhost:{PORT}/fraud-check")
    print(f"           http://localhost:{PORT}/confirm-payment")
    print(f"Backend:   {LOCALSTACK_API_URL or 'NOT CONFIGURED'}")
    print(f"{'='*50}\n")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down...")
        server.shutdown()
