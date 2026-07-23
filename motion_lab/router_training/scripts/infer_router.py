#!/usr/bin/env python3
"""CLI smoke inference for the exported text-to-action router."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

from feature_providers import cosine, hashed_char_ngram_vector


REPO_ROOT = Path(__file__).resolve().parents[3]
DEFAULT_MODEL = REPO_ROOT / "data" / "router_model.json"


def nearest(vector, centroids):
    best_label = ""
    best_score = -1.0
    for label, center in centroids.items():
        score = cosine(vector, center)
        if score > best_score:
            best_label = label
            best_score = score
    return best_label, best_score


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("text", nargs="+")
    parser.add_argument("--model", type=Path, default=DEFAULT_MODEL)
    args = parser.parse_args()

    model = json.loads(args.model.read_text(encoding="utf-8"))
    if model["feature_provider"] != "hash":
        raise SystemExit("This smoke CLI currently supports hash exported models. Use ECNU provider in Python service later.")
    text = " ".join(args.text)
    vector = hashed_char_ngram_vector(text, model["dimensions"])
    action, action_score = nearest(vector, model["centroids"]["actions"])
    expression, expression_score = nearest(vector, model["centroids"]["expressions"])
    motion_label, motion_score = nearest(vector, model["centroids"]["motion_request"])
    print(
        json.dumps(
            {
                "text": text,
                "action_id": action,
                "action_score": round(action_score, 4),
                "expression": expression,
                "expression_score": round(expression_score, 4),
                "motion_request": motion_label == "true",
                "motion_score": round(motion_score, 4),
            },
            ensure_ascii=False,
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
