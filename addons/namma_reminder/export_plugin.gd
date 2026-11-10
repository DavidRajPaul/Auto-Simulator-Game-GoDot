@tool
extends EditorPlugin
## Adds the NammaReminder Android plugin (daily reminder notifications) to Android exports.
## The AAR is built from android_plugins/namma_reminder by CI (or locally, see its README) and
## copied to addons/namma_reminder/bin/namma_reminder.aar. Without it the export still works,
## just without reminders (DailyReminder.gd finds no singleton and does nothing).

var _export_plugin: AndroidExportPlugin

func _enter_tree() -> void:
	_export_plugin = AndroidExportPlugin.new()
	add_export_plugin(_export_plugin)

func _exit_tree() -> void:
	remove_export_plugin(_export_plugin)
	_export_plugin = null

class AndroidExportPlugin extends EditorExportPlugin:
	## Relative to res://addons/ (Godot's convention for _get_android_libraries).
	const AAR: String = "namma_reminder/bin/namma_reminder.aar"
	## A local AAR brings no dependency metadata, so list what it needs. Keep in sync with
	## android_plugins/namma_reminder/build.gradle.
	const DEPENDENCIES: PackedStringArray = ["androidx.work:work-runtime:2.9.1", "androidx.core:core:1.12.0"]

	func _get_name() -> String:
		return "NammaReminder"

	func _supports_platform(platform: EditorExportPlatform) -> bool:
		return platform is EditorExportPlatformAndroid

	func _has_aar() -> bool:
		return FileAccess.file_exists("res://addons/" + AAR)

	func _get_android_libraries(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
		if not _has_aar():
			push_warning("NammaReminder: %s missing, exporting without daily reminders." % AAR)
			return PackedStringArray()
		return PackedStringArray([AAR])

	func _get_android_dependencies(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
		return DEPENDENCIES if _has_aar() else PackedStringArray()
