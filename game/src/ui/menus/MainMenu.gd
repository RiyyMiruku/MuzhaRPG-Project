## MainMenu — 遊戲主選單
class_name MainMenu
extends Control

@onready var _start_btn: Button    = $Panel/VBox/StartButton
@onready var _load_btn: Button     = $Panel/VBox/LoadButton
@onready var _quit_btn: Button     = $Panel/VBox/QuitButton

func _ready() -> void:
	UIManager.register("MainMenu", self)
	_start_btn.pressed.connect(_on_start)
	_load_btn.pressed.connect(_on_load)
	_quit_btn.pressed.connect(_on_quit)
	_start_btn.pressed.connect(UISfx.play_click)
	_load_btn.pressed.connect(UISfx.play_click)
	_quit_btn.pressed.connect(UISfx.play_click)
	_load_btn.disabled = not (SaveManager.has_slot(1) or SaveManager.has_slot(2) or SaveManager.has_slot(3) or SaveManager.has_slot("auto"))
	# 遊戲啟動時顯示主選單
	UIManager.push("MainMenu")

func _on_start() -> void:
	UIManager.pop_all()
	# 新遊戲：啟動第一章（章節已 scan，這裡切到 active 狀態）
	if ChapterManager.current() == null:
		ChapterManager.start_chapter("ch01_arrival")

func _on_load() -> void:
	var panel: SaveLoadPanel = UIManager.get_panel("SaveLoadPanel") as SaveLoadPanel
	if panel != null:
		panel.open(SaveLoadPanel.Mode.LOAD)

func _on_quit() -> void:
	get_tree().quit()
