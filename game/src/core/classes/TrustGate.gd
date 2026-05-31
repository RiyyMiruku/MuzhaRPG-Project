## TrustGate — system prompt 組裝器（純函式）
##
## 設計原則：所有依賴透過參數注入，不直接呼叫任何 autoload。
## caller（AIClient / 未來 BeatRunner）負責從 ChapterManager / StoryManager 取資料再傳入。
## 這讓 TrustGate 可獨立測試、避免循環依賴、不會因為 autoload 改名而壞掉。
class_name TrustGate
extends RefCounted

## 構造完整的 NPC 對話 system prompt
##
## 參數：
##   profile         - NPC 設定（NPCProfile，或 fallback NPCConfig）
##   trust           - 當前信任值（StoryManager.npc_relationships.get(npc_id, 0)）
##   flags           - 玩家 flags（StoryManager.player_flags）
##   chapter_overlay - 章節差異片段（ChapterManager.get_npc_overlay(npc_id)）
##
## 回傳：拼好的 system prompt 字串
static func build_system_prompt(
	profile: NPCConfig,
	trust: int,
	flags: Dictionary,
	chapter_overlay: String = "",
	stage_attitude: String = ""
) -> String:
	var parts: Array[String] = []

	# 1. 基底人格
	parts.append(profile.system_prompt)

	# 2. 章節 overlay
	if not chapter_overlay.is_empty():
		parts.append("[章節背景] " + chapter_overlay)

	# 以下只有 NPCProfile 才有，NPCConfig 跳過
	if profile is NPCProfile:
		var p: NPCProfile = profile as NPCProfile

		# 3. 講話風格
		if not p.personality_voice.is_empty():
			parts.append("[語氣] " + p.personality_voice)

		# 3.5 現階段劇情態度
		if not stage_attitude.is_empty():
			parts.append("[現階段態度] " + stage_attitude)

		# 4. 信任值決定的 allowed topics
		var allowed: Array = []
		for unlock: Dictionary in p.trust_revelations:
			var threshold: int = int(unlock.get("threshold", 0))
			if trust >= threshold:
				var topics: Array = unlock.get("topics", [])
				allowed.append_array(topics)
		if not allowed.is_empty():
			parts.append("[你願意聊] " + ", ".join(allowed))

		# 5. 禁忌主題
		var forbidden: Array = []
		for topic: String in p.forbidden_until_flag:
			var required_flag: String = p.forbidden_until_flag[topic]
			if not flags.get(required_flag, false):
				forbidden.append(topic)
		if not forbidden.is_empty():
			parts.append("[絕對不能提] " + ", ".join(forbidden))

		# 6. 已知事實
		if not p.known_facts.is_empty():
			parts.append("[你知道的事]\n - " + "\n - ".join(p.known_facts))

	# 7. 信任值
	parts.append("[對玩家信任度] %d/100" % trust)

	# 8. 信任評分指令：要 NPC 在回覆最後輸出隱藏 tag（client 會剝除）
	parts.append(
		"[信任評分] 在你回覆的最後，依玩家這一輪的態度附上一個隱藏標記 <trust±N>"
		+ "（N 為 0 到 3 的整數）。評分標準：玩家溫和有禮、尊重你、展現可信、不過度逼問隱私 → 正值；"
		+ "冒犯、逼問太緊、自稱知道不該知道的事、說出與『南部來打工的表親之子』身分矛盾的話 → 負值；"
		+ "一般寒暄問路給 <trust+0>。多數情況給 0 或 1。例：<trust+1>"
	)

	return "\n".join(parts)


## 後處理：過濾未解鎖的禁忌詞，避免 LLM 違反 prompt 約束
## 將禁忌詞替換為「他」/「那個人」並 log warning。
##
## 回傳：過濾後的字串
static func filter_forbidden(
	text: String,
	profile: NPCConfig,
	flags: Dictionary
) -> String:
	if not (profile is NPCProfile):
		return text
	var p: NPCProfile = profile as NPCProfile
	var result: String = text
	for topic: String in p.forbidden_until_flag:
		var required_flag: String = p.forbidden_until_flag[topic]
		if flags.get(required_flag, false):
			continue   # 已解鎖
		if result.contains(topic):
			push_warning("TrustGate: LLM 提及未解鎖禁忌詞 '%s'，已過濾" % topic)
			result = result.replace(topic, "那個人")
	return result

## 解析 NPC 在指定 stage 的態度片段，含「往前繼承」：
## 若 current_stage 沒填，沿 stage_order 往前找最近一個有填的 stage。
## stage_order 為 stage_id 由前到後的陣列（即 ChapterConfig.stage_rules 的 stage_id 序）。
## 找不到任何片段回空字串。
static func resolve_stage_attitude(
	profile: NPCConfig,
	current_stage: String,
	stage_order: Array
) -> String:
	if not (profile is NPCProfile):
		return ""
	var p: NPCProfile = profile as NPCProfile
	if p.stage_attitudes.is_empty() or current_stage.is_empty():
		return ""
	var idx: int = stage_order.find(current_stage)
	if idx == -1:
		# stage 不在 order 中，直接查當格
		return str(p.stage_attitudes.get(current_stage, ""))
	for i in range(idx, -1, -1):
		var sid: String = str(stage_order[i])
		if p.stage_attitudes.has(sid):
			return str(p.stage_attitudes[sid])
	return ""


## 從 LLM 回應解析信任 delta。抓最後一個 <trust±N>，clamp 到 -3..3。無 tag 回 0。
static func parse_trust_delta(text: String) -> int:
	var re: RegEx = RegEx.new()
	re.compile("<trust([+-]\\d+)>")
	var matches: Array[RegExMatch] = re.search_all(text)
	if matches.is_empty():
		return 0
	var last: RegExMatch = matches[matches.size() - 1]
	var val: int = last.get_string(1).to_int()
	return clampi(val, -3, 3)

## 移除回應中所有 <trust±N> tag，回傳乾淨內容（前後去空白）。
static func strip_trust_tag(text: String) -> String:
	var re: RegEx = RegEx.new()
	re.compile("<trust[+-]\\d+>")
	return re.sub(text, "", true).strip_edges()
