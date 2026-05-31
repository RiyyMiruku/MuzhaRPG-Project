## BaseNPC — NPC 基底類別
## 綁定一個 NPCConfig 資源，並在玩家靠近時顯示互動提示、開啟對話。
class_name BaseNPC
extends BaseCharacter

# ── Config ───────────────────────────────────────────────────────────────────
@export var npc_config: NPCConfig

# ── Node References ──────────────────────────────────────────────────────────
@onready var _sprite: AnimatedSprite2D    = $AnimatedSprite2D
@onready var _prompt_label: Label         = $InteractionPrompt
@onready var _detect_area: Area2D         = $DetectArea

# ── State ────────────────────────────────────────────────────────────────────
var _dialogue_ui: DialogueUI = null
var _conversation_active: bool = false

# ── Wander state ─────────────────────────────────────────────────────────────
## 設定請見 NPCConfig 的 wander_* 欄位。
## radius=0 → 完全跳過 wander 邏輯，行為跟以前靜止 NPC 相同。
enum _WanderState { DISABLED, IDLE, WALKING }
const _ARRIVE_THRESHOLD: float = 4.0   # 距離 target 小於此就算到達
const _DEFAULT_WANDER_SPEED: float = 40.0
var _wander_state: int = _WanderState.DISABLED
var _wander_origin: Vector2 = Vector2.ZERO  # spawn 位置 = wander 中心
var _wander_target: Vector2 = Vector2.ZERO
var _wander_pause_left: float = 0.0
var _wander_paused_by_player: bool = false

func _ready() -> void:
	sprite = _sprite
	move_speed = 0.0   # NPC 預設靜止

	# 從預編譯 spritesheet 載入；找不到則退回橘色佔位
	if _sprite.sprite_frames == null and npc_config != null and not npc_config.npc_id.is_empty():
		_sprite.sprite_frames = SpriteSheetLoader.load_character(npc_config.npc_id)

	if _sprite.sprite_frames == null:
		_sprite.sprite_frames = PlaceholderSprite.generate_sprite_frames(
			Color.ORANGE_RED, Color.YELLOW, Vector2i(16, 24)
		)
	_sprite.play("idle_down")

	if npc_config == null:
		push_warning("BaseNPC: npc_config 未設定於 " + name)
		return

	_prompt_label.text = "按 [E] 對話"
	_prompt_label.hide()

	_detect_area.body_entered.connect(_on_player_entered)
	_detect_area.body_exited.connect(_on_player_exited)

	# 快取 DialogueUI 參照，避免每次互動都遍歷場景樹
	_dialogue_ui = _find_dialogue_ui()

	# 信任變動時在頭頂冒浮動箭頭（綠↑/紅↓）
	AIClient.trust_changed.connect(_on_trust_changed)

	# 初始化 wander 行為（若 config 有設）
	_init_wander()

# ── 信任浮動特效 ───────────────────────────────────────────────────────────────
## 信任變動時，在此 NPC 頭頂冒出綠↑/紅↓，上飄 + 淡出。只對自己 npc_id 反應。
func _on_trust_changed(changed_npc_id: String, direction: int) -> void:
	if npc_config == null or changed_npc_id != npc_config.npc_id:
		return
	var label: Label = Label.new()
	label.text = "↑" if direction > 0 else "↓"
	label.add_theme_font_size_override("font_size", 28)
	label.add_theme_color_override(
		"font_color",
		Color(0.3, 1.0, 0.4) if direction > 0 else Color(1.0, 0.35, 0.35)
	)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	label.add_theme_constant_override("outline_size", 4)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.z_index = 100
	# 置於頭頂中央（sprite 約 24px 高，往上偏移）
	label.position = Vector2(-12, -42)
	add_child(label)

	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(label, "position:y", label.position.y - 24.0, 0.9)
	tween.tween_property(label, "modulate:a", 0.0, 0.9).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(label.queue_free)

# ── Wander logic ─────────────────────────────────────────────────────────────
func _init_wander() -> void:
	if npc_config == null or npc_config.wander_radius <= 0.0:
		return
	# SSOT 是 spritesheet。沒 walk frame 就跳過(Inspector 端也用同邏輯藏欄位)。
	if _sprite.sprite_frames == null or not _sprite.sprite_frames.has_animation("walk_down"):
		push_warning("BaseNPC: '%s' has wander_radius>0 but no walk_down anim — skip" % npc_config.npc_id)
		return
	_wander_state = _WanderState.IDLE
	_wander_origin = global_position
	_wander_pause_left = randf_range(
		npc_config.wander_pause_min, npc_config.wander_pause_max
	)
	move_speed = npc_config.wander_speed if npc_config.wander_speed > 0.0 else _DEFAULT_WANDER_SPEED

func _physics_process(delta: float) -> void:
	if _wander_state == _WanderState.DISABLED:
		return
	# Zone 傳送中 NPC 凍住 — 避免 spawn 時撞到玩家;
	# 對話/暫停不擋,讓背景 NPC 繼續活動維持氛圍。
	if GameManager.current_state == GameManager.GameState.LOADING:
		move_with_input(Vector2.ZERO)
		return
	if _wander_paused_by_player or _conversation_active:
		move_with_input(Vector2.ZERO)
		return
	match _wander_state:
		_WanderState.IDLE:
			_wander_pause_left -= delta
			if _wander_pause_left <= 0.0:
				_pick_new_wander_target()
				_wander_state = _WanderState.WALKING
			else:
				move_with_input(Vector2.ZERO)
		_WanderState.WALKING:
			var to_target: Vector2 = _wander_target - global_position
			if to_target.length() < _ARRIVE_THRESHOLD:
				_enter_idle()
			else:
				move_with_input(to_target.normalized())

func _pick_new_wander_target() -> void:
	# 在 origin 周圍半徑內隨機選一點
	var r: float = npc_config.wander_radius
	var angle: float = randf() * TAU
	var dist: float = randf_range(r * 0.3, r)   # 偏外圈，避免老在原地踏
	_wander_target = _wander_origin + Vector2(cos(angle), sin(angle)) * dist

func _enter_idle() -> void:
	_wander_state = _WanderState.IDLE
	_wander_pause_left = randf_range(
		npc_config.wander_pause_min, npc_config.wander_pause_max
	)
	move_with_input(Vector2.ZERO)

## 外部呼叫（通常由 Player 觸發）— 開啟對話
func interact(_player: Node) -> void:
	if _conversation_active or npc_config == null:
		return
	_conversation_active = true
	_prompt_label.hide()

	if _dialogue_ui == null:
		_dialogue_ui = _find_dialogue_ui()
	if _dialogue_ui == null:
		push_error("BaseNPC: 找不到 DialogueUI 節點")
		_conversation_active = false
		return

	face_toward(_player.global_position)

	# 優先檢查當前是否有 active beat（authored 預寫對話）
	var beat: StoryBeat = ChapterManager.find_active_beat(npc_config.npc_id)
	if beat != null:
		ChapterManager.run_beat(beat, _dialogue_ui)
		# Beat 結束會呼叫 dialogue_closed → _on_dialogue_closed 收尾
		if not _dialogue_ui.dialogue_closed.is_connected(_on_dialogue_closed):
			_dialogue_ui.dialogue_closed.connect(_on_dialogue_closed, CONNECT_ONE_SHOT)
		EventBus.npc_interaction_started.emit(self)
		return

	# 沒 beat → AI mode
	_dialogue_ui.open_dialogue(npc_config)
	if not _dialogue_ui.player_submitted_input.is_connected(_on_player_input):
		_dialogue_ui.player_submitted_input.connect(_on_player_input)
	if not _dialogue_ui.dialogue_closed.is_connected(_on_dialogue_closed):
		_dialogue_ui.dialogue_closed.connect(_on_dialogue_closed, CONNECT_ONE_SHOT)
	EventBus.npc_interaction_started.emit(self)

func _on_player_input(text: String) -> void:
	var context: Dictionary = StoryManager.build_ai_context(npc_config.npc_id)
	AIClient.query(npc_config, text, context)
	# 記錄「已與此 NPC 對話」事件
	StoryManager.record_event("talked_to_" + npc_config.npc_id)

func _on_dialogue_closed() -> void:
	_conversation_active = false
	# 清理 signal 連接
	if _dialogue_ui and _dialogue_ui.player_submitted_input.is_connected(_on_player_input):
		_dialogue_ui.player_submitted_input.disconnect(_on_player_input)

# ── Detect Area ───────────────────────────────────────────────────────────────
func _on_player_entered(body: Node) -> void:
	if body is Player:
		_prompt_label.show()
		_wander_paused_by_player = true

func _on_player_exited(body: Node) -> void:
	if body is Player:
		_prompt_label.hide()
		_wander_paused_by_player = false

# ── Helpers ───────────────────────────────────────────────────────────────────
func _find_dialogue_ui() -> DialogueUI:
	# 搜尋 UILayer 下的 DialogueUI 節點
	var ui_layer: Node = get_tree().current_scene.find_child("UILayer", true, false)
	if ui_layer == null:
		return null
	return ui_layer.find_child("DialogueUI", true, false) as DialogueUI
