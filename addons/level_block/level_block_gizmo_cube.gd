@tool
extends "res://addons/level_block/level_block_gizmo_base.gd"
## Names and claims the gizmo for [LevelBlockCube]. All drawing and drag handling
## lives in the base; this only narrows which node type it attaches to and what
## View > Gizmos calls it.


func _get_gizmo_name() -> String:
	return "Level Block Cube"


func _has_gizmo(node: Node3D) -> bool:
	return node is LevelBlockCube
