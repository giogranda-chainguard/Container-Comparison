# Chainguard nginx Migration Demo

A local side-by-side demo comparing the current public `nginx:latest` image with
`cgr.dev/chainguard/nginx:latest`.

## Prerequisites (macOS)

- Docker CLI + a running Docker engine (Docker Desktop or Colima)
- Python 3
- Trivy

Install Trivy with Homebrew if needed:

    brew install trivy

## Run

    cd chainguard-nginx-migration-demo
    ./start-demo.sh

The script pulls both current images and starts:

- Upstream nginx: http://localhost:8081
- Chainguard nginx: http://localhost:8082
- Local scan API: http://127.0.0.1:9090

Both web pages remain up at the same time. Click **Scan this image with Trivy**
to perform a live vulnerability scan of the exact image ID that was pulled at
demo startup.

## Stop

    ./stop-demo.sh

## What the demo highlights

The upstream container maps host 8081 -> container 80.
The Chainguard container maps host 8082 -> container 8080.

This intentionally exposes one of the practical changes encountered when moving
from the traditional nginx image to the non-root Chainguard nginx image.

## Security note

The scanner API listens only on 127.0.0.1 and accepts only two hard-coded scan
targets captured by start-demo.sh. It does not accept arbitrary shell commands
or arbitrary image names from the browser.

## Troubleshooting

Check containers:

    docker ps -a

Check scanner:

    curl http://127.0.0.1:9090/health
    cat .demo/scanner.log

Test sites:

    curl http://localhost:8081
    curl http://localhost:8082

The first Trivy scan may take longer while its vulnerability database is
downloaded or updated.
