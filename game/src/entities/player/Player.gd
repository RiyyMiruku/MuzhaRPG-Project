 ## Player — 玩家角色
## WASD / 方向鍵移動，E 鍵與最近的 NPC/物件互動。
class_name Player
extends BaseCharacter

# ── Signals ─────────────────────────────────────────────────────────────────
signal interaction_requested(interactable: Node)

# ── Node References ──────────────────────────────────────────────────────────
@onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var _interact_area: Area2D    = $InteractArea

# ── State ────────────────────────────────────────────────────────────────────
var _nearby_interactable: Node = null
var _step_accum: float = 0.0
var _last_pos: Vector2 = Vector2.ZERO

const PLAYER_ID: String = "lin_siqian"

func _ready() -> void:
	sprite = _sprite
	_sprite.speed_scale = 1.0
	add_to_group("player")
	if _sprite.sprite_frames == null:
		_sprite.sprite_frames = SpriteSheetLoader.load_character(PLAYER_ID)
		if _sprite.sprite_frames == null:
			_sprite.sprite_frames = PlaceholderSprite.generate_sprite_frames(
				Color.CORNFLOWER_BLUE, Color.WHITE, Vector2i(16, 24)
			)
		_sprite.play("idle_down")
	_interact_area.body_entered.connect(_on_body_entered)
	_interact_area.body_exited.connect(_on_body_exited)
	GameManager.game_state_changed.connect(_on_state_changed)
	_last_pos = global_position

func _physics_process(_delta: float) -> void:
	var input_vec: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	move_with_input(input_vec)
	_update_footsteps()

func _update_footsteps() -> void:
	var moved: float = global_position.distance_to(_last_pos)
	_last_pos = global_position
	if not is_moving or velocity.length() < 1.0:
		return
	_step_accum += moved
	if _step_accum < FootstepPlayer.get_step_distance():
		return
	_step_accum = 0.0
	FootstepPlayer.play(_surface_under_player())

func _surface_under_player() -> String:
	## 找站位下方最上層的 ground TileMapLayer，回它 TileSet 對應的 surface_id。
	## Ground layer 須加進 "ground_layer" group，並用 z_index 表達疊放順序。
	## Tileset 名稱以 atlas source 的 texture PNG basename 為準(SubResource
	## 的 resource_path 是 <scene>::<SubResId> 形式不可用)。
	var best_layer: TileMapLayer = null
	for node in get_tree().get_nodes_in_group("ground_layer"):
		if node is TileMapLayer:
			if best_layer == null or node.z_index > best_layer.z_index:
				best_layer = node
	if best_layer == null or best_layer.tile_set == null:
		return ""
	var ts: TileSet = best_layer.tile_set
	if ts.get_source_count() == 0:
		return ""
	# Assumes single-source-per-zone (one tileset PNG per zone). Multi-source
	# tilesets (e.g. dirt+grass+sand on one TileMap) would need cell-based
	# lookup of which source the cell-under-player draws from — defer to
	# future zone where that pattern appears.
	var src: TileSetSource = ts.get_source(ts.get_source_id(0))
	if not (src is TileSetAtlasSource):
		return ""
	var tex: Texture2D = (src as TileSetAtlasSource).texture
	if tex == null or tex.resource_path == "":
		return ""
	var tileset_name: String = tex.resource_path.get_file().get_basename()
	return SurfaceRegistry.surface_for_tileset(tileset_name)

func _on_state_changed(new_state: GameManager.GameState) -> void:
	var can_move: bool = new_state == GameManager.GameState.EXPLORING
	set_physics_process(can_move)
	if not can_move:
		velocity = Vector2.ZERO
		is_moving = false
		_update_animation()

func _unhandled_input(event: InputEvent) -> void:
	if GameManager.current_state == GameManager.GameState.DIALOGUE:
		return
	if event.is_action_pressed("interact") and _nearby_interactable != null:
		interaction_requested.emit(_nearby_interactable)
		EventBus.player_interacted_with.emit(_nearby_interactable)
		# 直接呼叫 NPC 的 interact()
		if _nearby_interactable.has_method("interact"):
			_nearby_interactable.interact(self)
		get_viewport().set_input_as_handled()

# ── Interaction Area ──────────────────────────────────────────────────────────
func _on_body_entered(body: Node) -> void:
	# 優先選最近的可互動物件
	if body.has_method("interact"):
		_nearby_interactable = body

func _on_body_exited(body: Node) -> void:
	if _nearby_interactable == body:
		_nearby_interactable = null
