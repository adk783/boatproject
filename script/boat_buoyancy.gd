extends RigidBody3D

# === Buoyancy / Eau ===
@export var floater_markers: Array[Node3D] = []
@export var water_path: NodePath

@export var k_buoyancy: float = 5200.0       # monte si le bateau s'enfonce trop
@export var c_damping: float = 320.0         # amortit les rebonds (le long de la normale)
@export var max_force: float = 12000.0       # clamp par floater (sécurité)
@export var disable_above_surface := true    # ignore si le point n'est pas sous l'eau
@export var surface_threshold: float = 0.02  # zone morte près de la surface (m)
@export var c_tangent: float = 140.0         # frottement tangent (horizontal)
@export var hull_angular_drag: float = 1.0   # amortissement angulaire global

# === Stabilisation / COM ===
@export var angular_damp_strength: float = 4.0
@export var com_offset: Vector3 = Vector3(0.0, -0.25, 0.0)  # COM abaissé pour auto-redressement

# === Option: pondération auto des floaters (plus de portance à l'arrière) ===
@export var auto_weight_enabled: bool = true
@export var front_weight: float = 0.6     # poids de flottabilité pour l'avant (Z le plus négatif)
@export var rear_weight: float  = 2.2     # poids pour l'arrière (Z le plus positif)

# === État ===
var _submersion_ratio: float = 1.0   # 0..1 (mis à jour)
var _z_min: float = 0.0
var _z_max: float = 1.0

# === Référence eau ===
@onready var water = get_node_or_null(water_path)


func _ready() -> void:
	if water == null:
		push_warning("⚠️ No water node assigned — buoyancy disabled.")
	else:
		print("✅ Boat buoyancy only (no user control) active")

	# COM custom
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = com_offset

	# Stabilisation générale
	angular_damp = angular_damp_strength

	# Pré-calcule l'étendue en Z des floaters (pour la pondération auto)
	_cache_floater_span()


func _physics_process(_delta: float) -> void:
	if water:
		_apply_wave_buoyancy()
	_apply_drag()


# === Helper: bornes Z locales des floaters (pour pondération avant/arrière) ===
func _cache_floater_span() -> void:
	if floater_markers.is_empty():
		_z_min = 0.0
		_z_max = 1.0
		return
	_z_min = 1e9
	_z_max = -1e9
	for m in floater_markers:
		if m == null:
			continue
		var z_local: float = to_local(m.global_transform.origin).z
		_z_min = min(_z_min, z_local)
		_z_max = max(_z_max, z_local)
	if absf(_z_max - _z_min) < 0.001:
		_z_max = _z_min + 0.001  # évite division ~0


# === Flottabilité suivant hauteur & normale des vagues ===
func _apply_wave_buoyancy() -> void:
	var total_force := Vector3.ZERO
	var underwater_points := 0
	var n_pts: int = max(1, floater_markers.size())

	# --- Répartition de k_buoyancy (optionnelle) ---
	var weights: Array[float] = []
	weights.resize(n_pts)
	var total_w: float = 0.0

	for i in range(n_pts):
		var marker := floater_markers[i]
		if marker == null:
			weights[i] = 0.0
			continue

		if auto_weight_enabled:
			var p := marker.global_transform.origin
			var z_local: float = to_local(p).z
			var t: float = clamp((z_local - _z_min) / (_z_max - _z_min), 0.0, 1.0)  # 0=avant, 1=arrière
			weights[i] = max(lerp(front_weight, rear_weight, t), 0.0)
		else:
			weights[i] = 1.0

		total_w += weights[i]

	if total_w <= 0.0:
		for i in range(n_pts):
			weights[i] = 1.0
		total_w = float(n_pts)

	# --- Application des forces pour chaque floater ---
	for i in range(n_pts):
		var marker := floater_markers[i]
		if marker == null:
			continue

		var p: Vector3 = marker.global_transform.origin

		# Données eau
		var info: Dictionary = water.get_height_and_normal(p)
		var h: float = info["height"]
		var n: Vector3 = (info["normal"] as Vector3).normalized()

		# Profondeur (>0 = sous la surface)
		var depth: float = h - p.y
		if disable_above_surface and depth <= surface_threshold:
			continue

		underwater_points += 1

		# Vitesse locale du point
		var r: Vector3 = p - global_transform.origin
		var v_point: Vector3 = linear_velocity + angular_velocity.cross(r)
		var v_along_n: float = v_point.dot(n)
		var v_tan: Vector3 = v_point - n * v_along_n

		# Part de k_buoyancy pour ce floater
		var k_i: float = k_buoyancy * (weights[i] / total_w)

		var F_spring: Vector3  = n * (k_i * max(depth, 0.0))
		var F_damping: Vector3 = -n * (c_damping * v_along_n)
		var F_tangent: Vector3 = -v_tan * c_tangent

		var F_total: Vector3 = (F_spring + F_damping + F_tangent).limit_length(max_force)

		apply_force(F_total, r)
		total_force += F_total

	_submersion_ratio = float(underwater_points) / float(n_pts)

	# Clamp global (sécurité)
	var max_total_force := max_force * n_pts
	if total_force.length() > max_total_force:
		total_force = total_force.normalized() * max_total_force

	# Drag d'air si totalement hors de l'eau
	if underwater_points == 0:
		_apply_air_drag()


# === Drag hydrodynamique directionnel (quadratique) + amortissement angulaire ===
func _apply_drag() -> void:
	if linear_velocity == Vector3.ZERO and angular_velocity == Vector3.ZERO:
		return

	var fwd   := -transform.basis.z.normalized()
	var right :=  transform.basis.x.normalized()
	var up    :=  Vector3.UP

	var v := linear_velocity
	var v_fwd  := v.dot(fwd)
	var v_side := v.dot(right)
	var v_upv  := v.dot(up)

	# Coeffs directionnels (peu longitudinal, fort latéral, moyen vertical)
	var Cf := 0.35
	var Cs := 2.20
	var Cu := 1.60

	# F = -C * v * |v|
	var F_drag := (
		-(Cf * v_fwd  * absf(v_fwd))  * fwd
		- (Cs * v_side * absf(v_side)) * right
		- (Cu * v_upv  * absf(v_upv))  * up
	)
	apply_central_force(F_drag)

	# Damping angulaire global
	var ang := angular_velocity
	if ang.length() > 0.001:
		apply_torque(-ang * hull_angular_drag)


# === Drag d'air quand le bateau est hors de l'eau ===
func _apply_air_drag() -> void:
	var air_drag_coeff := 0.30
	var air_angular_drag_coeff := 0.30
	apply_central_force(-linear_velocity * air_drag_coeff)
	apply_torque(-angular_velocity * air_angular_drag_coeff)
