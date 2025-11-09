extends SpringArm3D

@export var follow_target: Node3D
@export var mouse_sensibility: float = 0.005
@export var smoothness: float = 10.0

@export_range(-90.0, 0.0, 0.1, "radians_as_degrees") var min_vertical_angle: float = -PI / 2
@export_range(-90.0, 90.0, 0.1, "radians_as_degrees") var max_vertical_angle: float = PI / 4

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		rotation.y -= event.relative.x * mouse_sensibility
		rotation.y = wrapf(rotation.y, 0.0, TAU)

		rotation.x -= event.relative.y * mouse_sensibility
		rotation.x = clamp(rotation.x, min_vertical_angle, max_vertical_angle)

func _process(delta: float) -> void:
	if follow_target:
		global_position = global_position.lerp(follow_target.global_position, delta * smoothness)
