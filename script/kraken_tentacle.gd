extends Node3D

@export var surface_y: float = 0.0    # niveau de la mer
@export var depth_y: float = -8.0     # profondeur de repos (en dessous de 0)
@export var rise_time: float = 1.2    # durée de montée
@export var hold_time: float = 5.0    # temps resté à la surface
@export var fall_time: float = 1.0    # durée de descente
@export var interval: float = 10.0    # toutes les ~10 s un cycle démarre

@export var start_delay: float = 0.0  # décalage optionnel pour désynchroniser plusieurs tentacules

@onready var area: Area3D = $Area3D

func _ready() -> void:
	# Position initiale sous l'eau
	position.y = depth_y
	# Collision TOUJOURS active
	if area:
		area.monitorable = true
		area.monitoring = true
	# Lancement de la boucle
	_start_loop()

func _start_loop() -> void:
	if start_delay > 0.0:
		await get_tree().create_timer(start_delay).timeout
	await _cycle_loop()

func _cycle_gap() -> float:
	var used := rise_time + hold_time + fall_time
	return max(0.0, interval - used)

func _tween_y(target_y: float, dur: float, ease_out: bool) -> void:
	var tw := create_tween()
	tw.tween_property(self, "position:y", target_y, dur)\
		.set_trans(Tween.TRANS_SINE)\
		.set_ease(Tween.EASE_OUT if ease_out else Tween.EASE_IN)
	await tw.finished

func _do_rise_hold_fall() -> void:
	# Montée
	await _tween_y(surface_y, rise_time, true)
	# Maintien en surface
	await get_tree().create_timer(hold_time).timeout
	# Descente
	await _tween_y(depth_y, fall_time, false)

func _cycle_loop() -> void:
	while true:
		await _do_rise_hold_fall()
		var gap := _cycle_gap()
		if gap > 0.0:
			await get_tree().create_timer(gap).timeout
