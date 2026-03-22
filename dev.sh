#!/usr/bin/env bash
set -euo pipefail

BACKEND_DIR="$(cd "$(dirname "$0")/backend" && pwd)"
FRONTEND_DIR="$(cd "$(dirname "$0")/frontend" && pwd)"
BINARY=/tmp/algoroute
PORT=8080

echo "==> Building frontend..."
cd "$FRONTEND_DIR"
npm run build

echo "==> Building backend..."
cd "$BACKEND_DIR"
go build -o "$BINARY" .

echo "==> Starting server on port $PORT..."
"$BINARY" -serve -port "$PORT" &
SERVER_PID=$!

# Give the server a moment to start
sleep 1

echo "==> Opening browser..."
open "http://localhost:$PORT"

echo "==> Server running (PID $SERVER_PID). Press Ctrl+C to stop."
trap "kill $SERVER_PID 2>/dev/null; echo '==> Server stopped.'" EXIT
wait "$SERVER_PID"
