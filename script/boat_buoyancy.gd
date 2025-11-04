extends RigidBody3D

# === Buoyancy ===
@export var floater_markers: Array[Node3D] = []
@export var water_path: NodePath

@export var k_buoyancy: float = 5200.0       # spring strength (increase if it sinks)
@export var c_damping: float = 320.0         # damping to reduce bouncing
@export var max_force: float = 12000.0       # clamp buoyant force per floater
@export var disable_above_surface := true    # skip if not underwater
@export var surface_threshold: float = 0.02  # dead-zone near surface to avoid ghost forces (meters)
@export var c_tangent: float = 140.0          # tangent damping (horizontal)
@export var hull_drag: float = 2.0           # overall movement drag
@export var hull_angular_drag: float = 1.0   # overall rotational drag

# === Movement ===
@export var move_force: float = 4000.0       # forward/backward force
@export var turn_torque: float = 800.0       # steering torque

# === Stabilization ===
@export var angular_damp_strength: float = 4.0
@export var com_offset: Vector3 = Vector3(0, -0.25, 0)  # lower CoM for self-righting

# === Movement tuning ===
@export var max_speed: float = 6.0        # m/s ~ 21.6 km/h
@export var accel_rate: float = 2.5       # montée d'accélérateur (par s)
@export var decel_rate: float = 3.5       # relâchement (par s)
@export var steer_rate: float = 4.0       # vitesse de braquage du gouvernail (par s)

var throttle: float = 0.0                 # -1..+1 (arrière..avant)
var rudder: float = 0.0                   # -1..+1 (gauche..droite)
var _submersion_ratio: float = 1.0        # 0..1 (mis à jour par la flottabilité)

# === Water reference ===
@onready var water := get_node_or_null(water_path)

func _ready() -> void:
	if water == null:
		push_warning("⚠️ No water node assigned — buoyancy disabled.")
	else:
		print("✅ Boat buoyancy + movement system active")

	# Enable custom center of mass
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = com_offset

	# Stability
	angular_damp = angular_damp_strength



func _physics_process(delta: float) -> void:
	if water:
		_apply_wave_buoyancy()
	_handle_input(delta)
	_apply_drag()


# === Real buoyancy that follows wave height & normal ===
func _apply_wave_buoyancy() -> void:
	var total_force := Vector3.ZERO
	var underwater_points := 0
	var n_pts: int = max(1, floater_markers.size())
	var k_per: float = k_buoyancy / float(n_pts)

	for marker in floater_markers:
		if marker == null:
			continue
		var p: Vector3 = marker.global_transform.origin

		# --- Water data ---
		var info: Dictionary = water.get_height_and_normal(p)
		var h: float = info["height"]
		var n: Vector3 = (info["normal"] as Vector3).normalized()

		# --- Depth ---
		var depth: float = h - p.y
		# Dead-zone near surface avoids tiny "ghost" forces when barely out of water
		if disable_above_surface and depth <= surface_threshold:
			continue

		underwater_points += 1

		# --- Local velocity of the floater point ---
		var r: Vector3 = p - global_transform.origin
		var v_point: Vector3 = linear_velocity + angular_velocity.cross(r)
		var v_along_n: float = v_point.dot(n)
		var v_tan: Vector3 = v_point - n * v_along_n

		# --- Forces ---
		var F_spring: Vector3 = n * (k_per * max(depth, 0.0))
		var F_damping: Vector3 = -n * (c_damping * v_along_n)
		var F_tangent: Vector3 = -v_tan * c_tangent
		var F_total: Vector3 = (F_spring + F_damping + F_tangent).limit_length(max_force)

		apply_force(F_total, r)
		total_force += F_total
	
	_submersion_ratio = float(underwater_points) / float(n_pts)
	# === Global safety clamp (sum of all floaters) ===
	var max_total_force := max_force * floater_markers.size()
	if total_force.length() > max_total_force:
		# We already applied forces per floater; this clamp prevents runaway totals in edge cases
		total_force = total_force.normalized() * max_total_force

	# === If boat is fully airborne, apply light air drag ===
	if underwater_points == 0:
		_apply_air_drag()


# === Movement Controls (fixed) ===
func _handle_input(delta: float) -> void:
	var fwd := -transform.basis.z.normalized()
	# Avant du bateau = -Z
	# on retire toute composante verticale pour ne pas "sauter"
	var fwd_flat := (fwd - fwd.project(Vector3.UP)).normalized()
	if fwd_flat == Vector3.ZERO:
		return
	# --- Throttle lissé (-1..+1) ---
	var target_throttle := 0.0
	if Input.is_action_pressed("W") or Input.is_action_pressed("Z"): # ZQSD
		target_throttle = 1.0
	elif Input.is_action_pressed("S"):
		target_throttle = -0.6        # marche arrière plus faible
	var rate := accel_rate if abs(target_throttle) > abs(throttle) else decel_rate
	throttle = lerp(throttle, target_throttle, clamp(rate * delta, 0.0, 1.0))

	# --- Gouvernail lissé (-1..+1) ---
	var target_rudder := 0.0
	if Input.is_action_pressed("A") or Input.is_action_pressed("Q"):
		target_rudder = 1.0           # gauche (sens +Y)
	elif Input.is_action_pressed("D"):
		target_rudder = -1.0          # droite
	rudder = lerp(rudder, target_rudder, clamp(steer_rate * delta, 0.0, 1.0))
	# --- Limite de vitesse et modulation par immersion ---
	var speed := linear_velocity.length()
	var subm: float = clamp(_submersion_ratio, 0.0, 1.0)     # 0..1
	var thrust_scale: float = subm                            # pas de traction en l'air
	var speed_norm: float = clamp(speed / max_speed, 0.0, 1.0)
	var steer_scale: float = (0.35 + 0.65 * speed_norm) * subm

	# Cap de vitesse douce
	var speed_scale := 1.0
	if speed > max_speed:
		speed_scale = clamp(1.0 - (speed - max_speed) / max_speed, 0.0, 1.0)
	# --- Application des forces ---
	var thrust := move_force * throttle * thrust_scale * speed_scale
	apply_central_force(fwd_flat * thrust)

	# Couple de rotation (rudder) proportionnel à la vitesse utile
	if abs(rudder) > 0.001:
		apply_torque(Vector3.UP * (turn_torque * rudder * steer_scale))



# === Global drag (water resistance) ===
func _apply_drag() -> void:
	# Linear drag
	if linear_velocity.length() > 0.001:
		apply_central_force(-linear_velocity * hull_drag)

	# Angular drag
	if angular_velocity.length() > 0.001:
		apply_torque(-angular_velocity * hull_angular_drag)


# === Air drag when out of water (prevents endless spinning/drifting) ===
func _apply_air_drag() -> void:
	var air_drag_coeff := 0.3
	var air_angular_drag_coeff := 0.3
	apply_central_force(-linear_velocity * air_drag_coeff)
	apply_torque(-angular_velocity * air_angular_drag_coeff)
