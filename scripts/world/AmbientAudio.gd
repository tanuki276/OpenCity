extends AudioStreamPlayer
## Continuous urban afternoon ambience bed (wind + distant city traffic) — enforces Quality Standard §6 (no silence).


func _ready() -> void:
	var wav := load("res://assets/audio/ambient_city_afternoon.wav") as AudioStreamWAV
	if wav != null:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = int(wav.get_length() * float(wav.mix_rate))
		stream = wav
		volume_db = -12.0
		play()
