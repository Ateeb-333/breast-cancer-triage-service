# Breast Cancer Triage API — MLOps Assignment 02

**Education only — not a medical device.** Classifies numeric breast-cancer diagnostic features for demonstration purposes. Malignant is the positive class (`target=0`). Dataset: scikit-learn Breast Cancer Wisconsin, first exported as 569 rows, then corrected to 539 rows (last 30 removed). All stochastic procedures use seed 42.

## Requirements

Apple Silicon Mac with Docker Desktop/Compose v2, Homebrew and Python 3.12. Commands below run from this repository root.

## Fast track (run scripts in this exact order)

```bash
bash scripts/01_data_dvc.sh
bash scripts/02_train_dvc.sh
bash scripts/03_docker.sh
bash scripts/04_compose.sh
bash scripts/05_publish.sh
```

The first script installs local venv dependencies, initializes Git/DVC and creates both required dataset versions. For GitHub, create an empty public repository and push `main` when done; see below. Each script prints observable evidence; save Terminal screenshots **with the command and output**. Evidence CSV and build logs go in ignored `evidence/`. Do not commit `.env`, secrets, the raw CSV, the DVC cache or model artifacts. The `dvc-remote/` folder is **intentionally committed** so a clean clone can restore the data without a cloud remote.

## Manual reproduction from a clean clone

```bash
python3.12 -m venv .venv
source .venv/bin/activate
pip install -r requirements-train.txt -r requirements-serve.txt -r requirements-dev.txt
dvc pull
# expect 539 rows
dvc repro
python -m uvicorn app.main:app --host 127.0.0.1 --port 8000
```

Open http://127.0.0.1:8000/docs for interactive API documentation.

## Docker build/run

```bash
dvc pull
docker build -f Dockerfile.naive -t breast-cancer-triage:naive .
docker build -f Dockerfile -t breast-cancer-triage:production --build-arg MODEL_VERSION=1.0.0 --build-arg GIT_SHA="$(git rev-parse --short HEAD)" .
docker run --rm -p 8091:8000 breast-cancer-triage:production
```

## Docker Compose (build locally)

```bash
cp .env.example .env # edit DOCKERHUB_USERNAME (never commit .env)
docker compose up -d --build
docker compose ps
curl -s http://localhost:8000/health
docker compose down
```

Compose publishes only the API port, uses Redis service-name discovery, a Redis healthcheck, and a named volume with AOF persistence.

## Docker Hub (public repository required)

Create `https://hub.docker.com/r/YOUR_USERNAME/breast-cancer-triage-api` as PUBLIC. Set `DOCKERHUB_USERNAME` in `.env` then:

```bash
docker login
docker compose build
# Compose image is YOUR_USERNAME/breast-cancer-triage-api:1.0.0
docker tag YOUR_USERNAME/breast-cancer-triage-api:1.0.0 YOUR_USERNAME/breast-cancer-triage-api:latest
docker push YOUR_USERNAME/breast-cancer-triage-api:1.0.0
docker push YOUR_USERNAME/breast-cancer-triage-api:latest
```

From an empty folder containing **only** `docker-compose.hub.yml` renamed to `docker-compose.yml` and your local `.env`:

```bash
docker compose pull
docker compose up -d
```

## API endpoints

| Method | Endpoint | Description |
|---|---|---|
| GET | `/health` | Always `{"status":"ok"}` independent of Redis |
| POST | `/predict` | 30 nonnegative numeric fields; missing/invalid -> HTTP 422 |
| GET | `/model/info` | Version, family, sklearn version, Git SHA, threshold, features, test metrics |
| GET | `/stats` | Redis prediction count when configured |

Prediction example:

```bash
curl -s -X POST http://localhost:8000/predict -H 'Content-Type: application/json' --data-binary @sample.json
```

Prediction response: `{"label":"malignant","malignant_probability":0.9871,"threshold":0.5,"model_version":"1.0.0"}` (probability varies). `malignant_probability` is `predict_proba` for class zero, **not** class one.

## Environment variables

Copy `.env.example`. `MODEL_PATH=/service/artifacts/model.joblib`, `DECISION_THRESHOLD=0.5`, `LOG_LEVEL=INFO`, `REDIS_HOST` unset for standalone or `redis` in Compose, `REDIS_PORT=6379`, `MODEL_VERSION=1.0.0`, `GIT_SHA` build arg, `HOST_PORT=8000`, `IMAGE_TAG=1.0.0`, and `DOCKERHUB_USERNAME`.

## GitHub submission

Create an **empty public** GitHub repository named `breast-cancer-triage-service` (do not auto-create a README). Then from the project folder:

```bash
git branch -M main
git remote add origin https://github.com/YOUR_GITHUB_USERNAME/breast-cancer-triage-service.git
git push -u origin main
```

### Evidence guide

Capture Task 5: DVC init/add/push/restore; Task 6: 569 and 539 rows, hashes/commits; Task 7: metrics and chosen model; Task 8: DVC repro executed/skipped/changed params; Task 9: `/docs` prediction; Task 10-11: image build timings, size, cached layers; Task 12: standalone prediction, inspect, health, new threshold; Tasks 13-15: Compose health, Redis `/stats` persistence/reset; Tasks 16-17: both Docker Hub public tags/digests and clean-room pull/requests. Always screenshot command **and** output.

## Written analysis (at most 150 words)

An image is an immutable package of code and dependencies; a container is a running or stopped instance created from it. Docker initially blocked image removal because a stopped container still referenced its layers. Removing the container first allowed us to remove the image safely. A process inside Docker must listen on `0.0.0.0` so Docker port publishing can reach it; binding only to `127.0.0.1` inside the container restricts access to the container itself. `-p 8000:8000` maps the host's port 8000 to container port 8000. Git stores a compact DVC pointer rather than the original CSV so source history stays small. A new clone must have the matching pointer, `.dvc/config` pointing at a reachable remote, and the remote's data objects; then `dvc pull` restores the exact dataset. Here the tiny DVC remote is intentionally included in Git as required.
