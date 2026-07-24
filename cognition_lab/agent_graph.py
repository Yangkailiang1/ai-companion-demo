"""Shared LangGraph cognition prototype for all Living Agent characters.

The graph is deliberately model-agnostic. LLM-backed reflection and response
nodes can replace the deterministic baseline without changing the state contract.
Godot remains authoritative for physical validation and execution.
"""

from __future__ import annotations

from typing import Any, TypedDict

from langgraph.checkpoint.memory import InMemorySaver
from langgraph.graph import END, START, StateGraph


class AgentGraphState(TypedDict, total=False):
    schema_version: int
    thread_id: str
    agent_id: str
    trigger: dict[str, Any]
    profile: dict[str, Any]
    psyche: dict[str, Any]
    world: str
    memory_context: str
    candidate_goals: list[dict[str, Any]]
    selected_goal: dict[str, Any]
    response: dict[str, Any]
    audit: list[str]


def _perceive(state: AgentGraphState) -> AgentGraphState:
    audit = [*state.get("audit", []), "perceive"]
    return {"audit": audit}


def _retrieve_memory(state: AgentGraphState) -> AgentGraphState:
    # Godot currently supplies bounded, already-retrieved memory context. A future
    # node can query a LangGraph Store without changing downstream state channels.
    audit = [*state.get("audit", []), "retrieve_memory"]
    return {"audit": audit}


def _update_psyche(state: AgentGraphState) -> AgentGraphState:
    psyche = dict(state.get("psyche", {}))
    trigger = state.get("trigger", {})
    if trigger.get("source") == "player":
        psyche["attention"] = "player"
        psyche["intention"] = "respond_to_player"
    audit = [*state.get("audit", []), "update_psyche"]
    return {"psyche": psyche, "audit": audit}


def _propose_goals(state: AgentGraphState) -> AgentGraphState:
    trigger = state.get("trigger", {})
    world = state.get("world", "")
    profile = state.get("profile", {})
    motives = profile.get("motives", {})
    candidates: list[dict[str, Any]] = []
    if trigger.get("source") == "player":
        candidates.append({"goal": "chat_with_player", "score": 1.0, "reason": "player_priority"})
    if any(label in world for label in ("需要浇水", "严重缺水", "枯萎")):
        care = float(motives.get("care", 0.5))
        candidates.append({"goal": "water_plant", "score": 0.55 + 0.4 * care, "reason": "plant_dry"})
    curiosity = float(motives.get("curiosity", 0.5))
    candidates.append({"goal": "read_book", "score": 0.25 + 0.35 * curiosity, "reason": "curiosity"})
    autonomy = float(motives.get("autonomy", 0.5))
    candidates.append({"goal": "wander_room", "score": 0.2 + 0.3 * autonomy, "reason": "autonomy"})
    audit = [*state.get("audit", []), "propose_goals"]
    return {"candidate_goals": candidates, "audit": audit}


def _arbitrate(state: AgentGraphState) -> AgentGraphState:
    candidates = state.get("candidate_goals", [])
    selected = max(candidates, key=lambda item: float(item.get("score", 0.0)), default={})
    audit = [*state.get("audit", []), "arbitrate"]
    return {"selected_goal": selected, "audit": audit}


def _compose_response(state: AgentGraphState) -> AgentGraphState:
    selected = state.get("selected_goal", {})
    goal = selected.get("goal", "idle")
    response = {
        "goal": goal,
        "goal_reason": selected.get("reason", "no_candidate"),
        "speech": "" if goal != "chat_with_player" else "我在听，你想和我聊什么？",
        "requires_godot_validation": True,
    }
    audit = [*state.get("audit", []), "compose_response"]
    return {"response": response, "audit": audit}


def build_shared_graph(checkpointer: Any | None = None):
    """Compile one reusable graph; isolate characters with config.thread_id."""

    builder = StateGraph(AgentGraphState)
    builder.add_node("perceive", _perceive)
    builder.add_node("retrieve_memory", _retrieve_memory)
    builder.add_node("update_psyche", _update_psyche)
    builder.add_node("propose_goals", _propose_goals)
    builder.add_node("arbitrate", _arbitrate)
    builder.add_node("compose_response", _compose_response)
    builder.add_edge(START, "perceive")
    builder.add_edge("perceive", "retrieve_memory")
    builder.add_edge("retrieve_memory", "update_psyche")
    builder.add_edge("update_psyche", "propose_goals")
    builder.add_edge("propose_goals", "arbitrate")
    builder.add_edge("arbitrate", "compose_response")
    builder.add_edge("compose_response", END)
    return builder.compile(checkpointer=checkpointer or InMemorySaver())
