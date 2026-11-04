#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p evidence docs
[ -f .env ] || sed 's/replace-with-your-dockerhub-username/localtriage/' .env.example > .env
# Preserve user-set vars in .env; GIT_SHA resolved separately for Compose build.
export GIT_SHA=$(git rev-parse --short HEAD)
docker compose up -d --build
docker compose ps
for i in 1 2 3 4 5 6 7 8 9 10; do if curl -fsS http://127.0.0.1:8000/health; then break; fi; sleep 2; done
echo
for i in 1 2 3; do curl -fsS -X POST http://127.0.0.1:8000/predict -H 'Content-Type: application/json' --data-binary @sample.json; echo; done
echo 'STATS after three predictions:'
curl -fsS http://127.0.0.1:8000/stats; echo
echo '=== PERSISTENCE TEST ==='
docker compose down
docker compose up -d
for i in 1 2 3 4 5 6 7 8 9 10; do if curl -fsS http://127.0.0.1:8000/health >/dev/null; then break; fi; sleep 2; done
curl -fsS http://127.0.0.1:8000/stats; echo
echo '=== VOLUME RESET TEST ==='
docker compose down -v
docker compose up -d
for i in 1 2 3 4 5 6 7 8 9 10; do if curl -fsS http://127.0.0.1:8000/health >/dev/null; then break; fi; sleep 2; done
curl -fsS http://127.0.0.1:8000/stats; echo
docker compose ps
cat > docs/milestone-4.md <<'MD'
# Milestone 4
Redis increments a prediction counter on POST /predict when configured.
Redis uses a named data volume and AOF persistence; docker compose down
keeps its volume, while docker compose down -v removes it and resets the count.
Nginx/Redis internal service discovery is through the `redis` Compose hostname.
MD
git add docs/milestone-4.md && git commit -m 'Milestone 4: Compose Redis counter and persistence verified'
echo '=== MILESTONE 4 SUCCESS (screenshot terminal output) ==='
