extends MeshInstance3D

@export var wave_settings: WaveSettings
@export var water_level: float = 0.0
@onready var mat := get_surface_override_material(0)

func _ready():
	if mat == null:
		mat = get_active_material(0)
	
	if mat and mat is ShaderMaterial:
		update_shader_from_settings(mat)
	else:
		push_error("Aucun ShaderMaterial trouvé sur la surface 0 de " + str(self))


func update_shader_from_settings(shader: ShaderMaterial) -> void:
	if not wave_settings:
		push_warning("wave_settings n'est pas assigné.")
		return
	
	# Envoi des paramètres de la ressource vers le shader
	shader.set_shader_parameter("waveCount", wave_settings.wave_count)
	shader.set_shader_parameter("amplitude", wave_settings.amplitude)
	shader.set_shader_parameter("wavelength", wave_settings.wavelength)
	shader.set_shader_parameter("speed", wave_settings.speed)
	shader.set_shader_parameter("direction", wave_settings.direction)
	shader.set_shader_parameter("steepness", wave_settings.steepness)


func get_height_and_normal(world_pos: Vector3) -> Dictionary:
	var result = get_precise_pose_on_wave_and_normal(world_pos,float(Time.get_ticks_msec()) / 1000.0)
	var pos = result["posOnWave"]
	var normal = result["normal"]
	return { "height": pos.y , "normal": normal }
	

func get_precise_pose_on_wave_and_normal(point: Vector3, time: float, max_iters := 4, alpha := 0.6, eps := 1e-4) -> Dictionary:
	var offset := Vector3.ZERO
	var pos_on_wave := Vector3.ZERO
	var normal := Vector3.ZERO
	
	for i in range(max_iters):
		var new_point := point - offset                # estimation courante (x,z plats)
		var result = get_point_position_and_normal(new_point, time)
		pos_on_wave = result["pos"]
		normal = result["normal"]
		var new_offset := get_wave_offset(new_point, pos_on_wave)  # <-- fonction dédiée

		# relaxation pour éviter l’overshoot
		offset += (new_offset - offset) * alpha

		# critère d'arrêt robuste
		if (new_offset - offset).length() < eps:
			break
	return { "posOnWave": pos_on_wave, "normal": normal }


# ---- Fonctions de support ---------------------------------------------------

# Position (Gerstner somme) pour un point (x,z) "plat"
func get_point_position_and_normal(point: Vector3, time: float) -> Dictionary:
	var pos := Vector3(point.x, 0.0, point.z)
	var origin_xz := Vector2(point.x, point.z)
	var dhdx: float = 0.0
	var dhdz: float = 0.0

	for i in range(wave_settings.wave_count):
		var d := wave_settings.direction[i].normalized()
		var k := TAU / wave_settings.wavelength[i]
		var w := sqrt(9.8 * k)
		var phi := k * d.dot(origin_xz) - w * time * wave_settings.speed[i]

		var A := wave_settings.amplitude[i]
		var Q := wave_settings.steepness[i]
		var c := cos(phi)
		var s := sin(phi)

		pos.x += Q * A * d.x * c
		pos.z += Q * A * d.y * c
		pos.y += A * s
		
		dhdx += A * k * d.x * c
		dhdz += A * k * d.y * c
	
	var normal = Vector3(-dhdx, 1.0, -dhdz).normalized()
	return { "pos": pos, "normal": normal }


# ⚠️ Fonction DÉDIÉE : offset horizontal entre l’estimation (new_point) et la position déplacée (pos_on_wave)
func get_wave_offset(new_point: Vector3, pos_on_wave: Vector3) -> Vector3:
	return Vector3(
		pos_on_wave.x - new_point.x,
		0.0,
		pos_on_wave.z - new_point.z
	)


func _process(delta):
	var t = Time.get_ticks_msec() / 1000.0

	var players = get_tree().get_nodes_in_group("Player")
	if players.size() == 0:
		return

	var player :Node3D= players[0]

	# ======================
	# suivi du joueur
	# ======================
	var follow_radius := 25.0
	var player_xz = Vector3(player.global_position.x, global_position.y, player.global_position.z)

	if global_position.distance_to(player_xz) > follow_radius:
		# on recolle le plane au joueur uniquement sur XZ
		global_position.x = player.global_position.x
		global_position.z = player.global_position.z

	# ======================
	# update shader
	# ======================
	if mat and mat is ShaderMaterial:
		mat.set_shader_parameter("time", t)
		mat.set_shader_parameter("playerPosition", player.global_position)
		mat.set_shader_parameter("globalPosition", global_position)
