extends Node

# ── Signals ────────────────────────────────────────────────────────────────
signal event_recorded(event_id: String)
signal flag_changed(key: String, value: Variant)

# ── State ──────────────────────────────────────────────────────────────────
var unlocked_zones: Array[String] = [Zones.STARTING]
var completed_events: Array[String] = []
var player_flags: Dictionary = {}
var npc_relationships: Dictionary = {}          # npc_id -> int (-100 to 100)
## relationship 跨門檻時派生的一次性事件設定。每項：{npc_id, threshold, event_id}
var _relationship_triggers: Array[Dictionary] = []
var conversation_histories: Dictionary = {}     # npc_id -> Array[Dictionary]
var current_zone: String = Zones.STARTING
var game_time_hours: float = 14.0               # 0.0 - 24.0 (in-game clock)

## 遊戲內時間流速：1 秒真實時間 = N 分鐘遊戲時間
## 預設 1.0 = 1 秒真實時間推進 1 分鐘遊戲時間（24 分鐘真實時間 = 遊戲內一天）
const TIME_SCALE: float = 1.0  # minutes per real second

func _ready() -> void:
	pass

var _time_accumulator: float = 0.0

func _process(delta: float) -> void:
	if GameManager.current_state != GameManager.GameState.EXPLORING:
		return
	_time_accumulator += delta
	if _time_accumulator >= 1.0:
		game_time_hours += (_time_accumulator * TIME_SCALE) / 60.0
		_time_accumulator = 0.0
		if game_time_hours >= 24.0:
			game_time_hours -= 24.0

# ── Context Builder (核心方法) ────────────────────────────────────────────
## 依當前章節 stage_rules + player_flags 推導劇情階段 id。無章節/無規則回空字串。
func get_current_stage() -> String:
	var current: ChapterConfig = ChapterManager.current()
	if current == null:
		return ""
	return current.resolve_stage(player_flags)

## 給 AI 用的完整對話 context。包含章節 overlay，以解除 AIClient 對 ChapterManager 的直接依賴。
func build_ai_context(npc_id: String) -> Dictionary:
	return {
		"zone": current_zone,
		"zone_display": Zones.display_name(current_zone),
		"time_of_day": _get_time_string(),
		"time_period": _get_time_period(),
		"relationship": npc_relationships.get(npc_id, 0),
		"recent_events": _get_recent_events(5),
		"player_visited_zones": unlocked_zones.duplicate(),
		"conversation_history": conversation_histories.get(npc_id, []).duplicate(),
		"chapter_overlay": ChapterManager.get_npc_overlay(npc_id),
		"story_stage": get_current_stage(),
		"stage_order": ChapterManager.get_current_stage_order(),
		"player_flags": player_flags.duplicate(),
	}

# ── Time Helpers ───────────────────────────────────────────────────────────
func _get_time_string() -> String:
	var h: int = int(game_time_hours)
	var period: String = "上午" if h < 12 else "下午"
	var display_h: int = h if h <= 12 else h - 12
	if display_h == 0:
		display_h = 12
	return "%s%d點" % [period, display_h]

func _get_time_period() -> String:
	var h: int = int(game_time_hours)
	if h < 6:   return "deep_night"
	if h < 10:  return "morning"
	if h < 14:  return "noon"
	if h < 18:  return "afternoon"
	if h < 21:  return "evening"
	return "night"

func _get_recent_events(count: int) -> Array[String]:
	var total: int = completed_events.size()
	var start: int = max(0, total - count)
	var result: Array[String] = []
	for i in range(start, total):
		result.append(completed_events[i])
	return result

# ── Event Tracking ─────────────────────────────────────────────────────────
func record_event(event_id: String) -> void:
	if not completed_events.has(event_id):
		completed_events.append(event_id)
		event_recorded.emit(event_id)

func set_flag(key: String, value: Variant) -> void:
	player_flags[key] = value
	flag_changed.emit(key, value)

func get_flag(key: String, default: Variant = null) -> Variant:
	return player_flags.get(key, default)

func unlock_zone(zone_id: String) -> void:
	if not unlocked_zones.has(zone_id):
		unlocked_zones.append(zone_id)

## 註冊「某 NPC 信任值 ≥ threshold 時記錄 event_id」。重複註冊（相同三元組）會被忽略。
func register_relationship_event(npc_id: String, threshold: int, event_id: String) -> void:
	for trig: Dictionary in _relationship_triggers:
		if trig["npc_id"] == npc_id and int(trig["threshold"]) == threshold and trig["event_id"] == event_id:
			return
	_relationship_triggers.append({"npc_id": npc_id, "threshold": threshold, "event_id": event_id})

func update_relationship(npc_id: String, delta: int) -> void:
	var current: int = npc_relationships.get(npc_id, 0)
	var new_val: int = clamp(current + delta, -100, 100)
	npc_relationships[npc_id] = new_val
	for trig: Dictionary in _relationship_triggers:
		if trig["npc_id"] == npc_id and new_val >= int(trig["threshold"]):
			record_event(trig["event_id"])  # record_event 內含去重

const MAX_HISTORY_PER_NPC: int = 20

func add_conversation_turn(npc_id: String, role: String, content: String) -> void:
	if not conversation_histories.has(npc_id):
		conversation_histories[npc_id] = []
	conversation_histories[npc_id].append({"role": role, "content": content})
	if conversation_histories[npc_id].size() > MAX_HISTORY_PER_NPC:
		conversation_histories[npc_id] = conversation_histories[npc_id].slice(-MAX_HISTORY_PER_NPC)

## 清空所有 NPC 的對話歷史。zone 切換時呼叫,讓 NPC「忘掉」上個場景的對話。
## 長期記憶仍保留在 completed_events / player_flags / npc_relationships。
func clear_conversation_histories() -> void:
	conversation_histories.clear()

# ── Persistence ────────────────────────────────────────────────────────────
func serialize() -> Dictionary:
	return {
		"unlocked_zones": unlocked_zones,
		"completed_events": completed_events,
		"player_flags": player_flags,
		"npc_relationships": npc_relationships,
		"conversation_histories": conversation_histories,
		"current_zone": current_zone,
		"game_time_hours": game_time_hours,
	}

func deserialize(data: Dictionary) -> void:
	# JSON 反序列化回來是無型別 Array，需手動轉型
	unlocked_zones.assign(data.get("unlocked_zones", [Zones.STARTING]))
	completed_events.assign(data.get("completed_events", []))
	player_flags = data.get("player_flags", {})
	npc_relationships = data.get("npc_relationships", {})
	conversation_histories = data.get("conversation_histories", {})
	current_zone = data.get("current_zone", Zones.STARTING)
	game_time_hours = data.get("game_time_hours", 14.0)
