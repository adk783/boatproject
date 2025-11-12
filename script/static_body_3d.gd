extends StaticBody3D

func _on_detector_body_entered(body: Node3D) -> void:
	if body.name == "PlayerFPS":
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
