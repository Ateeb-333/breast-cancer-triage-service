#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p evidence docs .local
[ -f data/raw/breast_cancer.csv ] || { echo 'Missing dataset. Run source .venv/bin/activate && dvc pull'; exit 1; }
sha=$(git rev-parse --short HEAD)
echo '=== BASELINE COLD BUILD ==='
t0=$(date +%s)
docker build --no-cache -f Dockerfile.naive -t breast-cancer-triage:naive --build-arg MODEL_VERSION=1.0.0 . > evidence/m3_naive_cold.log 2>&1 || { tail -50 evidence/m3_naive_cold.log; exit 1; }
naive_cold=$(($(date +%s)-t0))
echo '=== PRODUCTION COLD BUILD ==='
t0=$(date +%s)
docker build --no-cache -f Dockerfile -t breast-cancer-triage:production --build-arg MODEL_VERSION=1.0.0 --build-arg GIT_SHA="$sha" . > evidence/m3_prod_cold.log 2>&1 || { tail -50 evidence/m3_prod_cold.log; exit 1; }
prod_cold=$(($(date +%s)-t0))
cp app/main.py .local/main.py.backup
trap 'cp .local/main.py.backup app/main.py' EXIT
printf '\n# Milestone 3 cache timing: harmless code comment.\n' >> app/main.py
echo '=== BASELINE REBUILD AFTER APP CODE EDIT ==='
t0=$(date +%s)
docker build -f Dockerfile.naive -t breast-cancer-triage:naive --build-arg MODEL_VERSION=1.0.0 . > evidence/m3_naive_rebuild.log 2>&1 || { tail -50 evidence/m3_naive_rebuild.log; exit 1; }
naive_rebuild=$(($(date +%s)-t0))
echo '=== OPTIMIZED REBUILD AFTER APP CODE EDIT ==='
t0=$(date +%s)
docker build -f Dockerfile -t breast-cancer-triage:production --build-arg MODEL_VERSION=1.0.0 --build-arg GIT_SHA="$sha" . > evidence/m3_prod_rebuild.log 2>&1 || { tail -50 evidence/m3_prod_rebuild.log; exit 1; }
prod_rebuild=$(($(date +%s)-t0))
cp .local/main.py.backup app/main.py
trap - EXIT
# restore final production image with unchanged code

docker build -f Dockerfile -t breast-cancer-triage:production --build-arg MODEL_VERSION=1.0.0 --build-arg GIT_SHA="$sha" . > evidence/m3_prod_final.log 2>&1 || { tail -50 evidence/m3_prod_final.log; exit 1; }
naive_size=$(docker image inspect breast-cancer-triage:naive --format '{{.Size}}')
prod_size=$(docker image inspect breast-cancer-triage:production --format '{{.Size}}')
printf 'Image,Base,Size bytes,Cold build sec,Rebuild sec,Runtime user\nnaive,ubuntu:24.04,%s,%s,%s,root\nproduction,python:3.12.16-slim-bookworm,%s,%s,%s,triage (non-root)\n' "$naive_size" "$naive_cold" "$naive_rebuild" "$prod_size" "$prod_cold" "$prod_rebuild" | tee evidence/table3_image_sizes.csv
printf 'Saving layer cache proof to evidence/m3_prod_rebuild.log\n'
grep -E 'CACHED|COPY app|pip install' evidence/m3_prod_rebuild.log | tail -18 || true
printf 'Non-root, port, healthcheck:\n'
docker image inspect breast-cancer-triage:production --format 'User={{.Config.User}} ExposedPorts={{json .Config.ExposedPorts}} Healthcheck={{json .Config.Healthcheck}}'
docker history --format 'table {{.CreatedBy}}\t{{.Size}}' breast-cancer-triage:production | head -12
docker rm -f mlops-standalone mlops-threshold >/dev/null 2>&1 || true
docker run -d --name mlops-standalone -p 8091:8000 breast-cancer-triage:production
for i in 1 2 3 4 5 6 7 8 9 10; do if curl -fsS http://127.0.0.1:8091/health; then break; fi; sleep 2; done
echo
curl -fsS http://127.0.0.1:8091/model/info; echo
curl -fsS http://127.0.0.1:8091/predict -H 'Content-Type: application/json' --data-binary @sample.json; echo
sleep 10
docker inspect mlops-standalone --format 'Health: {{.State.Health.Status}}'
docker logs --tail 8 mlops-standalone
docker run -d --name mlops-threshold -p 8092:8000 -e DECISION_THRESHOLD=0.1 breast-cancer-triage:production
for i in 1 2 3 4 5 6 7 8 9 10; do if curl -fsS http://127.0.0.1:8092/health >/dev/null; then break; fi; sleep 2; done
curl -fsS http://127.0.0.1:8092/model/info; echo
docker rm -f mlops-standalone mlops-threshold
echo 'Optimized image saves space through slim runtime, absence of training dependencies/dataset, and layer caching.' > docs/milestone-3.md
git add docs/milestone-3.md && git commit -m 'Milestone 3: Docker image measurement and optimization evidence'
echo '=== MILESTONE 3 SUCCESS (screenshot console, inspect evidence/*.log) ==='
