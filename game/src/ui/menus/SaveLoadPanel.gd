## SaveLoadPanel — 清單式存讀檔面板
## 模式：SAVE（點手動位存）/ LOAD（點任一位讀）。auto 位唯讀。
class_name SaveLoadPanel
extends Control

enum Mode { SAVE, LOAD }

@onready var _title: Label = $Panel/VBox/Title
@onready var _slot_list: VBoxContainer = $Panel/VBox/SlotList
@onready var _close_btn: Button = $Panel/VBox/CloseButton

var _mode: Mode = Mode.SAVE

func _ready() -> void:
	UIManager.register("SaveLoadPanel", self)
	_close_btn.pressed.connect(func() -> void: UIManager.pop())
	_close_btn.pressed.connect(UISfx.play_click)

## 開啟面板（指定模式）。由 PauseMenu / MainMenu 呼叫。
func open(mode: Mode) -> void:
	_mode = mode
	_title.text = "存檔" if mode == Mode.SAVE else "讀檔"
	_refresh()
	UIManager.push("SaveLoadPanel")

func _refresh() -> void:
	for child: Node in _slot_list.get_children():
		child.queue_free()
	for info: Dictionary in SaveManager.list_slots():
		_slot_list.add_child(_make_row(info))

func _make_row(info: Dictionary) -> Control:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var slot: Variant = info["slot"]
	var is_auto: bool = info["is_auto"]
	var label: Label = Label.new()
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 12)
	label.text = _row_text(info)
	row.add_child(label)

	if _mode == Mode.SAVE and not is_auto:
		var save_btn: Button = Button.new()
		save_btn.text = "存"
		save_btn.pressed.connect(func() -> void:
			SaveManager.save_to_slot(slot)
			_refresh()
		)
		save_btn.pressed.connect(UISfx.play_click)
		row.add_child(save_btn)
	if _mode == Mode.LOAD and info.get("exists", false):
		var load_btn: Button = Button.new()
		load_btn.text = "讀"
		load_btn.pressed.connect(func() -> void:
			UIManager.pop_all()
			SaveManager.load_from_slot(slot)
		)
		load_btn.pressed.connect(UISfx.play_click)
		row.add_child(load_btn)
	if not is_auto and info.get("exists", false):
		var del_btn: Button = Button.new()
		del_btn.text = "刪"
		del_btn.pressed.connect(func() -> void:
			SaveManager.delete_slot(slot)
			_refresh()
		)
		del_btn.pressed.connect(UISfx.play_click)
		row.add_child(del_btn)
	return row

func _row_text(info: Dictionary) -> String:
	var slot: Variant = info["slot"]
	var name_part: String = "自動存檔" if info["is_auto"] else "存檔 %s" % str(slot)
	if not info.get("exists", false):
		return "%s ：（空）" % name_part
	var chapter_id: String = info.get("chapter_id", "")
	var secs: int = int(info.get("time_played_sec", 0.0))
	var hh: int = secs / 3600
	var mm: int = (secs % 3600) / 60
	return "%s ：%s ｜遊玩 %02d:%02d" % [name_part, chapter_id, hh, mm]
