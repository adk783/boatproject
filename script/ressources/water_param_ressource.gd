extends Resource
class_name WaveSettings

@export var wave_count := 5

@export var amplitude: Array[float] = [0.8, 0.7, 0.7, 0.05, 0.02]
@export var wavelength: Array[float] = [22.0, 15.0, 15.0, 5.0, 2.0]
@export var speed: Array[float] = [0.5, 0.4, 0.8, 0.9, 0.0] # le dernier manquant → 0.0 pour garder 5 éléments
@export var direction: Array[Vector2] = [
	Vector2(1.0, 2.0),
	Vector2(0.8, -0.3),
	Vector2(-1.0, 0.8),
	Vector2(0.2, 1.0),
	Vector2(0.7, -1.0)
]
@export var steepness: Array[float] = [1.0, 0.8, 0.7, 0.9, 0.7]
