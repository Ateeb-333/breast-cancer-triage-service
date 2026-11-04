# syntax=docker/dockerfile:1
FROM python:3.12.16-slim-bookworm AS trainer
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1
WORKDIR /service
COPY requirements-train.txt ./
RUN pip install --no-cache-dir -r requirements-train.txt
COPY training/ ./training/
COPY params.yaml ./params.yaml
COPY data/raw/breast_cancer.csv ./data/raw/breast_cancer.csv
ARG MODEL_VERSION=1.0.0
RUN python -m training.train --data-path data/raw/breast_cancer.csv --output-dir artifacts --model-version "$MODEL_VERSION"

FROM python:3.12.16-slim-bookworm AS runtime
ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 \
    MODEL_PATH=/service/artifacts/model.joblib DECISION_THRESHOLD=0.5 \
    LOG_LEVEL=INFO REDIS_PORT=6379
WORKDIR /service
COPY requirements-serve.txt ./
RUN pip install --no-cache-dir -r requirements-serve.txt \
    && groupadd --system triage && useradd --system --gid triage --create-home triage
COPY --chown=triage:triage app/ ./app/
COPY --from=trainer --chown=triage:triage /service/artifacts/ ./artifacts/
ARG MODEL_VERSION=1.0.0
ARG GIT_SHA=unknown
ENV MODEL_VERSION=${MODEL_VERSION} GIT_SHA=${GIT_SHA}
LABEL org.opencontainers.image.version="${MODEL_VERSION}" \
      org.opencontainers.image.revision="${GIT_SHA}" \
      org.opencontainers.image.title="breast-cancer-triage-api"
USER triage
EXPOSE 8000
HEALTHCHECK --interval=10s --timeout=3s --start-period=15s --retries=3 \
  CMD ["python", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=2)"]
ENTRYPOINT ["python", "-m", "uvicorn"]
CMD ["app.main:app", "--host", "0.0.0.0", "--port", "8000"]
