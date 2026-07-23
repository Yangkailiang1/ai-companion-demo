#!/usr/bin/env python3
"""Build a first-pass training set from catalogs plus curated seed intents."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Dict, Iterable, List


REPO_ROOT = Path(__file__).resolve().parents[3]
MOTION_CATALOG = REPO_ROOT / "data" / "motion_catalog.json"
EXPRESSION_CATALOG = REPO_ROOT / "data" / "expression_catalog.json"
SEED_INTENTS = REPO_ROOT / "motion_lab" / "router_training" / "seed_intents.jsonl"
DEFAULT_OUTPUT = REPO_ROOT / "motion_lab" / "router_training" / "generated_train.jsonl"


COMMAND_PREFIXES = ["请", "帮我", "现在", "来一个", "可以", ""]
CONVERSATION_SUFFIXES = ["", "好吗", "一下", "给我看看"]
NEGATION_PREFIXES = ["不要", "别", "先不用"]


def load_json(path: Path) -> Dict:
    return json.loads(path.read_text(encoding="utf-8"))


def read_jsonl(path: Path) -> Iterable[Dict]:
    if not path.exists():
        return []
    rows = []
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line:
            rows.append(json.loads(line))
    return rows


def add_row(rows: List[Dict], text: str, action_id: str, expression: str, motion_request: bool, source: str) -> None:
    normalized = text.strip()
    if not normalized:
        return
    key = (normalized, action_id, expression, motion_request)
    if key in add_row.seen:
        return
    add_row.seen.add(key)
    rows.append(
        {
            "text": normalized,
            "action_id": action_id,
            "expression": expression,
            "motion_request": bool(motion_request),
            "source": source,
        }
    )


add_row.seen = set()


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()

    motion_catalog = load_json(MOTION_CATALOG)
    expression_catalog = load_json(EXPRESSION_CATALOG)
    rows: List[Dict] = []

    for seed in read_jsonl(SEED_INTENTS):
        add_row(
            rows,
            seed["text"],
            seed["action_id"],
            seed.get("expression", "neutral"),
            seed.get("motion_request", seed["action_id"] not in ["talk", "idle"]),
            "seed",
        )

    for action in motion_catalog.get("actions", []):
        action_id = action["id"]
        expression = action.get("default_expression", "neutral")
        is_motion = action_id not in ["talk", "idle"]
        for alias in action.get("aliases", []):
            for prefix in COMMAND_PREFIXES:
                for suffix in CONVERSATION_SUFFIXES:
                    add_row(rows, f"{prefix}{alias}{suffix}", action_id, expression, is_motion, "action_alias")
            if is_motion:
                for prefix in NEGATION_PREFIXES:
                    add_row(rows, f"{prefix}{alias}", "talk", "neutral", False, "negation")

    for intent in motion_catalog.get("router_intents", []):
        action_id = intent.get("gesture", "talk")
        expression = intent.get("expression", "neutral")
        for alias in intent.get("aliases", []):
            for prefix in COMMAND_PREFIXES:
                add_row(rows, f"{prefix}{alias}", action_id, expression, True, "router_intent")

    for expression_name, expression in expression_catalog.get("expressions", {}).items():
        for alias in expression.get("aliases", []):
            add_row(rows, f"我现在有点{alias}", "talk", expression_name, False, "expression_alias")
            add_row(rows, f"感觉{alias}", "talk", expression_name, False, "expression_alias")

    hard_negatives = [
        "你会跳舞吗",
        "你能侧手翻吗",
        "这个动作难不难",
        "我们聊聊天吧",
        "今天天气怎么样",
        "奶茶好喝吗",
        "你喜欢这个房间吗",
    ]
    for text in hard_negatives:
        add_row(rows, text, "talk", "talk", False, "hard_negative")

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", encoding="utf-8") as handle:
        for row in rows:
            handle.write(json.dumps(row, ensure_ascii=False) + "\n")
    print(f"Wrote {len(rows)} rows to {args.output}")


if __name__ == "__main__":
    main()
