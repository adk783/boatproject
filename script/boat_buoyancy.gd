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

# === État ===
var _submersion_ratio: float = 1.0   # 0..1 (mis à jour)

# === Référence eau ===
@onready var water = get_node_or_null(water_path)

# === Propulsion & Steering ===
@export var prop_marker_path: NodePath       # Marker3D placé à l'arrière (point d'hélice)
@onready var prop_marker: Node3D = get_node_or_null(prop_marker_path)
@export var prop_front_marker_path: NodePath   # 2e propulseur avant
@onready var prop_front_marker: Node3D = get_node_or_null(prop_front_marker_path)

# Poussée hélice
@export var thrust_max: float = 14000.0      # N : poussée maximale
@export var reverse_factor: float = 0.1      # 0..1 : puissance en marche arrière

# Gouvernail 
@export var turn_gain: float = 3200.0        # N·m : intensité de rotation (yaw)
@export var speed_turn_factor: float = 0.6   # plein effet dès ~60% de Vmax

# Limites de sécurité
@export var force_limit: float = 16000.0     # N : clamp de poussée
@export var torque_limit: float = 4000.0     # N·m : clamp de couple

# Entrées (seront pilotées par l'input plus tard)
var throttle: float = 0.0    # [-1..+1]  +1 avant, -1 arrière
var steer: float = 0.0       # [-1..+1]  gauche/droite

# === Observables de mouvement (lecture seule) ===
var _fwd: Vector3 = Vector3.ZERO        # avant global (-Z)
var _fwd_flat: Vector3 = Vector3.ZERO   # avant projeté sur l'horizontale
var _v_forward: float = 0.0             # vitesse le long de _fwd_flat (m/s)
var _w_yaw: float = 0.0                 # vitesse angulaire autour de Y (rad/s)



func _ready() -> void:
	if water == null:
		push_warning("No water node assigned — buoyancy disabled.")
	else:
		print("Boat buoyancy only (no movement)")

	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = com_offset
	angular_damp = angular_damp_strength
	# Vérif du propulseur (Marker3D)
	if prop_marker == null:
		push_warning("No propeller marker assigned — set 'prop_marker_path' to a rear Marker3D.")


func _physics_process(_delta: float) -> void:
	if water:
		_apply_wave_buoyancy()
	_update_controls(_delta)
	_measure_movement_observables()
	_apply_propulsion()
	_apply_steering()
	_apply_drag()


# --- Flottabilité (répartition uniforme entre floaters) ---
func _apply_wave_buoyancy() -> void:
	var total_force := Vector3.ZERO
	var underwater_points := 0
	var n_pts: int = max(1, floater_markers.size())
	var k_per: float = k_buoyancy / float(n_pts)

	for marker in floater_markers:
		if marker == null:
			continue

		var p: Vector3 = marker.global_transform.origin

		# Données eau
		var info: Dictionary = water.get_height_and_normal(p)
		var h: float = info["height"]
		var n: Vector3 = (info["normal"] as Vector3).normalized()

		# Profondeur
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
		var F_spring: Vector3  = n * (k_per * max(depth, 0.0))
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

	# Drag d’air si totalement hors de l’eau
	if underwater_points == 0:
		_apply_air_drag()


# --- Drag eau + amortissement angulaire ---
func _apply_drag() -> void:
	if linear_velocity == Vector3.ZERO and angular_velocity == Vector3.ZERO:
		return

	var fwd := -transform.basis.z.normalized()
	var right := transform.basis.x.normalized()
	var up := Vector3.UP

	var v := linear_velocity
	var v_fwd := v.dot(fwd)
	var v_side := v.dot(right)
	var v_upv := v.dot(up)

	# Coeffs directionnels
	var Cf := 0.18
	var Cs := 1.50
	var Cu := 0.9

	var F_drag := (
		-(Cf * v_fwd  * absf(v_fwd))  * fwd
		- (Cs * v_side * absf(v_side)) * right
		- (Cu * v_upv  * absf(v_upv))  * up
	)
	apply_central_force(F_drag)

	var ang := angular_velocity
	if ang.length() > 0.001:
		apply_torque(-ang * hull_angular_drag)


# --- Drag d’air hors de l’eau ---
func _apply_air_drag() -> void:
	var air_drag_coeff := 0.30
	var air_angular_drag_coeff := 0.30
	apply_central_force(-linear_velocity * air_drag_coeff)
	apply_torque(-angular_velocity * air_angular_drag_coeff)
	
func _measure_movement_observables() -> void:
	# Avant global du bateau 
	_fwd = (-transform.basis.z).normalized()

	# On retire la composante verticale pour éviter de "sauter" avec les vagues
	_fwd_flat = (_fwd - _fwd.project(Vector3.UP)).normalized()
	if _fwd_flat == Vector3.ZERO:
		# fallback de sécurité si la projection s'annule
		_fwd_flat = _fwd

	# Vitesse projetée sur l'avant (scalaire)
	_v_forward = linear_velocity.dot(_fwd_flat)

	# Taux de rotation en lacet (yaw)
	_w_yaw = angular_velocity.y
	
# === Étape 3 : Propulsion (hélice) ===
func _apply_propulsion() -> void:
	if throttle == 0.0:
		return

	
	# Poussée avant/arrière (marche arrière limitée)
	var t = throttle
	if t < 0.0:
		t *= reverse_factor

	var thrust = thrust_max * t


	# Option : réduire la poussée si quasi hors de l’eau (évite l’effet "fusée")
	var subm = clamp(_submersion_ratio * 1.2, 0.0, 1.0)
	thrust *= subm

	# Clamp sécurité
	if absf(thrust) > force_limit:
		thrust = sign(thrust) * force_limit

	# Direction d’avance à plat
	var fwd_flat = _fwd_flat
	if fwd_flat == Vector3.ZERO:
		fwd_flat = (-transform.basis.z).normalized()

	# --- Répartition sur les deux propulseurs (50/50 si les deux existent) ---
	var thrust_rear: float = 0.0
	var thrust_front: float = 0.0

	if prop_marker != null and prop_front_marker != null:
		thrust_rear = thrust * 0.9
		thrust_front = thrust * 0.1  
	elif prop_marker != null:
		thrust_rear = thrust
	elif prop_front_marker != null:
		thrust_front = thrust
	else:
		# Aucun marker -> fallback centre
		apply_central_force(fwd_flat * thrust)
		return

	# Appliquer la poussée à l'arrière
	if thrust_rear != 0.0:
		var r_rear = prop_marker.global_transform.origin - global_transform.origin
		apply_force(fwd_flat * thrust_rear, r_rear)

	# Appliquer la poussée à l'avant
	if thrust_front != 0.0:
		var r_front = prop_front_marker.global_transform.origin - global_transform.origin
		apply_force(fwd_flat * thrust_front, r_front)



# === Étape 3 : Gouvernail (efficacité dépendante de la vitesse) ===
func _apply_steering() -> void:
	if steer == 0.0:
		return

	# Efficacité qui augmente avec la vitesse avant (évite le "spin" à l’arrêt)
	#  -> 0.2 à l’arrêt, → 1.0 vers ~8 m/s (ajuste 8.0 si besoin)
	var TURN_FULL_SPEED := 8.0
	var speed_factor = clamp(absf(_v_forward) / TURN_FULL_SPEED, 0.2, 1.0)

	# Marche arrière : gouvernail un peu moins efficace
	if throttle < 0.0:
		speed_factor *= 0.8

	var torque = turn_gain * steer * speed_factor

	# Clamp sécurité
	if absf(torque) > torque_limit:
		torque = sign(torque) * torque_limit


	apply_torque(Vector3.UP * torque)
	
# === Input (touches -> throttle/steer) ===
@export var input_smooth: float = 8.0   # lissage (plus grand = plus réactif)

func _update_controls(delta: float) -> void:
	var t_target := 0.0
	if Input.is_action_pressed("throttle_forward"):
		t_target = 1.0
	elif Input.is_action_pressed("throttle_reverse"):
		t_target = -1.0

	var s_target := 0.0
	if Input.is_action_pressed("steer_left"):
		s_target -= 1.0
	if Input.is_action_pressed("steer_right"):
		s_target += 1.0

	# Lissage (évite les pics quand on presse/relâche)
	throttle = lerp(throttle, t_target, clamp(input_smooth * delta, 0.0, 1.0))
	steer    = lerp(steer,    s_target, clamp(input_smooth * delta, 0.0, 1.0))
