#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p evidence .local
if ! command -v python3.12 >/dev/null 2>&1; then
  echo 'Python 3.12 not found. Installing with Homebrew...'
  if ! command -v brew >/dev/null 2>&1; then echo 'Please install Homebrew first (https://brew.sh)'; exit 1; fi
  brew install python@3.12
fi
[ -d .venv ] || python3.12 -m venv .venv
source .venv/bin/activate
python -m pip install --disable-pip-version-check -q -r requirements-train.txt -r requirements-serve.txt -r requirements-dev.txt
if [ ! -d .git ]; then git init -b main; fi
if ! git var GIT_AUTHOR_IDENT >/dev/null 2>&1; then
  echo 'Git author not configured. Run: git config --global user.name "YOUR NAME"; git config --global user.email "YOUR GITHUB EMAIL"'; exit 2
fi
if [ ! -d .dvc ]; then dvc init; fi
if ! dvc remote list | grep -q '^local-storage'; then dvc remote add -d local-storage ./dvc-remote; fi
mkdir -p dvc-remote
python -m training.prepare_data --trim-last 0 --sample-json sample.json
dvc add data/raw/breast_cancer.csv
dvc push
sha1=$(awk '$2=="md5:" {print $3}' data/raw/breast_cancer.csv.dvc)
size1=$(python -c 'import os; print(os.path.getsize("data/raw/breast_cancer.csv"))')
git add -A
# Commit the complete DVC remote object(s) to Git (assignment-specific exception).
git add -f dvc-remote
if ! git diff --cached --quiet; then git commit -m 'Milestone 1: versioned 569-row dataset with DVC'; fi
v1=$(git rev-parse --short HEAD)
echo "VERSION 1: git=$v1 DVC=$sha1 rows=569 bytes=$size1"
echo 'Proof of remote restore: deleting local CSV/cache, then dvc pull'
rm -f data/raw/breast_cancer.csv
rm -rf .dvc/cache
dvc pull data/raw/breast_cancer.csv.dvc
python -c 'import pandas as pd;print("RESTORED ROWS:",len(pd.read_csv("data/raw/breast_cancer.csv")))'
python -m training.prepare_data --trim-last 30 --sample-json sample.json
dvc add data/raw/breast_cancer.csv
dvc push
sha2=$(awk '$2=="md5:" {print $3}' data/raw/breast_cancer.csv.dvc)
size2=$(python -c 'import os; print(os.path.getsize("data/raw/breast_cancer.csv"))')
git add -A
git add -f dvc-remote
if ! git diff --cached --quiet; then git commit -m 'Milestone 1: corrected 539-row dataset'; fi
v2=$(git rev-parse --short HEAD)
printf 'Git commit,DVC hash,Rows,File size bytes\n%s,%s,569,%s\n%s,%s,539,%s\n' "$v1" "$sha1" "$size1" "$v2" "$sha2" "$size2" | tee evidence/table1_dataset_versions.csv
# Demonstrate moving between versions without changing other source files.
git checkout "$v1" -- data/raw/breast_cancer.csv.dvc
dvc checkout data/raw/breast_cancer.csv.dvc
python -c 'import pandas as pd;print("VERSION SWITCH to V1:",len(pd.read_csv("data/raw/breast_cancer.csv")))'
git restore --source=HEAD --staged --worktree -- data/raw/breast_cancer.csv.dvc
dvc checkout data/raw/breast_cancer.csv.dvc
python -c 'import pandas as pd;print("VERSION SWITCH back to V2:",len(pd.read_csv("data/raw/breast_cancer.csv")))'
echo 'VERIFY Git does not track CSV:'
git ls-files data/raw/breast_cancer.csv
echo 'VERIFY DVC remote / local:'
dvc status
git status --short
echo '=== MILESTONE 1 SUCCESS (screenshot this Terminal output) ==='
