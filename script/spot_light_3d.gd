extends Node3D

@export var rotation_speed: float = 20.0 

func _process(delta: float) -> void:
	rotation_degrees.y += rotation_speed * delta
