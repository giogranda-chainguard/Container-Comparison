#!/usr/bin/env bash
set -euo pipefail
docker rm -f cg-demo-upstream cg-demo-chainguard >/dev/null 2>&1 || true
if [ -f .demo/scanner.pid ]; then
  kill "$(cat .demo/scanner.pid)" >/dev/null 2>&1 || true
  rm -f .demo/scanner.pid
fi
echo "Chainguard nginx migration demo stopped."
