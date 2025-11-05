extends Node
@onready var boat: RigidBody3D = get_parent() as RigidBody3D

func _physics_process(_delta: float) -> void:
	if boat == null:
		return

	var throttle := 0.0
	if Input.is_action_pressed("W") or Input.is_action_pressed("Z"):
		throttle = 1.0
	elif Input.is_action_pressed("S"):
		throttle = -1.0

	var rudder := 0.0
	if Input.is_action_pressed("A") or Input.is_action_pressed("Q"):
		rudder = 1.0
	elif Input.is_action_pressed("D"):
		rudder = -1.0

	if "set_input" in boat:
		boat.set_input(throttle, rudder)
