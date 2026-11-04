#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p evidence docs
read -r -p 'Enter your REAL Docker Hub username: ' HUB
[ -n "$HUB" ] || { echo 'Username required'; exit 1; }
# update local .env (never Git-commit it)
if [ ! -f .env ]; then cp .env.example .env; fi
python3 - "$HUB" <<'PY'
from pathlib import Path
import sys
p=Path('.env'); lines=p.read_text().splitlines(); key='DOCKERHUB_USERNAME='
lines=[key+sys.argv[1] if line.startswith(key) else line for line in lines]
p.write_text('\n'.join(lines)+'\n')
PY
cat > docs/milestone-5.md <<'MD'
# Milestone 5
Image is published to a PUBLIC Docker Hub repository with matching 1.0.0 and
latest tags. The clean-room Compose file has an image reference and no build.
MD
git add docs/milestone-5.md && git commit -m 'Milestone 5: publishing and clean-room instructions'
sha=$(git rev-parse --short HEAD)
repo="$HUB/breast-cancer-triage-api"
# Build with the final source Git revision so /model/info reports the published commit.
docker build -f Dockerfile --build-arg MODEL_VERSION=1.0.0 --build-arg GIT_SHA="$sha" -t "$repo:1.0.0" .
docker tag "$repo:1.0.0" "$repo:latest"
echo 'Ensure https://hub.docker.com/repositories is PUBLIC and repo breast-cancer-triage-api exists.'
docker login
docker push "$repo:1.0.0"
docker push "$repo:latest"
echo '=== PUBLISHED DIGEST (record this) ==='
docker image inspect "$repo:1.0.0" --format 'ID={{.Id}} Digest={{json .RepoDigests}}'
echo '=== CLEAN ROOM: stop local Compose; delete only our image tags ==='
docker compose down || true
docker image rm "$repo:1.0.0" "$repo:latest" || true
mkdir -p .local/clean-room
cp docker-compose.hub.yml .local/clean-room/docker-compose.yml
cp .env .local/clean-room/.env
cd .local/clean-room
docker compose pull
docker compose up -d
docker compose ps
for i in 1 2 3 4 5 6 7 8 9 10; do if curl -fsS http://127.0.0.1:8000/health; then break; fi; sleep 2; done
echo
curl -fsS http://127.0.0.1:8000/model/info; echo
curl -fsS -X POST http://127.0.0.1:8000/predict -H 'Content-Type: application/json' --data-binary @../../sample.json; echo
docker image inspect "$repo:1.0.0" --format 'Pulled digest={{json .RepoDigests}}'
echo "DOCKER HUB: https://hub.docker.com/r/$repo"
echo '=== MILESTONE 5 SUCCESS (screenshot; compare digest with Hub tag page) ==='
