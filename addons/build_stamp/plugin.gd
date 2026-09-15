@tool
extends EditorPlugin

const BuildStampExportPlugin := preload("res://addons/build_stamp/build_stamp_export_plugin.gd")

var _export_plugin: EditorExportPlugin


func _enter_tree() -> void:
	_export_plugin = BuildStampExportPlugin.new()
	add_export_plugin(_export_plugin)


func _exit_tree() -> void:
	remove_export_plugin(_export_plugin)
	_export_plugin = null
