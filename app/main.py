"""FastAPI screening triage demo. Never intended for medical decision-making."""
from contextlib import asynccontextmanager
import json
import logging
import os
from pathlib import Path
import sys

import joblib
from fastapi import FastAPI, Request
from pydantic import ConfigDict, Field, create_model
import redis

FEATURES = [
    'mean_radius', 'mean_texture', 'mean_perimeter', 'mean_area',
    'mean_smoothness', 'mean_compactness', 'mean_concavity', 'mean_concave_points',
    'mean_symmetry', 'mean_fractal_dimension',
    'radius_error', 'texture_error', 'perimeter_error', 'area_error',
    'smoothness_error', 'compactness_error', 'concavity_error', 'concave_points_error',
    'symmetry_error', 'fractal_dimension_error',
    'worst_radius', 'worst_texture', 'worst_perimeter', 'worst_area',
    'worst_smoothness', 'worst_compactness', 'worst_concavity',
    'worst_concave_points', 'worst_symmetry', 'worst_fractal_dimension',
]

PredictionInput = create_model(
    'PredictionInput', __config__=ConfigDict(extra='forbid'),
    **{name: (float, Field(..., ge=0, strict=True)) for name in FEATURES},
)
logger = logging.getLogger('triage')


@asynccontextmanager
async def lifespan(app: FastAPI):
    logging.basicConfig(level=getattr(logging, os.getenv('LOG_LEVEL', 'INFO').upper(), logging.INFO),
                        stream=sys.stdout, format='%(asctime)s %(levelname)s %(message)s')
    model_path = Path(os.environ.get('MODEL_PATH', 'artifacts/model.joblib'))
    card_path = model_path.with_name('model_card.json')
    if not model_path.exists() or not card_path.exists():
        logger.error('Model artifact missing: %s or %s', model_path, card_path)
        raise RuntimeError('Model artifacts missing. Train first or set MODEL_PATH correctly.')
    app.state.model = joblib.load(model_path)
    app.state.card = json.loads(card_path.read_text())
    if app.state.card['feature_names'] != FEATURES:
        raise RuntimeError('Model feature order does not match API schema')
    threshold = float(os.getenv('DECISION_THRESHOLD', '0.5'))
    if not 0 <= threshold <= 1:
        raise RuntimeError('DECISION_THRESHOLD must be between 0 and 1')
    app.state.threshold = threshold
    app.state.malignant_index = list(app.state.model.classes_).index(0)
    host = os.getenv('REDIS_HOST', '').strip()
    app.state.redis = (redis.Redis(host=host, port=int(os.getenv('REDIS_PORT', '6379')),
                                   decode_responses=True, socket_connect_timeout=0.4,
                                   socket_timeout=0.4) if host else None)
    logger.info('Model loaded once: %s, version=%s, threshold=%s, redis=%s',
                model_path, app.state.card['model_version'], threshold, bool(host))
    yield

app = FastAPI(title='Breast Cancer Triage API (Educational Only)',
              description='Education-only ML screening demo; not a medical device.',
              version='1.0.0', lifespan=lifespan)


@app.get('/health')
def health():
    return {'status': 'ok'}


@app.post('/predict')
def predict(payload: PredictionInput, request: Request):
    row = [[getattr(payload, name) for name in FEATURES]]
    probability = float(request.app.state.model.predict_proba(row)[0][request.app.state.malignant_index])
    threshold = request.app.state.threshold
    label = 'malignant' if probability >= threshold else 'benign'
    client = request.app.state.redis
    if client is not None:
        try:
            client.incr('predictions_served')
        except redis.RedisError as exc:
            logger.warning('Redis unavailable, prediction still served: %s', exc)
    logger.info('Prediction served, result=%s', label)
    return {'label': label, 'malignant_probability': round(probability, 4),
            'threshold': threshold, 'model_version': request.app.state.card['model_version']}


@app.get('/model/info')
def model_info(request: Request):
    card = request.app.state.card
    return {
        'model_version': os.getenv('MODEL_VERSION', card['model_version']),
        'model_family': card['model_family'],
        'scikit_learn_version': card['scikit_learn_version'],
        'git_commit': os.getenv('GIT_SHA', 'local-development'),
        'decision_threshold': request.app.state.threshold,
        'feature_count': card['feature_count'],
        'test_metrics': card['test_metrics'],
    }


@app.get('/stats')
def stats(request: Request):
    client = request.app.state.redis
    if client is None:
        return {'predictions_served': 0, 'redis_enabled': False}
    try:
        return {'predictions_served': int(client.get('predictions_served') or 0),
                'redis_enabled': True}
    except redis.RedisError as exc:
        logger.warning('Redis unavailable for /stats: %s', exc)
        return {'predictions_served': None, 'redis_enabled': True, 'redis_available': False}
