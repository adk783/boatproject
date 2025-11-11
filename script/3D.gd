extends Node3D
var mode := "boat"

func _ready() -> void:
	$PlayerFPS.visible = false
	$PlayerFPS.set_physics_process(false)
	$PlayerFPS/FPSCamera.current = false
	$SpringArm3D/Camera3D.current = true

func _switch_to_fps() -> void:
	mode = "fps"
	# couper le bateau
	if $boat.has_node("BoatController"):
		$boat/BoatController.set_physics_process(false)
	$boat.linear_velocity = Vector3.ZERO
	$boat.angular_velocity = Vector3.ZERO
	$boat.freeze = true

	# placer le joueur sur le ponton du Lighthouse
	$PlayerFPS.global_transform = $lighthouse/SpawnPoint.global_transform
	$PlayerFPS.yaw   = $PlayerFPS.rotation_degrees.y
	$PlayerFPS.pitch = $PlayerFPS/FPSCamera.rotation_degrees.x
	
	$PlayerFPS.visible = true
	$PlayerFPS.set_physics_process(true)

	# switch caméras
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	$SpringArm3D/Camera3D.current = false
	$PlayerFPS/FPSCamera.current = true


func _on_dock_trigger_body_entered(body: Node3D) -> void:
	if mode != "boat":
		return
	if body.is_in_group("boat"):
		_switch_to_fps()
