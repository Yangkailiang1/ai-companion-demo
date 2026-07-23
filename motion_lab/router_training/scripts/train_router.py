#!/usr/bin/env python3
"""Train/export the lightweight text-to-action prototype router."""

from __future__ import annotations

import argparse
import json
import random
import subprocess
import sys
from collections import defaultdict
from pathlib import Path
from typing import Dict, List

from feature_providers import EmbeddingConfig, centroid, cosine, make_provider, normalize_text


REPO_ROOT = Path(__file__).resolve().parents[3]
DEFAULT_DATASET = REPO_ROOT / "motion_lab" / "router_training" / "generated_train.jsonl"
DEFAULT_MODEL = REPO_ROOT / "data" / "router_model.json"
CACHE_PATH = REPO_ROOT / "motion_lab" / "router_training" / ".embedding_cache" / "ecnu_embeddings.json"


def read_jsonl(path: Path) -> List[Dict]:
    rows = []
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line:
            rows.append(json.loads(line))
    return rows


def ensure_dataset(path: Path) -> None:
    if path.exists():
        return
    builder = Path(__file__).with_name("build_training_data.py")
    subprocess.run([sys.executable, str(builder), "--output", str(path)], check=True)


def split_rows(rows: List[Dict], seed: int) -> tuple[List[Dict], List[Dict]]:
    random.Random(seed).shuffle(rows)
    by_label: dict[str, List[Dict]] = defaultdict(list)
    for row in rows:
        by_label[row["action_id"]].append(row)
    train: List[Dict] = []
    dev: List[Dict] = []
    for label_rows in by_label.values():
        cutoff = max(1, int(len(label_rows) * 0.82))
        train.extend(label_rows[:cutoff])
        dev.extend(label_rows[cutoff:])
    return train, dev


def nearest_label(vector: List[float], centroids: Dict[str, List[float]]) -> tuple[str, float]:
    best_label = ""
    best_score = -1.0
    for label, center in centroids.items():
        score = cosine(vector, center)
        if score > best_score:
            best_label = label
            best_score = score
    return best_label, best_score


def evaluate(rows: List[Dict], vectors: List[List[float]], action_centroids: Dict[str, List[float]], expression_centroids: Dict[str, List[float]]) -> Dict:
    action_correct = 0
    expression_correct = 0
    motion_correct = 0
    confusion: dict[str, dict[str, int]] = defaultdict(lambda: defaultdict(int))
    motion_labels = {
        "true": centroid((vector for row, vector in zip(rows, vectors) if row["motion_request"]), len(vectors[0])),
        "false": centroid((vector for row, vector in zip(rows, vectors) if not row["motion_request"]), len(vectors[0])),
    }
    for row, vector in zip(rows, vectors):
        action_label, _score = nearest_label(vector, action_centroids)
        expression_label, _expr_score = nearest_label(vector, expression_centroids)
        motion_label, _motion_score = nearest_label(vector, motion_labels)
        if action_label == row["action_id"]:
            action_correct += 1
        if expression_label == row["expression"]:
            expression_correct += 1
        predicted_motion = motion_label == "true"
        if predicted_motion == bool(row["motion_request"]):
            motion_correct += 1
        confusion[row["action_id"]][action_label] += 1
    total = max(1, len(rows))
    return {
        "rows": len(rows),
        "action_accuracy": round(action_correct / total, 4),
        "expression_accuracy": round(expression_correct / total, 4),
        "motion_request_accuracy": round(motion_correct / total, 4),
        "action_confusion": {key: dict(value) for key, value in confusion.items()},
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dataset", type=Path, default=DEFAULT_DATASET)
    parser.add_argument("--output", type=Path, default=DEFAULT_MODEL)
    parser.add_argument("--provider", choices=["hash", "ecnu"], default="hash")
    parser.add_argument("--dimensions", type=int, default=1024)
    parser.add_argument("--accept-threshold", type=float, default=0.24)
    parser.add_argument("--seed", type=int, default=20260723)
    args = parser.parse_args()

    ensure_dataset(args.dataset)
    rows = read_jsonl(args.dataset)
    train_rows, dev_rows = split_rows(rows, args.seed)

    config = EmbeddingConfig(
        provider=args.provider,
        dimensions=args.dimensions,
        cache_path=CACHE_PATH,
    )
    provider = make_provider(config)

    all_texts = [row["text"] for row in rows]
    all_vectors = provider.embed_many(all_texts)
    vector_by_text = {normalize_text(text): vector for text, vector in zip(all_texts, all_vectors)}

    def row_vectors(selected_rows: List[Dict]) -> List[List[float]]:
        return [vector_by_text[normalize_text(row["text"])] for row in selected_rows]

    train_vectors = row_vectors(train_rows)
    dev_vectors = row_vectors(dev_rows)

    action_centroids = {
        label: centroid((vector for row, vector in zip(train_rows, train_vectors) if row["action_id"] == label), args.dimensions)
        for label in sorted({row["action_id"] for row in train_rows})
    }
    expression_centroids = {
        label: centroid((vector for row, vector in zip(train_rows, train_vectors) if row["expression"] == label), args.dimensions)
        for label in sorted({row["expression"] for row in train_rows})
    }
    motion_centroids = {
        "true": centroid((vector for row, vector in zip(train_rows, train_vectors) if row["motion_request"]), args.dimensions),
        "false": centroid((vector for row, vector in zip(train_rows, train_vectors) if not row["motion_request"]), args.dimensions),
    }

    evaluation = evaluate(dev_rows, dev_vectors, action_centroids, expression_centroids)
    artifact = {
        "version": 1,
        "architecture": "frozen_text_embedding_plus_centroid_router",
        "feature_provider": args.provider,
        "embedding_model": "ecnu-embedding-small" if args.provider == "ecnu" else "hash_char_ngram_v1",
        "dimensions": args.dimensions,
        "accept_threshold": args.accept_threshold,
        "labels": {
            "actions": sorted(action_centroids.keys()),
            "expressions": sorted(expression_centroids.keys()),
            "motion_request": ["false", "true"],
        },
        "centroids": {
            "actions": action_centroids,
            "expressions": expression_centroids,
            "motion_request": motion_centroids,
        },
        "training": {
            "dataset": str(args.dataset.relative_to(REPO_ROOT)),
            "rows": len(rows),
            "train_rows": len(train_rows),
            "dev_rows": len(dev_rows),
            "seed": args.seed,
            "evaluation": evaluation,
        },
    }

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(artifact, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    print(json.dumps(artifact["training"], ensure_ascii=False, indent=2))
    print(f"Exported router model to {args.output}")


if __name__ == "__main__":
    main()
