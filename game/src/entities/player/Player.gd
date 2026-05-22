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
	if _step_accum < FootstepPlayer.STEP_DISTANCE:
		return
	_step_accum = 0.0
	var surface_id: String = _surface_under_player()
	print("[Footstep] step → surface_id='%s'" % surface_id)
	FootstepPlayer.play(surface_id)

func _surface_under_player() -> String:
	## 找站位下方最上層的 ground TileMapLayer，回它 TileSet 對應的 surface_id。
	## Ground layer 須加進 "ground_layer" group，並用 z_index 表達疊放順序。
	var nodes: Array = get_tree().get_nodes_in_group("ground_layer")
	print("[Footstep]   ground_layer count=%d" % nodes.size())
	var best_layer: TileMapLayer = null
	for node in nodes:
		if node is TileMapLayer:
			if best_layer == null or node.z_index > best_layer.z_index:
				best_layer = node
	if best_layer == null:
		print("[Footstep]   no TileMapLayer node in group")
		return ""
	print("[Footstep]   picked layer=%s z=%d tile_set=%s" % [best_layer.name, best_layer.z_index, best_layer.tile_set])
	if best_layer.tile_set == null:
		print("[Footstep]   layer.tile_set is null")
		return ""
	var ts_path: String = best_layer.tile_set.resource_path
	print("[Footstep]   tile_set.resource_path='%s'" % ts_path)
	if ts_path == "":
		# Fallback: try first atlas source's texture path
		var ts: TileSet = best_layer.tile_set
		if ts.get_source_count() > 0:
			var src: TileSetSource = ts.get_source(ts.get_source_id(0))
			if src is TileSetAtlasSource:
				var tex: Texture2D = (src as TileSetAtlasSource).texture
				if tex != null:
					ts_path = tex.resource_path
					print("[Footstep]   fallback texture path='%s'" % ts_path)
		if ts_path == "":
			return ""
	var tileset_name: String = ts_path.get_file().get_basename()
	print("[Footstep]   tileset_name='%s'" % tileset_name)
	var result: String = SurfaceRegistry.surface_for_tileset(tileset_name)
	print("[Footstep]   registry → '%s'" % result)
	return result

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
