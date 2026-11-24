@tool
extends EditorPlugin
## Registers one face-drag gizmo plugin per block shape. The nodes themselves are
## global classes ([code]class_name[/code] + [code]@icon[/code]), so they show in
## Create New Node without a custom-type registration.
##
## Each shape gets its own gizmo plugin so it carries its own name in
## View > Gizmos — the engine's gizmo name is per-plugin, not per-node. Adding a
## shape means adding its gizmo script to [constant GIZMO_SCRIPTS].

const GIZMO_SCRIPTS: Array[GDScript] = [
	preload("res://addons/level_block/level_block_gizmo_cube.gd"),
	preload("res://addons/level_block/level_block_gizmo_triangle.gd"),
]

var _gizmos: Array[EditorNode3DGizmoPlugin] = []


func _enter_tree() -> void:
	# Unregister first: a re-entry without an intervening _exit_tree would other-
	# wise append a second batch and leave the first registered — silent double
	# gizmos, no error.
	_unregister_all()
	for gizmo_script: GDScript in GIZMO_SCRIPTS:
		var gizmo: EditorNode3DGizmoPlugin = gizmo_script.new(get_undo_redo())
		_gizmos.append(gizmo)
		add_node_3d_gizmo_plugin(gizmo)


func _exit_tree() -> void:
	_unregister_all()


func _unregister_all() -> void:
	for gizmo: EditorNode3DGizmoPlugin in _gizmos:
		remove_node_3d_gizmo_plugin(gizmo)
	_gizmos.clear()
