extends RigidBody3D

# --- Réglages ---
@export var water_path: NodePath
@export var floater_markers: Array[Node3D] = []

@export var k_buoyancy: float = 8000.0     # raideur (↑ = suit mieux la vague)
@export var c_damping: float = 140.0       # amorti vertical (↓ si trop “mou”)
@export var c_tangent: float = 80.0        # frottement horizontal (stabilité)
@export var surface_threshold: float = 0.0 # 0 = réagit dès qu’on touche l’eau
@export var max_force: float = 20000.0     # clamp par floater (sécurité)

@export var upright_torque: float = 10.0   # remet la bouée droite

@export var drag_linear: float = 0.25      # drag global léger
@export var drag_angular: float = 0.5

# --- Références ---
var water: Node = null

func _ready() -> void:
	water = get_node_or_null(water_path)
	if water == null:
		push_warning("Buoy: water_path non assigné (pas de flottabilité).")
	# pas d’intégrateur custom -> on garde simple
	# option: centre de masse un peu abaissé si besoin
	# center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	# center_of_mass = Vector3(0, -0.2, 0)

func _physics_process(delta: float) -> void:
	if water == null or floater_markers.is_empty():
		return

	var n_pts: int = max(1, floater_markers.size())
	var k_per: float = k_buoyancy / float(n_pts)

	for m in floater_markers:
		if m == null:
			continue

		var gp: Vector3 = m.global_transform.origin

		# --- hauteur + normale de l’eau (depuis ton water.gd) ---
		if not water.has_method("get_height_and_normal"):
			continue
		var info: Dictionary = water.get_height_and_normal(gp)
		var h: float = float(info.get("height", 0.0))
		var n: Vector3 = (info.get("normal", Vector3.UP) as Vector3).normalized()

		# --- profondeur du point sous la surface ---
		var depth: float = h - gp.y
		if depth <= surface_threshold:
			continue

		# --- vitesse locale du point (linéaire + rotation) ---
		var r: Vector3 = gp - global_transform.origin
		var v_point: Vector3 = linear_velocity + angular_velocity.cross(r)

		# composantes le long de n et tangentielle
		var v_n: float = v_point.dot(n)
		var v_tan: Vector3 = v_point - n * v_n

		# --- forces spring-damper + frottement tangent ---
		var F: Vector3 = (
			n * (k_per * depth)       # ressort (suit la vague)
			- n * (c_damping * v_n)   # amorti vertical
			- v_tan * c_tangent       # frottement horizontal
		)
		if max_force > 0.0 and F.length() > max_force:
			F = F.normalized() * max_force

		apply_force(F, r)

	# --- redressement doux (toujours vertical) ---
	var up: Vector3 = global_transform.basis.y
	var axis: Vector3 = up.cross(Vector3.UP)
	var dotv: float = clamp(up.dot(Vector3.UP), -1.0, 1.0)
	var angle: float = acos(dotv)
	if angle > 0.001:
		apply_torque(axis.normalized() * (upright_torque * angle))

	# --- drag global léger (stabilise sans tuer la réactivité) ---
	if drag_linear > 0.0:
		linear_velocity *= max(0.0, 1.0 - drag_linear * delta)
	if drag_angular > 0.0:
		angular_velocity *= max(0.0, 1.0 - drag_angular * delta)
