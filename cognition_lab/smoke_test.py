"""Run with: python3 cognition_lab/smoke_test.py"""

from agent_graph import build_shared_graph


def state(agent_id: str, motives: dict[str, float], world: str) -> dict:
    return {
        "schema_version": 1,
        "thread_id": f"agent:{agent_id}",
        "agent_id": agent_id,
        "trigger": {"source": "autonomous"},
        "profile": {"identity": agent_id, "traits": {}, "motives": motives},
        "psyche": {
            "mood": {"valence": 0.1, "arousal": 0.4},
            "attention": "",
            "intention": "",
            "beliefs": {},
            "recent_activities": [],
        },
        "world": world,
        "memory_context": "",
        "daily_plan": {
            "day": 1,
            "period": "morning",
            "priorities": ["plant_care", "read_book", "wander_room"],
            "completed": [],
        },
        "audit": [],
    }


def main() -> None:
    graph = build_shared_graph()
    main_config = {"configurable": {"thread_id": "agent:main_agent"}}
    jue_config = {"configurable": {"thread_id": "agent:jue_agent"}}
    main_result = graph.invoke(
        state("main_agent", {"care": 0.9, "curiosity": 0.6, "autonomy": 0.7}, "小绿严重缺水"),
        config=main_config,
    )
    jue_result = graph.invoke(
        state("jue_agent", {"care": 0.5, "curiosity": 0.95, "autonomy": 0.7}, "小绿状态良好"),
        config=jue_config,
    )
    assert main_result["selected_goal"]["goal"] == "water_plant"
    assert jue_result["selected_goal"]["goal"] == "read_book"
    assert graph.get_state(main_config).values["agent_id"] == "main_agent"
    assert graph.get_state(jue_config).values["agent_id"] == "jue_agent"
    assert main_result["audit"] == [
        "perceive",
        "retrieve_memory",
        "update_psyche",
        "reflect_if_needed",
        "propose_goals",
        "arbitrate",
        "compose_response",
    ]
    reflection_config = {"configurable": {"thread_id": "agent:reflection_check"}}
    reflection_state = state(
        "reflection_check",
        {"care": 0.5, "curiosity": 0.5, "autonomy": 0.5},
        "小绿状态良好",
    )
    reflection_state["trigger"] = {"source": "reflection"}
    reflection_state["psyche"]["recent_activities"] = ["read_book", "read_book", "wander_room"]
    reflection_result = graph.invoke(reflection_state, config=reflection_config)
    assert reflection_result["reflection"]["dominant_activity"] == "read_book"
    assert reflection_result["reflection"]["requires_memory_write"] is True
    print(
        "LANGGRAPH_AGENT_PASS",
        f"main={main_result['selected_goal']['goal']}",
        f"jue={jue_result['selected_goal']['goal']}",
        f"reflection={reflection_result['reflection']['dominant_activity']}",
        "threads=isolated",
    )


if __name__ == "__main__":
    main()
