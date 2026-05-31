## QuestData — 任務資料定義
## 每個任務對應一個 .tres 資源檔。
class_name QuestData
extends Resource

enum QuestStatus { LOCKED, AVAILABLE, ACTIVE, COMPLETED }

@export var quest_id: String = ""
@export var title: String = ""                     # 顯示名稱
@export var description: String = ""               # 任務描述
@export var giver_npc_id: String = ""              # 發放任務的 NPC
@export var target_zone: String = ""               # 任務目標區域（可選）
@export var target_npc_id: String = ""             # 任務目標 NPC（可選）

## 前置條件：需要完成哪些事件才能接取
@export var required_events: Array[String] = []
## 完成條件：需要哪些事件被觸發才算完成
@export var completion_events: Array[String] = []

## 多步驟子目標。每項：{
##   "id": String, "desc": String,          # desc 顯示於 journal
##   "event": String,  (二選一) 此事件在 completed_events 即達成
##   "flag":  String,  (二選一) 此 flag 在 player_flags 為 true 即達成
##   "optional": bool   # 預設 false；true 不影響任務完成，只作支線提示
## }
@export var objectives: Array[Dictionary] = []

## 完成後獎勵
@export var reward_relationship: Dictionary = {}   # npc_id -> int delta
@export var reward_unlock_zone: String = ""        # 解鎖區域
@export var reward_event: String = ""              # 觸發事件

## 單一 objective 是否達成：event 在 completed_events，或 flag 在 flags 為 true。
static func is_objective_done(obj: Dictionary, completed_events: Array, flags: Dictionary) -> bool:
	var ev: String = obj.get("event", "")
	if ev != "" and completed_events.has(ev):
		return true
	var fl: String = obj.get("flag", "")
	if fl != "" and flags.get(fl, false):
		return true
	return false

## 所有「非 optional」objective 是否全部達成。空陣列回 true（交由 completion_events 判定）。
static func all_required_objectives_done(objectives: Array, completed_events: Array, flags: Dictionary) -> bool:
	for obj: Dictionary in objectives:
		if obj.get("optional", false):
			continue
		if not is_objective_done(obj, completed_events, flags):
			return false
	return true
