## QuestJournal — 任務日誌面板
class_name QuestJournal
extends Control

@onready var _active_list: VBoxContainer    = $Panel/VBox/ActiveSection/ActiveList
@onready var _completed_list: VBoxContainer = $Panel/VBox/CompletedSection/CompletedList

func _ready() -> void:
	UIManager.register("QuestJournal", self)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_journal"):
		if UIManager.current_panel == "QuestJournal":
			UIManager.pop()
		elif not UIManager.is_any_open:
			_refresh()
			UIManager.toggle("QuestJournal")
		get_viewport().set_input_as_handled()

func _refresh() -> void:
	_clear_list(_active_list)
	_clear_list(_completed_list)

	var active: Array[QuestData] = QuestManager.get_active_quests()
	if active.is_empty():
		_add_item(_active_list, "(none)", Color(0.5, 0.5, 0.5))
	else:
		for q: QuestData in active:
			_add_item(_active_list, q.title, Color.WHITE)
			_add_item(_active_list, "  " + q.description, Color(0.7, 0.7, 0.7), 10)
			for obj: Dictionary in QuestManager.get_objective_status(q.quest_id):
				var mark: String = "☑" if obj["done"] else "☐"
				var suffix: String = "（選擇）" if obj["optional"] else ""
				var col: Color = Color(0.5, 0.8, 0.5) if obj["done"] else Color(0.85, 0.85, 0.6)
				_add_item(_active_list, "    %s %s%s" % [mark, obj["desc"], suffix], col, 10)

	var completed: Array[String] = QuestManager._completed_quests
	if completed.is_empty():
		_add_item(_completed_list, "(none)", Color(0.5, 0.5, 0.5))
	else:
		for qid: String in completed:
			var q: QuestData = QuestManager.get_quest(qid)
			if q:
				_add_item(_completed_list, "✓ " + q.title, Color(0.5, 0.8, 0.5))

func _add_item(container: VBoxContainer, text: String, color: Color, font_size: int = 12) -> void:
	var label: Label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	container.add_child(label)

func _clear_list(container: VBoxContainer) -> void:
	for child: Node in container.get_children():
		child.queue_free()
