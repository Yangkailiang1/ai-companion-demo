# signal_bus.gd — 跨模块信号桥 (Autoload)
# 用于 CognitiveCycle → AgentBase 之间传递 GOAP Action Chain

extends Node

signal emit_actions(agent_id: String, actions: Array)

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
