## AudioSettingsPanel — Master 音量 + 一鍵靜音 UI 面板
class_name AudioSettingsPanel
extends Control

@onready var _volume_slider: HSlider = $Panel/VBox/VolumeRow/VolumeSlider
@onready var _volume_value: Label    = $Panel/VBox/VolumeRow/VolumeValue
@onready var _mute_check: CheckButton = $Panel/VBox/MuteCheck
@onready var _close_btn: Button       = $Panel/CloseButton

func _ready() -> void:
	UIManager.register("AudioSettingsPanel", self)
	_close_btn.pressed.connect(_on_close)
	_volume_slider.value_changed.connect(_on_volume_changed)
	_mute_check.toggled.connect(_on_mute_toggled)
	visibility_changed.connect(_on_visibility_changed)

func _on_visibility_changed() -> void:
	if visible:
		_sync_from_settings()

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("pause"):
		_on_close()
		get_viewport().set_input_as_handled()

func _sync_from_settings() -> void:
	_volume_slider.set_value_no_signal(AudioSettings.get_volume() * 100.0)
	_volume_value.text = "%d%%" % roundi(AudioSettings.get_volume() * 100.0)
	_mute_check.set_pressed_no_signal(AudioSettings.is_muted())

func _on_volume_changed(value: float) -> void:
	var linear: float = value / 100.0
	AudioSettings.set_volume(linear)
	_volume_value.text = "%d%%" % roundi(value)

func _on_mute_toggled(pressed: bool) -> void:
	AudioSettings.set_muted(pressed)

func _on_close() -> void:
	UIManager.pop()
