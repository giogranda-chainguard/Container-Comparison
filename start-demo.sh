#!/usr/bin/env bash
set -euo pipefail

UPSTREAM_IMAGE="${UPSTREAM_IMAGE:-nginx:latest}"
CHAINGUARD_IMAGE="${CHAINGUARD_IMAGE:-cgr.dev/chainguard/nginx:latest}"
UPSTREAM_PORT="${UPSTREAM_PORT:-8081}"
CHAINGUARD_PORT="${CHAINGUARD_PORT:-8082}"
SCANNER_PORT="${SCANNER_PORT:-9090}"

need() {
  command -v "$1" >/dev/null 2>&1 || { echo "ERROR: '$1' is required."; exit 1; }
}

need docker
need python3
need curl

docker info >/dev/null 2>&1 || {
  echo "ERROR: Docker is not reachable. Start Docker Desktop/Colima and try again."
  exit 1
}

if ! command -v trivy >/dev/null 2>&1; then
  echo "ERROR: Trivy is required."
  echo "On macOS with Homebrew: brew install trivy"
  exit 1
fi

echo "==> Pulling current images"
docker pull "$UPSTREAM_IMAGE"
docker pull "$CHAINGUARD_IMAGE"

echo "==> Capturing immutable image IDs"
UPSTREAM_ID="$(docker image inspect "$UPSTREAM_IMAGE" --format '{{.Id}}')"
CHAINGUARD_ID="$(docker image inspect "$CHAINGUARD_IMAGE" --format '{{.Id}}')"

echo "==> Removing prior demo containers"
docker rm -f cg-demo-upstream cg-demo-chainguard >/dev/null 2>&1 || true

echo "==> Starting upstream nginx on http://localhost:${UPSTREAM_PORT}"
docker run -d --name cg-demo-upstream \
  -p "${UPSTREAM_PORT}:80" \
  -v "$(pwd)/site:/demo-site:ro" \
  -v "$(pwd)/.demo:/usr/share/nginx/html/.demo:ro" \
  -v "$(pwd)/site/upstream.html:/usr/share/nginx/html/index.html:ro" \
  -v "$(pwd)/site/style.css:/usr/share/nginx/html/style.css:ro" \
  -v "$(pwd)/site/app.js:/usr/share/nginx/html/app.js:ro" \
  "$UPSTREAM_IMAGE" >/dev/null

echo "==> Starting Chainguard nginx on http://localhost:${CHAINGUARD_PORT}"
docker run -d --name cg-demo-chainguard \
  -p "${CHAINGUARD_PORT}:8080" \
  -v "$(pwd)/site/chainguard.html:/usr/share/nginx/html/index.html:ro" \
  -v "$(pwd)/site/style.css:/usr/share/nginx/html/style.css:ro" \
  -v "$(pwd)/site/app.js:/usr/share/nginx/html/app.js:ro" \
  -v "$(pwd)/.demo:/usr/share/nginx/html/.demo:ro" \
  "$CHAINGUARD_IMAGE" >/dev/null

metadata() {
  local image="$1"
  local container="$2"
  local port="$3"
  local kind="$4"
  local size user nginxver iid digest

  size="$(docker image inspect "$image" --format '{{.Size}}')"
  user="$(docker image inspect "$image" --format '{{.Config.User}}')"
  iid="$(docker image inspect "$image" --format '{{.Id}}')"
  digest="$(docker image inspect "$image" --format '{{join .RepoDigests ", "}}' 2>/dev/null || true)"
  nginxver="$(docker logs "$container" 2>&1 | head -1 || true)"

  python3 - "$image" "$container" "$port" "$kind" "$size" "$user" "$nginxver" "$iid" "$digest" <<'PY'
import json,sys
keys=["image","container","port","kind","size","user","nginx_version","image_id","digest"]
print(json.dumps(dict(zip(keys,sys.argv[1:])), separators=(",",":")))
PY
}

mkdir -p .demo
metadata "$UPSTREAM_IMAGE" cg-demo-upstream "$UPSTREAM_PORT" upstream > .demo/upstream.json
metadata "$CHAINGUARD_IMAGE" cg-demo-chainguard "$CHAINGUARD_PORT" chainguard > .demo/chainguard.json

echo "==> Starting local Trivy scan API on http://127.0.0.1:${SCANNER_PORT}"
if [ -f .demo/scanner.pid ] && kill -0 "$(cat .demo/scanner.pid)" 2>/dev/null; then
  kill "$(cat .demo/scanner.pid)" 2>/dev/null || true
fi

UPSTREAM_IMAGE="$UPSTREAM_IMAGE" \
UPSTREAM_ID="$UPSTREAM_ID" \
CHAINGUARD_IMAGE="$CHAINGUARD_IMAGE" \
CHAINGUARD_ID="$CHAINGUARD_ID" \
SCANNER_PORT="$SCANNER_PORT" \
nohup python3 scanner/server.py > .demo/scanner.log 2>&1 &
echo $! > .demo/scanner.pid

sleep 2

echo
echo "Demo is running:"
echo "  Upstream nginx:   http://localhost:${UPSTREAM_PORT}"
echo "  Chainguard nginx: http://localhost:${CHAINGUARD_PORT}"
echo
echo "Click 'Scan this image with Trivy' on either page."
echo "First scan may take longer while Trivy updates its vulnerability database."
echo
echo "To stop: ./stop-demo.sh"

if command -v open >/dev/null 2>&1; then
  open "http://localhost:${UPSTREAM_PORT}"
  open "http://localhost:${CHAINGUARD_PORT}"
fi
