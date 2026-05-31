## AudioSettingsPanel — Master / Music / SFX 音量 + 一鍵靜音 UI 面板
class_name AudioSettingsPanel
extends Control

@onready var _master_slider: HSlider = $Panel/VBox/MasterRow/Slider
@onready var _master_value: Label    = $Panel/VBox/MasterRow/Value
@onready var _music_slider: HSlider  = $Panel/VBox/MusicRow/Slider
@onready var _music_value: Label     = $Panel/VBox/MusicRow/Value
@onready var _sfx_slider: HSlider    = $Panel/VBox/SFXRow/Slider
@onready var _sfx_value: Label        = $Panel/VBox/SFXRow/Value
@onready var _mute_check: CheckButton = $Panel/VBox/MuteCheck
@onready var _close_btn: Button       = $Panel/CloseButton

## channel -> {slider: HSlider, value: Label}
var _rows: Dictionary = {}

func _ready() -> void:
	UIManager.register("AudioSettingsPanel", self)
	_rows = {
		AudioSettings.MASTER: {"slider": _master_slider, "value": _master_value},
		AudioSettings.MUSIC: {"slider": _music_slider, "value": _music_value},
		AudioSettings.SFX: {"slider": _sfx_slider, "value": _sfx_value},
	}
	_close_btn.pressed.connect(_on_close)
	_close_btn.pressed.connect(UISfx.play_click)
	_master_slider.value_changed.connect(_on_slider_changed.bind(AudioSettings.MASTER))
	_music_slider.value_changed.connect(_on_slider_changed.bind(AudioSettings.MUSIC))
	_sfx_slider.value_changed.connect(_on_slider_changed.bind(AudioSettings.SFX))
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
	for channel in _rows:
		var pct: float = AudioSettings.get_volume(channel) * 100.0
		var slider: HSlider = _rows[channel]["slider"]
		var value: Label = _rows[channel]["value"]
		slider.set_value_no_signal(pct)
		value.text = "%d%%" % roundi(pct)
	_mute_check.set_pressed_no_signal(AudioSettings.is_muted())

func _on_slider_changed(value: float, channel: String) -> void:
	AudioSettings.set_volume(channel, value / 100.0)
	var label: Label = _rows[channel]["value"]
	label.text = "%d%%" % roundi(value)

func _on_mute_toggled(pressed: bool) -> void:
	AudioSettings.set_muted(pressed)

func _on_close() -> void:
	UIManager.pop()
