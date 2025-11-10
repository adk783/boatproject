extends CharacterBody3D

@export var move_speed: float = 5.0
@export var sprint_mult: float = 1.7
@export var jump_velocity: float = 4.5
@export var mouse_sens: float = 0.12   # degrés par pixel
@export var max_look_up: float = 89.0

var yaw := 0.0   # rotation horizontale (corps)
var pitch := 0.0 # rotation verticale (caméra)
var gravity := ProjectSettings.get_setting("physics/3d/default_gravity") as float

func _ready() -> void:
	# Au départ on peut laisser la souris libre; ton Main gèrera l'activation.
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and $FPSCamera.current:
		yaw -= event.relative.x * mouse_sens * 0.01 * 57.2958 # rad->deg factor
		pitch -= event.relative.y * mouse_sens * 0.01 * 57.2958
		pitch = clamp(pitch, -max_look_up, max_look_up)
		rotation_degrees.y = yaw
		$FPSCamera.rotation_degrees.x = pitch

func _physics_process(delta: float) -> void:
	var speed := move_speed * (sprint_mult if Input.is_action_pressed("sprint") else 1.0)

	# Directions locales
	var input_dir := Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_back")  - Input.get_action_strength("move_forward")
	).normalized()

	var forward := -transform.basis.z
	var right := transform.basis.x
	var desired_vel := (right * input_dir.x + forward * input_dir.y) * speed

	# Gravité + saut
	if not is_on_floor():
		velocity.y -= gravity * delta
	elif Input.is_action_just_pressed("jump"):
		velocity.y = jump_velocity
	else:
		# colle bien au sol quand rien ne se passe
		velocity.y = 0.0

	# Applique la vitesse horizontale
	velocity.x = desired_vel.x
	velocity.z = desired_vel.z

	move_and_slide()
