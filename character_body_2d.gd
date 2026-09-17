extends CharacterBody2D


const SPEED = 300.0
const JUMP_VELOCITY = -375.0

const MUSIC_VOLUME_DB = -10.0
const WIN_MUSIC_VOLUME_DB = -10.0
const SILENT_DB = -40.0
const CROSSFADE_TIME = 1.0

@onready var spawn_point: Vector2 = global_position
@onready var tilemap: TileMapLayer = get_parent().get_node("TileMapLayer")
@onready var music: AudioStreamPlayer = get_parent().get_node("Music")
@onready var win_music: AudioStreamPlayer = get_parent().get_node("WinMusic")

var dead := false
var key_taken := false
var won := false
var hidden_win_cells: Array[Dictionary] = []

func _ready() -> void:
	$HazardDetector.body_entered.connect(_on_hazard_entered)
	_hide_win_tiles()

func _hide_win_tiles() -> void:
	for cell in tilemap.get_used_cells():
		var data := tilemap.get_cell_tile_data(cell)
		if data and data.get_custom_data("role") == "win":
			hidden_win_cells.append({
				"cell": cell,
				"source": tilemap.get_cell_source_id(cell),
				"atlas": tilemap.get_cell_atlas_coords(cell),
				"alt": tilemap.get_cell_alternative_tile(cell),
			})
			tilemap.erase_cell(cell)

func _show_win_tiles() -> void:
	for d in hidden_win_cells:
		tilemap.set_cell(d["cell"], d["source"], d["atlas"], d["alt"])
	hidden_win_cells.clear()

func _on_hazard_entered(_body: Node2D) -> void:
	die()

func die() -> void:
	if dead or won:
		return
	dead = true
	respawn.call_deferred()

func respawn() -> void:
	velocity = Vector2.ZERO
	global_position = spawn_point
	$Camera2D.reset_smoothing()
	await get_tree().physics_frame
	dead = false

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity += get_gravity() * delta

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	var direction := Input.get_axis("left", "right")
	if direction:
		velocity.x = direction * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)

	move_and_slide()
	_check_tiles()

func _get_player_rect() -> Rect2:
	var cs: CollisionShape2D = $CollisionShape2D
	var half := Vector2(16, 16)

	var rect_shape := cs.shape as RectangleShape2D
	if rect_shape != null:
		half = rect_shape.size * 0.5
	else:
		var cap := cs.shape as CapsuleShape2D
		if cap != null:
			half = Vector2(cap.radius, cap.height * 0.5)
		else:
			var circ := cs.shape as CircleShape2D
			if circ != null:
				half = Vector2(circ.radius, circ.radius)

	half *= cs.global_scale.abs()
	return Rect2(cs.global_position - half, half * 2.0)

func _check_tiles() -> void:
	if won:
		return

	var rect := _get_player_rect()
	var top_left := tilemap.local_to_map(tilemap.to_local(rect.position))
	var bottom_right := tilemap.local_to_map(tilemap.to_local(rect.end))

	for x in range(top_left.x, bottom_right.x + 1):
		for y in range(top_left.y, bottom_right.y + 1):
			var cell := Vector2i(x, y)
			var data := tilemap.get_cell_tile_data(cell)
			if data == null:
				continue
			var role: String = data.get_custom_data("role")
			if role == "key" and not key_taken:
				key_taken = true
				tilemap.erase_cell(cell)
				_erase_role("door")
				return
			elif role == "flag":
				_win()
				return

func _erase_role(role: String) -> void:
	for cell in tilemap.get_used_cells():
		var data := tilemap.get_cell_tile_data(cell)
		if data and data.get_custom_data("role") == role:
			tilemap.erase_cell(cell)

func _crossfade_music() -> void:
	win_music.volume_db = SILENT_DB
	win_music.play()

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(music, "volume_db", SILENT_DB, CROSSFADE_TIME)
	tween.tween_property(win_music, "volume_db", WIN_MUSIC_VOLUME_DB, CROSSFADE_TIME)
	tween.chain().tween_callback(music.stop)

func _win() -> void:
	won = true
	_crossfade_music()
	_erase_role("flag")

	var sprite: Sprite2D = $Sprite2D
	var elapsed := 0.0
	while elapsed < 2.0:
		sprite.visible = not sprite.visible
		await get_tree().create_timer(0.1).timeout
		elapsed += 0.1
	sprite.visible = true

	_show_win_tiles()
