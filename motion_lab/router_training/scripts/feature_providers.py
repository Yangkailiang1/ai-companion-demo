"""Feature providers for the lightweight text-to-action router.

The production path can use the ECNU OpenAI-compatible embedding endpoint.
For local smoke tests and offline development we keep a deterministic hashed
character n-gram provider that exports the same fixed-size vector contract.
"""

from __future__ import annotations

import json
import math
import os
import time
import urllib.error
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, List, Sequence


def normalize_text(text: str) -> str:
    return (
        text.strip()
        .lower()
        .replace("，", " ")
        .replace("。", " ")
        .replace("！", " ")
        .replace("？", " ")
        .replace(",", " ")
        .replace(".", " ")
        .replace("!", " ")
        .replace("?", " ")
    )


def l2_normalize(vector: Sequence[float]) -> List[float]:
    norm = math.sqrt(sum(value * value for value in vector))
    if norm <= 1e-12:
        return [0.0 for _ in vector]
    return [float(value / norm) for value in vector]


def hashed_char_ngram_vector(text: str, dimensions: int = 1024) -> List[float]:
    """A tiny deterministic local fallback.

    It is intentionally simple so it can be mirrored inside Godot/GDScript:
    generate character 1/2/3-grams, hash them with a small FNV-1a variant,
    add signed bucket counts, then L2-normalize.
    """

    normalized = normalize_text(text)
    vector = [0.0] * dimensions
    compact = "".join(ch for ch in normalized if not ch.isspace())
    tokens = [token for token in normalized.split(" ") if token]

    grams: List[str] = []
    for source in [compact, *tokens]:
        for ngram_size in (1, 2, 3):
            if len(source) < ngram_size:
                continue
            for index in range(0, len(source) - ngram_size + 1):
                grams.append(source[index : index + ngram_size])

    if not grams and normalized:
        grams = [normalized]

    for gram in grams:
        hash_value = 2166136261
        for char in gram:
            hash_value = (hash_value ^ ord(char)) * 16777619
            hash_value %= 2147483647
        bucket = hash_value % dimensions
        sign = 1.0 if hash_value % 2 == 0 else -1.0
        vector[bucket] += sign

    return l2_normalize(vector)


@dataclass(frozen=True)
class EmbeddingConfig:
    provider: str = "hash"
    dimensions: int = 1024
    model: str = "ecnu-embedding-small"
    base_url: str = "https://chat.ecnu.edu.cn/open/api/v1"
    api_key_env: str = "ECNU_EMBEDDING_API_KEY"
    cache_path: Path | None = None


class FeatureProvider:
    def embed_many(self, texts: Sequence[str]) -> List[List[float]]:
        raise NotImplementedError


class HashFeatureProvider(FeatureProvider):
    def __init__(self, dimensions: int = 1024) -> None:
        self.dimensions = dimensions

    def embed_many(self, texts: Sequence[str]) -> List[List[float]]:
        return [hashed_char_ngram_vector(text, self.dimensions) for text in texts]


class ECNUEmbeddingProvider(FeatureProvider):
    def __init__(self, config: EmbeddingConfig) -> None:
        self.config = config
        self.api_key = os.environ.get(config.api_key_env, "")
        if not self.api_key:
            raise RuntimeError(
                f"Missing {config.api_key_env}. Set it to train with ECNU embeddings, "
                "or pass --provider hash for offline local training."
            )
        self.cache_path = config.cache_path
        self.cache: dict[str, List[float]] = {}
        if self.cache_path and self.cache_path.exists():
            self.cache = json.loads(self.cache_path.read_text(encoding="utf-8"))

    def embed_many(self, texts: Sequence[str]) -> List[List[float]]:
        normalized_texts = [normalize_text(text) for text in texts]
        missing = [text for text in normalized_texts if text not in self.cache]
        if missing:
            for batch_start in range(0, len(missing), 64):
                batch = missing[batch_start : batch_start + 64]
                embeddings = self._request_batch(batch)
                for text, embedding in zip(batch, embeddings):
                    self.cache[text] = l2_normalize(embedding)
                time.sleep(0.15)
            if self.cache_path:
                self.cache_path.parent.mkdir(parents=True, exist_ok=True)
                self.cache_path.write_text(
                    json.dumps(self.cache, ensure_ascii=False),
                    encoding="utf-8",
                )
        return [self.cache[text] for text in normalized_texts]

    def _request_batch(self, texts: Sequence[str]) -> List[List[float]]:
        url = f"{self.config.base_url.rstrip('/')}/embeddings"
        payload = json.dumps({"model": self.config.model, "input": list(texts)}).encode("utf-8")
        request = urllib.request.Request(
            url,
            data=payload,
            headers={
                "Content-Type": "application/json",
                "Authorization": f"Bearer {self.api_key}",
            },
            method="POST",
        )
        try:
            with urllib.request.urlopen(request, timeout=45) as response:
                parsed = json.loads(response.read().decode("utf-8"))
        except urllib.error.HTTPError as exc:
            body = exc.read().decode("utf-8", errors="replace")
            raise RuntimeError(f"ECNU embedding request failed: HTTP {exc.code} {body}") from exc
        data = parsed.get("data", [])
        ordered = sorted(data, key=lambda item: int(item.get("index", 0)))
        embeddings = [item.get("embedding", []) for item in ordered]
        if len(embeddings) != len(texts):
            raise RuntimeError("ECNU embedding response size mismatch")
        if any(len(embedding) != self.config.dimensions for embedding in embeddings):
            raise RuntimeError("ECNU embedding dimensions mismatch")
        return embeddings


def make_provider(config: EmbeddingConfig) -> FeatureProvider:
    if config.provider == "hash":
        return HashFeatureProvider(config.dimensions)
    if config.provider == "ecnu":
        return ECNUEmbeddingProvider(config)
    raise ValueError(f"Unknown feature provider: {config.provider}")


def centroid(vectors: Iterable[Sequence[float]], dimensions: int) -> List[float]:
    total = [0.0] * dimensions
    count = 0
    for vector in vectors:
        count += 1
        for index, value in enumerate(vector):
            total[index] += value
    if count == 0:
        return total
    return l2_normalize([value / count for value in total])


def cosine(left: Sequence[float], right: Sequence[float]) -> float:
    return float(sum(a * b for a, b in zip(left, right)))
