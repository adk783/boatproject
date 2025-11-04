extends Camera3D

@export var follow_target: Node3D
@export var smoothness: float = 4.0

func _process(delta: float) -> void:
	if follow_target == null:
		return
	var target_transform := follow_target.global_transform
	var desired_pos := target_transform.origin + target_transform.basis.z * -6 + Vector3.UP * 3
	global_transform.origin = global_transform.origin.lerp(desired_pos, delta * smoothness)
	look_at(target_transform.origin + Vector3.UP)
