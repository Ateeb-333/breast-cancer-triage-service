"""Train and compare two pipeline families using malignant as positive class."""
import argparse
import json
from pathlib import Path
import sys

import joblib
import numpy as np
import pandas as pd
import sklearn
import yaml
from sklearn.ensemble import RandomForestClassifier
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import accuracy_score, recall_score, roc_auc_score
from sklearn.model_selection import StratifiedKFold, train_test_split
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler


def evaluate(model, x, y):
    labels = model.predict(x)
    classes = list(model.classes_)
    p_malignant = model.predict_proba(x)[:, classes.index(0)]
    return {
        'malignant_recall': round(float(recall_score(y, labels, pos_label=0)), 6),
        'accuracy': round(float(accuracy_score(y, labels)), 6),
        'roc_auc': round(float(roc_auc_score((y == 0).astype(int), p_malignant)), 6),
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--data-path', default='data/raw/breast_cancer.csv')
    parser.add_argument('--output-dir', default='artifacts')
    parser.add_argument('--model-version', default='1.0.0')
    parser.add_argument('--metrics-path', default='metrics.json')
    parser.add_argument('--params-path', default='params.yaml')
    args = parser.parse_args()
    params = yaml.safe_load(Path(args.params_path).read_text())
    seed = int(params['seed'])
    if seed != 42:
        raise ValueError('The assignment requires seed 42')
    df = pd.read_csv(args.data_path)
    feature_names = [col for col in df.columns if col != 'target']
    if len(feature_names) != 30 or df.isna().any().any():
        raise ValueError('Expected exactly 30 feature columns and no nulls')
    x = df.loc[:, feature_names].to_numpy(dtype=np.float64)
    y = df['target'].to_numpy(dtype=int)
    if sorted(np.unique(y).tolist()) != [0, 1]:
        raise ValueError('Expected target labels [0,1]')
    x_train, x_test, y_train, y_test = train_test_split(
        x, y, test_size=float(params['test_size']), stratify=y, random_state=seed)
    c = params['models']['logistic_regression']
    rf = params['models']['random_forest']
    models = {
        'LogisticRegression': Pipeline([
            ('scale', StandardScaler()),
            ('classifier', LogisticRegression(C=float(c['C']), max_iter=int(c['max_iter']),
                                              class_weight='balanced', random_state=seed)),
        ]),
        'RandomForest': Pipeline([
            ('classifier', RandomForestClassifier(n_estimators=int(rf['n_estimators']),
                                                  max_depth=rf['max_depth'],
                                                  class_weight='balanced',
                                                  random_state=seed, n_jobs=1)),
        ]),
    }
    cv = StratifiedKFold(n_splits=5, shuffle=True, random_state=seed)
    summary = {}
    print(f'TRAINING rows={len(df)} train={len(x_train)} test={len(x_test)} seed={seed}', flush=True)
    for name, model in models.items():
        fold_metrics = []
        for train_index, val_index in cv.split(x_train, y_train):
            model.fit(x_train[train_index], y_train[train_index])
            fold_metrics.append(evaluate(model, x_train[val_index], y_train[val_index]))
        cv_means = {key: round(float(np.mean([f[key] for f in fold_metrics])), 6)
                    for key in ('malignant_recall', 'accuracy', 'roc_auc')}
        model.fit(x_train, y_train)
        summary[name] = {'cross_validation': cv_means, 'test': evaluate(model, x_test, y_test)}
        print(f'Candidate {name}: CV={cv_means} TEST={summary[name]["test"]}', flush=True)
    # Select ONLY by highest mean CV malignant recall, with tie-breakers for determinism.
    chosen = max(summary, key=lambda key: (
        summary[key]['cross_validation']['malignant_recall'],
        summary[key]['cross_validation']['roc_auc'],
        summary[key]['cross_validation']['accuracy']))
    selected_model = models[chosen]
    selected_model.fit(x_train, y_train)
    selected_metrics = summary[chosen]['test']
    summary[chosen]['selected'] = True
    for name in summary:
        summary[name].setdefault('selected', False)
    out = Path(args.output_dir)
    out.mkdir(parents=True, exist_ok=True)
    joblib.dump(selected_model, out / 'model.joblib')
    card = {
        'model_version': args.model_version, 'model_family': chosen,
        'feature_names': feature_names, 'feature_count': len(feature_names),
        'seed': seed, 'scikit_learn_version': sklearn.__version__,
        'decision_threshold': 0.5, 'test_metrics': selected_metrics,
        'dataset_rows': len(df), 'candidates': summary,
        'positive_class': 'malignant', 'positive_class_code': 0,
        'note': 'Educational demonstration, not a clinical medical device',
    }
    (out / 'model_card.json').write_text(json.dumps(card, indent=2) + '\n')
    Path(args.metrics_path).write_text(json.dumps({
        'model_version': args.model_version, 'selected_model': chosen,
        'candidates': summary, 'selected_test_metrics': selected_metrics,
        'dataset_rows': len(df), 'seed': seed}, indent=2) + '\n')
    print(f'SELECTED {chosen}: held-out malignant recall={selected_metrics["malignant_recall"]}', flush=True)
    if selected_metrics['malignant_recall'] < 0.95:
        print('ERROR: test malignant recall below required 0.95', file=sys.stderr)
        return 1
    print('PASS: test malignant recall >= 0.95. Artifacts written.', flush=True)
    return 0

if __name__ == '__main__':
    raise SystemExit(main())
