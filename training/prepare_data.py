"""Export a deterministic, validated dataset from sklearn; no network download."""
import argparse
import json
from pathlib import Path
import pandas as pd
from sklearn.datasets import load_breast_cancer


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', default='data/raw/breast_cancer.csv')
    parser.add_argument('--trim-last', type=int, default=0,
                        help='Remove last N rows to simulate a corrected dataset export')
    parser.add_argument('--sample-json', default='sample.json')
    args = parser.parse_args()
    data = load_breast_cancer()
    feature_names = [name.replace(' ', '_') for name in data.feature_names]
    if len(feature_names) != 30:
        raise ValueError(f'Expected 30 features, found {len(feature_names)}')
    frame = pd.DataFrame(data.data, columns=feature_names)
    frame['target'] = data.target.astype(int)
    if frame.isnull().values.any():
        raise ValueError('Null values detected in exported dataset')
    if args.trim_last:
        if not 0 < args.trim_last < len(frame):
            raise ValueError('Invalid trim-last count')
        frame = frame.iloc[:-args.trim_last].copy()
    path = Path(args.output)
    path.parent.mkdir(parents=True, exist_ok=True)
    frame.to_csv(path, index=False, float_format='%.12g')
    if args.sample_json:
        sample = {name: float(frame.iloc[0][name]) for name in feature_names}
        Path(args.sample_json).write_text(json.dumps(sample, indent=2) + '\n', encoding='utf-8')
    print(f'DATASET exported={path} rows={len(frame)} features={len(feature_names)} nulls=0')
    print(f'CLASS COUNTS: {frame["target"].value_counts().to_dict()} (0=malignant, 1=benign)')

if __name__ == '__main__':
    main()
