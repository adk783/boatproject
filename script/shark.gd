extends Node3D

@export var speed: float = 8.0        # vitesse de poursuite
@export var chase_duration: float = 7.0  # durée de la chasse (secondes)
@export var idle_speed: float = 2.0   # vitesse lente quand il n’a rien détecté
@export var turn_interval: float = 3.0 #temps moyen entre deux changements de direction
@export var wander_angle_range: float = 45.0 #amplitude virage  aleatoire

var target: Node3D = null
var is_chasing: bool = false
var timer: float = 0.0
var turn_timer: float = 0.0

func _ready() -> void:
	var anim_player = $Sketchfab_Scene/AnimationPlayer
	if anim_player.has_animation("Take 001"):  # adapte le nom si besoin
		anim_player.play("Take 001")



func _physics_process(delta: float) -> void:
	if is_chasing and target:
		# direction vers le bateau
		var dir = (target.global_transform.origin - global_transform.origin).normalized()
		# avance dans cette direction
		global_translate(dir * speed * delta)
		# oriente le requin vers le bateau
		look_at(target.global_transform.origin, Vector3.UP)

		# compte le temps écoulé
		timer -= delta
		if timer <= 0.0:
			stop_chase()
	else:
	# --- errance aléatoire mais toujours "nez en avant" ---
		turn_timer -= delta
		if turn_timer <= 0.0:
			var random_angle = randf_range(-wander_angle_range, wander_angle_range)
			rotate_y(deg_to_rad(random_angle))
			turn_timer = turn_interval + randf_range(-1.0, 1.0)
	# garde requin horizontal 
	rotation.x = 0.0
	rotation.z = 0.0

	# avance selon l'orientation du nez
	translate_object_local(Vector3(0, 0, -idle_speed * delta))

func _on_detect_area_body_entered(body: Node3D) -> void:
	if body.name == "boat":  # adapte le nom exact de ton nœud bateau
		start_chase(body)

func start_chase(boat: Node3D) -> void:
	if is_chasing:
		return  # déjà en chasse
	target = boat
	is_chasing = true
	timer = chase_duration

func stop_chase() -> void:
	is_chasing = false
	target = null

func _on_catch_area_body_entered(body: Node3D) -> void:
	pass
