extends Node

# ── Signals ────────────────────────────────────────────────────────────────
signal response_complete(full_text: String, npc_id: String)
signal request_failed(error_msg: String)
signal server_status_changed(is_online: bool)

# ── Config ──────────────────────────────────────────────────────────────────
var server_url: String = "http://127.0.0.1:8000"
var is_server_online: bool = false
var default_temperature: float = 0.7
var default_max_tokens: int = 200
var request_timeout_sec: float = 30.0
## llama-server 的 context 視窗大小;同步自 config.json 的 server.context_size。
## 用於 client 端 pre-flight 預算檢查 — 估算 prompt 超量時自動裁掉最舊的 history。
var context_size: int = 8192

# ── Internal ────────────────────────────────────────────────────────────────
var _http: HTTPRequest          # 用於 AI query
var _health_http: HTTPRequest   # 用於 health check（獨立）
var _current_npc_id: String = ""
var _current_profile: NPCConfig = null   # 用於 post-process 過濾禁忌詞
var _current_flags: Dictionary = {}      # query 當下的 player_flags 快照
var _is_busy: bool = false

func _ready() -> void:
	_http = HTTPRequest.new()
	_http.timeout = request_timeout_sec
	add_child(_http)
	_http.request_completed.connect(_on_query_completed)

	_health_http = HTTPRequest.new()
	_health_http.timeout = 5.0
	add_child(_health_http)
	_health_http.request_completed.connect(_on_health_completed)

	await get_tree().process_frame
	_sync_server_url()
	# 啟動時自動檢查伺服器是否在線
	check_server_health()

func _sync_server_url() -> void:
	var config: Dictionary = GameManager._ai_config
	if config.is_empty():
		return
	var server_cfg: Dictionary = config.get("server", {})
	var host: String = server_cfg.get("host", "localhost")
	var port: int = server_cfg.get("port", 8000)
	server_url = "http://%s:%d" % [host, port]
	context_size = int(server_cfg.get("context_size", 8192))

# ── Health Check ────────────────────────────────────────────────────────────
func check_server_health() -> void:
	var err: int = _health_http.request(server_url + "/health")
	if err != OK:
		_set_online(false)

func _on_health_completed(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
		_set_online(true)
		print("AIClient: 伺服器已連線 ✓")
	else:
		_set_online(false)
		print("AIClient: 伺服器未回應 (HTTP %d)" % response_code)

# ── Core Query ──────────────────────────────────────────────────────────────
func query(npc_config: Resource, user_input: String, context: Dictionary) -> void:
	if _is_busy:
		push_warning("AIClient: Already processing a request, ignoring new query")
		return
	if not is_server_online:
		# 先嘗試一次 health check，也許伺服器剛啟動
		request_failed.emit("AI 伺服器尚未連線，請確認 llama-server 已啟動")
		check_server_health()
		return

	_is_busy = true
	_current_npc_id = npc_config.npc_id
	_current_profile = npc_config as NPCConfig
	_current_flags = context.get("player_flags", {}).duplicate()

	var payload: Dictionary = _build_chat_payload(npc_config, user_input, context)
	var body: String = JSON.stringify(payload)
	var headers: PackedStringArray = ["Content-Type: application/json"]

	var err: int = _http.request(
		server_url + "/v1/chat/completions",
		headers,
		HTTPClient.METHOD_POST,
		body
	)
	if err != OK:
		_is_busy = false
		request_failed.emit("HTTP 請求發送失敗 (error %d)" % err)

func _on_query_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_is_busy = false

	# 若請求已被取消（abort_current_request 清空了 _current_npc_id），丟棄此回應
	if _current_npc_id.is_empty():
		return

	if result == HTTPRequest.RESULT_TIMEOUT:
		_set_online(false)
		_clear_query_state()
		request_failed.emit("AI 伺服器逾時（%d 秒未回應），請確認 llama-server 狀態" % int(request_timeout_sec))
		return
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		_set_online(false)
		_clear_query_state()
		request_failed.emit("伺服器回應錯誤 (result=%d, HTTP %d)" % [result, response_code])
		return

	_set_online(true)

	var json: JSON = JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		request_failed.emit("無法解析 AI 回應 JSON")
		return

	var data: Dictionary = json.data
	var content: String = ""
	var choices: Array = data.get("choices", [])

	if not choices.is_empty():
		var message: Dictionary = choices[0].get("message", {})
		content = str(message.get("content", ""))

	# 清除所有 <think>...</think> 標籤
	while content.contains("<think>"):
		var think_start: int = content.find("<think>")
		var think_end: int = content.find("</think>")
		if think_end != -1:
			content = content.substr(0, think_start) + content.substr(think_end + 8)
		else:
			# </think> 不存在 = 思考被截斷，移除從 <think> 開始的所有內容
			content = content.substr(0, think_start)
		content = content.strip_edges()

	if content.is_empty() or content == "null":
		request_failed.emit("AI 回應為空，請重試")
		return

	# Post-process: 過濾未解鎖的禁忌詞（防 LLM 違反 prompt 約束）
	if _current_profile != null:
		content = TrustGate.filter_forbidden(content, _current_profile, _current_flags)

	# Save to conversation history
	StoryManager.add_conversation_turn(_current_npc_id, "assistant", content)

	var npc_id: String = _current_npc_id
	_current_npc_id = ""
	_current_profile = null
	_current_flags = {}
	response_complete.emit(content, npc_id)

## Token 估算 — 1 CJK 字 ≈ 1 token,英文略低估但保守無妨;
## 每則訊息額外 +4 token 作為 role/格式 wrapper 的 overhead。
const _TOKEN_PER_MSG_OVERHEAD: int = 4
## 安全餘量:扣完 max_tokens 之後再留這麼多 token 給 chat_template 包裝、stop tokens 等。
const _CONTEXT_SAFETY_MARGIN: int = 128

func _estimate_tokens(text: String) -> int:
	return text.length()

func _estimate_message_tokens(msg: Dictionary) -> int:
	return _estimate_tokens(str(msg.get("content", ""))) + _TOKEN_PER_MSG_OVERHEAD

# ── Payload Builder ─────────────────────────────────────────────────────────
func _build_chat_payload(npc_config: Resource, user_input: String, context: Dictionary) -> Dictionary:
	# 用 TrustGate 組裝核心 system prompt（人格 + 章節 overlay + 信任值門檻）
	var system_content: String = TrustGate.build_system_prompt(
		npc_config as NPCConfig,
		int(context.get("relationship", 0)),
		context.get("player_flags", {}),
		context.get("chapter_overlay", "")
	)
	# 追加 per-call 動態情境（time / zone / recent events）— 不適合進 TrustGate
	system_content += "\n\n" + _build_context_string(context)

	var max_response: int = npc_config.max_response_tokens if "max_response_tokens" in npc_config else default_max_tokens
	var system_msg: Dictionary = {"role": "system", "content": system_content}
	var user_msg: Dictionary = {"role": "user", "content": user_input}
	var prefill_msg: Dictionary = {"role": "assistant", "content": "<think>\n</think>\n", "prefix": true}

	# 先取 conversation_memory_turns 的硬上限,再做 token 預算檢查
	var history: Array = context.get("conversation_history", [])
	var max_turns: int = npc_config.conversation_memory_turns if "conversation_memory_turns" in npc_config else 6
	var start: int = max(0, history.size() - max_turns * 2)
	var history_slice: Array = history.slice(start, history.size())

	# Token 預算:input 部分(system + history + user + prefill) 不能超過
	# context_size - max_response - safety_margin
	var input_budget: int = context_size - max_response - _CONTEXT_SAFETY_MARGIN
	var fixed_tokens: int = (
		_estimate_message_tokens(system_msg)
		+ _estimate_message_tokens(user_msg)
		+ _estimate_message_tokens(prefill_msg)
	)
	var history_tokens: int = 0
	for m: Dictionary in history_slice:
		history_tokens += _estimate_message_tokens(m)

	# 超量 → 從最舊端 pop 直到塞得下;成對 pop(user+assistant)避免破壞對話結構
	var dropped: int = 0
	while history_slice.size() > 0 and fixed_tokens + history_tokens > input_budget:
		var removed: Dictionary = history_slice.pop_front()
		history_tokens -= _estimate_message_tokens(removed)
		dropped += 1
	if dropped > 0:
		push_warning(
			"AIClient: prompt token budget exceeded → dropped %d oldest history messages (npc=%s, budget=%d, fixed=%d, history=%d)"
			% [dropped, npc_config.npc_id, input_budget, fixed_tokens, history_tokens]
		)

	# 組裝最終 messages
	var messages: Array[Dictionary] = [system_msg]
	for m: Dictionary in history_slice:
		messages.append(m)
	messages.append(user_msg)
	StoryManager.add_conversation_turn(npc_config.npc_id, "user", user_input)
	messages.append(prefill_msg)

	return {
		"model": "default",
		"messages": messages,
		"max_tokens": max_response,
		"temperature": npc_config.base_temperature if "base_temperature" in npc_config else default_temperature,
		"stream": false,
	}

func _build_context_string(context: Dictionary) -> String:
	var rel: int = context.get("relationship", 0)
	var rel_tag: String = "stranger"
	if rel >= 60:     rel_tag = "close_friend"
	elif rel >= 30:   rel_tag = "acquaintance"
	elif rel >= 10:   rel_tag = "seen_before"
	elif rel <= -30:  rel_tag = "unfriendly"
	var ctx: String = "[Context] time=%s, zone=%s, rel=%s" % [
		context.get("time_of_day", ""),
		context.get("zone_display", ""),
		rel_tag]
	var events: Array = context.get("recent_events", [])
	if not events.is_empty():
		ctx += ", recent=" + ",".join(events)
	return ctx

# ── Internal Helpers ─────────────────────────────────────────────────────────
func _set_online(online: bool) -> void:
	if is_server_online != online:
		is_server_online = online
		server_status_changed.emit(online)
		if online:
			EventBus.ai_server_online.emit()
		else:
			EventBus.ai_server_offline.emit()

func abort_current_request() -> void:
	if _is_busy:
		_http.cancel_request()
		_is_busy = false
		_clear_query_state()

func _clear_query_state() -> void:
	_current_npc_id = ""
	_current_profile = null
	_current_flags = {}
