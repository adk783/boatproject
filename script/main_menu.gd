extends Control


func _on_buttonplay_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main.tscn")


func _on_buttonquit_pressed() -> void:
	get_tree().quit()
