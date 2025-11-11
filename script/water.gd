extends MeshInstance3D

@export var wave_settings: WaveSettings
@export var water_level: float = 0.0
@onready var mat := get_surface_override_material(0)

# --- Données pré-calculées pour CPU et GPU ---
var amp_final: Array[float] = []
var wl_final: Array[float] = []
var sp_final: Array[float] = []
var dir_final: Array[Vector2] = []
var steep_final: Array[float] = []


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

	# Réinitialiser les tableaux avant recalcul
	amp_final.clear()
	wl_final.clear()
	sp_final.clear()
	dir_final.clear()
	steep_final.clear()

	for i in range(wave_settings.wave_count):
		var A   = wave_settings.amplitude[i]
		var lam = wave_settings.wavelength[i]
		var S   = wave_settings.speed[i]
		var d   = wave_settings.direction[i]
		var Q   = wave_settings.steepness[i]

		# Si c’est la première vague : on applique le modèle brownien
		if i == 0:
			var amp_mult  = 0.8
			var freq_mult = 1.2
			for o in range(20):
				amp_final.append(A)
				wl_final.append(lam)
				sp_final.append(S)
				dir_final.append(_rand_dir(o + 31)) # direction pseudo-aléatoire stable
				steep_final.append(Q * pow(0.55, o))

				A *= amp_mult
				lam /= freq_mult
		else:
			amp_final.append(A)
			wl_final.append(lam)
			sp_final.append(S)
			dir_final.append(d.normalized())
			steep_final.append(Q)

	# Limiter à ce que le shader accepte
	var max_waves = 30
	if amp_final.size() > max_waves:
		amp_final.resize(max_waves)
		wl_final.resize(max_waves)
		sp_final.resize(max_waves)
		dir_final.resize(max_waves)
		steep_final.resize(max_waves)

	# --- Envoi au shader ---
	shader.set_shader_parameter("waveCount", amp_final.size())
	shader.set_shader_parameter("amplitude", amp_final)
	shader.set_shader_parameter("wavelength", wl_final)
	shader.set_shader_parameter("speed", sp_final)
	shader.set_shader_parameter("direction", dir_final)
	shader.set_shader_parameter("steepness", steep_final)


func _rand_dir(seed: int) -> Vector2:
	var a = fmod(sin(float(seed) * 12.9898) * 43758.5453123, 1.0) * TAU
	return Vector2(cos(a), sin(a))


# ---- Fonctions de support ---------------------------------------------------

func get_height_and_normal(world_pos: Vector3) -> Dictionary:
	var result = get_precise_pose_on_wave_and_normal(world_pos, float(Time.get_ticks_msec()) / 1000.0)
	var pos = result["posOnWave"]
	var normal = result["normal"]
	return { "height": pos.y, "normal": normal }


func get_precise_pose_on_wave_and_normal(point: Vector3, time: float, max_iters := 4, alpha := 0.6, eps := 1e-4) -> Dictionary:
	var offset := Vector3.ZERO
	var pos_on_wave := Vector3.ZERO
	var normal := Vector3.ZERO
	
	for i in range(max_iters):
		var new_point := point - offset
		var result = get_point_position_and_normal(new_point, time)
		pos_on_wave = result["pos"]
		normal = result["normal"]
		var new_offset := get_wave_offset(new_point, pos_on_wave)

		offset += (new_offset - offset) * alpha

		if (new_offset - offset).length() < eps:
			break

	return { "posOnWave": pos_on_wave, "normal": normal }


func get_point_position_and_normal(point: Vector3, time: float) -> Dictionary:
	var pos := Vector3(point.x, 0.0, point.z)
	var origin_xz := Vector2(point.x, point.z)
	var dhdx: float = 0.0
	var dhdz: float = 0.0

	for i in range(amp_final.size()):
		var d := dir_final[i].normalized()
		var k := TAU / wl_final[i]
		var w := sqrt(9.8 * k)
		var phi := k * d.dot(origin_xz) - w * time * sp_final[i]

		var A := amp_final[i]
		var Q := steep_final[i]
		var c := cos(phi)
		var s := sin(phi)

		pos.x += Q * A * d.x * c
		pos.z += Q * A * d.y * c
		pos.y += A * s

		dhdx += A * k * d.x * c
		dhdz += A * k * d.y * c

	var normal = Vector3(-dhdx, 1.0, -dhdz).normalized()
	return { "pos": pos, "normal": normal }


func get_wave_offset(new_point: Vector3, pos_on_wave: Vector3) -> Vector3:
	return Vector3(
		pos_on_wave.x - new_point.x,
		0.0,
		pos_on_wave.z - new_point.z
	)


func _process(delta):
	var t = Time.get_ticks_msec() / 1000.0

	var players = get_tree().get_nodes_in_group("Player")
	if players.is_empty():
		return

	var player: Node3D = players[0]

	var follow_radius := 25.0
	var player_xz = Vector3(player.global_position.x, global_position.y, player.global_position.z)

	if global_position.distance_to(player_xz) > follow_radius:
		global_position.x = player.global_position.x
		global_position.z = player.global_position.z

	if mat and mat is ShaderMaterial:
		mat.set_shader_parameter("time", t)
		mat.set_shader_parameter("playerPosition", player.global_position)
		mat.set_shader_parameter("globalPosition", global_position)
