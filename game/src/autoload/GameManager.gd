extends Node

# ── Signals ────────────────────────────────────────────────────────────────
signal game_state_changed(new_state: GameState)
signal server_ready()
signal server_failed(error: String)

# ── Enums ──────────────────────────────────────────────────────────────────
enum GameState { MAIN_MENU, EXPLORING, DIALOGUE, PAUSED, LOADING }

# ── State ──────────────────────────────────────────────────────────────────
var current_state: GameState = GameState.MAIN_MENU
var _server_pid: int = -1
var _ai_config: Dictionary = {}
var _time_played_sec: float = 0.0
var _pending_load_position: Vector2 = Vector2.INF  # INF = 無待載入位置

# ── Constants ──────────────────────────────────────────────────────────────
const CONFIG_PATH: String = "../../llm_engine/config.json"

# ── Lifecycle ──────────────────────────────────────────────────────────────
func _ready() -> void:
	_load_ai_config()

func _process(delta: float) -> void:
	if current_state == GameState.EXPLORING:
		_time_played_sec += delta
	# 載入存檔後定位玩家
	if _pending_load_position != Vector2.INF:
		var players: Array[Node] = get_tree().get_nodes_in_group("player")
		if not players.is_empty():
			players[0].global_position = _pending_load_position
			_pending_load_position = Vector2.INF

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		shutdown_server()

# ── Config ─────────────────────────────────────────────────────────────────
func _load_ai_config() -> void:
	var config_path: String = ProjectSettings.globalize_path("res://") + "../llm_engine/config.json"
	var file: FileAccess = FileAccess.open(config_path, FileAccess.READ)
	if file == null:
		push_warning("GameManager: llm_engine/config.json not found at: " + config_path)
		return
	var json: JSON = JSON.new()
	var err: int = json.parse(file.get_as_text())
	file.close()
	if err != OK:
		push_error("GameManager: Failed to parse config.json")
		return
	_ai_config = json.data

# ── Server Lifecycle ───────────────────────────────────────────────────────
func launch_llama_server() -> void:
	if _ai_config.is_empty():
		server_failed.emit("config.json not loaded")
		return

	# If server already running, skip launch
	var http: HTTPClient = HTTPClient.new()
	var port: int = _ai_config.get("server", {}).get("port", 8000)
	var host: String = _ai_config.get("server", {}).get("host", "localhost")
	if http.connect_to_host(host, port) == OK:
		print("GameManager: llama-server already running, skipping launch")
		server_ready.emit()
		return

	var binary_path: String = _get_server_binary_path()
	var model_path: String = _get_model_path()
	if binary_path.is_empty() or model_path.is_empty():
		server_failed.emit("Could not resolve server binary or model path")
		return

	var args: Array[String] = ["-m", model_path, "--port", str(port),
		"-c", str(_ai_config.get("server", {}).get("context_size", 2048)),
		"-ngl", str(_ai_config.get("server", {}).get("gpu_layers", 20))]
	_server_pid = OS.create_process(binary_path, args)
	if _server_pid <= 0:
		server_failed.emit("Failed to start llama-server process")
		return

	# Poll health endpoint until ready
	_poll_server_health.call_deferred()

func _poll_server_health() -> void:
	var timeout: float = _ai_config.get("server", {}).get("startup_timeout_sec", 30.0)
	var elapsed: float = 0.0
	while elapsed < timeout:
		AIClient.check_server_health()
		await get_tree().create_timer(1.0).timeout
		elapsed += 1.0
		if AIClient.is_server_online:
			server_ready.emit()
			return
	server_failed.emit("llama-server 啟動逾時（%d 秒），請檢查 binary/model 路徑與系統資源" % int(timeout))

func shutdown_server() -> void:
	if _server_pid > 0:
		OS.kill(_server_pid)
		_server_pid = -1

# ── Path Resolution ────────────────────────────────────────────────────────
func _get_server_binary_path() -> String:
	var platform: String = OS.get_name()
	var key: String
	match platform:
		"Windows": key = "windows"
		"Linux": key = "linux"
		"macOS": key = "macos"
		_: key = "linux"

	var rel_path: String = _ai_config.get("binaries", {}).get(key, "")
	if rel_path.is_empty():
		return ""
	return _resolve_llm_engine_path(rel_path)

func _get_model_path() -> String:
	var rel_path: String = _ai_config.get("model_path", "")
	if rel_path.is_empty():
		return ""
	return _resolve_llm_engine_path(rel_path)

func _resolve_llm_engine_path(relative: String) -> String:
	# Works both in editor and exported builds
	var base: String
	if OS.has_feature("editor"):
		base = ProjectSettings.globalize_path("res://") + "../llm_engine/"
	else:
		base = OS.get_executable_path().get_base_dir() + "/llm_engine/"
	return (base + relative).simplify_path()

# ── State Machine ──────────────────────────────────────────────────────────
func change_state(new_state: GameState) -> void:
	if current_state == new_state:
		return
	current_state = new_state
	game_state_changed.emit(new_state)

# ── Runtime 狀態存取（給 SaveManager 用）────────────────────────────────────
## 收集玩家當前世界座標（無玩家時回 Vector2.ZERO）。
func collect_player_position() -> Vector2:
	var players: Array[Node] = get_tree().get_nodes_in_group("player")
	if players.is_empty():
		return Vector2.ZERO
	return players[0].global_position

## 目前累計遊玩秒數。
func get_time_played_sec() -> float:
	return _time_played_sec

## 載入存檔後還原執行期狀態：遊玩時間 + 待定位玩家座標。
func apply_loaded_runtime(time_played: float, player_pos: Vector2) -> void:
	_time_played_sec = time_played
	_pending_load_position = player_pos

## 回主選單：重置 autoload 狀態 + reload 主場景（MainMenu 會自動重新 push）
func return_to_main_menu() -> void:
	# 重置故事 / 任務 / 章節 / 時空 狀態（傳空 dict 讓 deserialize 套預設值）
	StoryManager.deserialize({})
	QuestManager.deserialize({})
	ChapterManager.deserialize({})
	EraManager.deserialize({})
	_time_played_sec = 0.0
	# 中止任何 in-flight AI 請求
	AIClient.abort_current_request()
	# 切回 MAIN_MENU state，reload 主場景讓 zone/player 重置
	change_state(GameState.MAIN_MENU)
	get_tree().reload_current_scene()

