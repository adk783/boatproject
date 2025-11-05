extends RigidBody3D

# === Buoyancy ===
@export var floater_markers: Array[Node3D] = []
@export var water_path: NodePath

@export var k_buoyancy: float = 5200.0       # spring strength (monte si ça coule trop)
@export var c_damping: float = 320.0         # amortit les rebonds
@export var max_force: float = 12000.0       # clamp par floater
@export var disable_above_surface := true    # ignore s'il n'est pas sous l'eau
@export var surface_threshold: float = 0.02  # zone morte près de la surface (m)
@export var c_tangent: float = 140.0         # frottement tangent (horizontal)
@export var hull_angular_drag: float = 1.0   # amortissement angulaire global

# === Stabilisation / COM ===
@export var angular_damp_strength: float = 4.0
@export var com_offset: Vector3 = Vector3(0.0, -0.25, 0.0)  # COM abaissé pour auto-redressement

# === Etat ===
var _submersion_ratio: float = 1.0   # 0..1 (mis à jour par la flottabilité)

# === Référence eau ===
@onready var water = get_node_or_null(water_path)

# === Moteur basique : thrust + rotation ===
@export var move_force: float = 4000.0
@export var turn_torque: float = 800.0
@export var prop_local_offset: Vector3 = Vector3(0.0, -0.28, 0.85)  # Y bas, Z vers la poupe (+Z)

func _ready() -> void:
	if water == null:
		push_warning("⚠️ No water node assigned — buoyancy disabled.")
	else:
		print("✅ Boat buoyancy (no user control) active")

	# COM custom
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = com_offset

	# Stabilisation générale
	angular_damp = angular_damp_strength


func _physics_process(delta: float) -> void:
	if water:
		_apply_wave_buoyancy()
		_apply_drag()
	_apply_basic_engine(delta)
	
func _apply_basic_engine(_delta: float) -> void:
	if not accept_control:
		return

	# Avant du bateau (à plat)
	var fwd := -transform.basis.z.normalized()
	fwd = (fwd - fwd.project(Vector3.UP)).normalized()
	if fwd == Vector3.ZERO:
		return

	# Immersion utile
	var subm: float = clamp(_submersion_ratio, 0.0, 1.0)
	if subm < 0.05:
		return

	# --- PROPULSION au point hélice (génère un couple "nez vers le haut") ---
	if abs(ctrl_throttle) > 0.001:
		var prop_world := global_transform.origin + transform.basis * prop_local_offset
		var r := prop_world - global_transform.origin
		var F := fwd * move_force * ctrl_throttle
		apply_force(F, r)

	# --- BRAQUAGE simple ---
	if abs(ctrl_rudder) > 0.001:
		apply_torque(Vector3.UP * turn_torque * ctrl_rudder)

	# --- DAMPING de tangage (anti-porpoising / anti-plongeon) ---
	var ang_local := transform.basis.inverse() * angular_velocity
	var pitch_rate := ang_local.x                               # +X = tangage
	var kd_pitch := 2.8                                         # augmente si ça pompe encore
	var torque_pitch_local := Vector3(-kd_pitch * pitch_rate, 0.0, 0.0)
	apply_torque(transform.basis * torque_pitch_local)


# === Flottabilité suivant hauteur & normale des vagues ===
func _apply_wave_buoyancy() -> void:
	var total_force := Vector3.ZERO
	var underwater_points := 0
	var n_pts: int = max(1, floater_markers.size())
	var k_per: float = k_buoyancy / float(n_pts)

	for marker in floater_markers:
		if marker == null:
			continue
		var p: Vector3 = marker.global_transform.origin

		# Données eau depuis ton node "water"
		var info: Dictionary = water.get_height_and_normal(p)
		var h: float = info["height"]
		var n: Vector3 = (info["normal"] as Vector3).normalized()

		# Profondeur: >0 = sous la surface
		var depth: float = h - p.y
		if disable_above_surface and depth <= surface_threshold:
			continue

		underwater_points += 1

		# Vitesse locale du point
		var r: Vector3 = p - global_transform.origin
		var v_point: Vector3 = linear_velocity + angular_velocity.cross(r)
		var v_along_n: float = v_point.dot(n)
		var v_tan: Vector3 = v_point - n * v_along_n

		# Forces
		var F_spring: Vector3 = n * (k_per * max(depth, 0.0))
		var F_damping: Vector3 = -n * (c_damping * v_along_n)
		var F_tangent: Vector3 = -v_tan * c_tangent
		var F_total: Vector3 = (F_spring + F_damping + F_tangent).limit_length(max_force)

		apply_force(F_total, r)
		total_force += F_total

	_submersion_ratio = float(underwater_points) / float(n_pts)

	# Clamp global de sécurité (somme des floaters)
	var max_total_force := max_force * floater_markers.size()
	if total_force.length() > max_total_force:
		total_force = total_force.normalized() * max_total_force

	# Si totalement en l'air, applique un léger drag d'air
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

	# Coeffs: peu de drag longitudinal (laisser glisser), fort latéral, moyen vertical
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

# === API de contrôle (inputs externes) ===
@export var accept_control: bool = true
var ctrl_throttle: float = 0.0    # -1..+1
var ctrl_rudder: float = 0.0      # -1..+1

func set_input(throttle: float, rudder: float) -> void:
	if not accept_control:
		return
	ctrl_throttle = clamp(throttle, -1.0, 1.0)
	ctrl_rudder   = clamp(rudder,   -1.0, 1.0)
