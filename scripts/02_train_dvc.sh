#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
source .venv/bin/activate
mkdir -p evidence docs
if [ ! -f data/raw/breast_cancer.csv ]; then dvc pull; fi
echo '=== FIRST DVC REPRO (should run) ==='
dvc repro
echo '=== SECOND DVC REPRO (should skip: unchanged) ==='
dvc repro
echo '=== MODIFY ONE HYPERPARAMETER ==='
python - <<'PY'
from pathlib import Path
p=Path('params.yaml')
s=p.read_text()
if 'C: 0.15' in s: s=s.replace('C: 0.15','C: 0.14')
elif 'C: 0.14' in s: s=s.replace('C: 0.14','C: 0.15')
else: raise RuntimeError('Unexpected C hyperparameter; edit params.yaml manually')
p.write_text(s)
PY
echo '=== THIRD DVC REPRO (should re-run due to changed params) ==='
dvc repro
python - <<'PY'
import json,csv
m=json.load(open('metrics.json'))
with open('evidence/table2_model_metrics.csv','w',newline='') as f:
 w=csv.writer(f);w.writerow(['Model','Selected','CV malignant recall','CV accuracy','CV ROC AUC','Test malignant recall','Test accuracy','Test ROC AUC'])
 for name,item in m['candidates'].items():
  cv=item['cross_validation']; te=item['test'];w.writerow([name,item['selected'],cv['malignant_recall'],cv['accuracy'],cv['roc_auc'],te['malignant_recall'],te['accuracy'],te['roc_auc']])
print('MODEL METRICS:');print(json.dumps(m,indent=2))
PY
cat > docs/milestone-2.md <<'MD'
# Milestone 2
Two scikit-learn Pipelines are compared with 5-fold stratified CV and seed 42.
The chosen model maximizes cross-validation malignant recall (class 0 is positive).
The model and model card are DVC-tracked outputs, not committed to Git.
The pipeline was run once, rerun without edits, then rerun after changing C.
MD
git add -A
if ! git diff --cached --quiet; then git commit -m 'Milestone 2: DVC training pipeline and FastAPI service'; fi
if [ ! -f .env ]; then sed 's/replace-with-your-dockerhub-username/localtriage/' .env.example > .env; fi
echo '=== LOCAL API TEST ==='
python -m uvicorn app.main:app --host 127.0.0.1 --port 8095 > evidence/m2_local_api.log 2>&1 &
server_pid=$!
trap 'kill "$server_pid" >/dev/null 2>&1 || true' EXIT
for i in 1 2 3 4 5 6 7 8 9 10; do if curl -fsS http://127.0.0.1:8095/health; then break; fi; sleep 1; done
echo
curl -fsS http://127.0.0.1:8095/model/info; echo
curl -fsS http://127.0.0.1:8095/predict -H 'content-type: application/json' --data-binary @sample.json; echo
curl -s -o /dev/null -w 'INVALID INPUT HTTP CODE: %{http_code}\n' -X POST http://127.0.0.1:8095/predict -H 'content-type: application/json' -d '{}'
echo '=== MILESTONE 2 SUCCESS (screenshot this Terminal; also open http://127.0.0.1:8095/docs while running if needed) ==='
