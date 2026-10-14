## Every sound is synthesized at startup (no sound files): one-shot effects are rendered into
## AudioStreamWAV samples, engines are seamless loops played back at a pitch that follows the rpm.
## Machine sounds go through the "Machines" bus, which the ear muffs low-pass and turn down.
extends Node

const RATE := 22050
var sounds := {}
var pool: Array[AudioStreamPlayer] = []
var muffs := false
var _machines_bus := -1
var _lp: AudioEffectLowPassFilter

func _ready() -> void:
	_machines_bus = AudioServer.bus_count
	AudioServer.add_bus()
	AudioServer.set_bus_name(_machines_bus, "Machines")
	AudioServer.set_bus_send(_machines_bus, "Master")
	_lp = AudioEffectLowPassFilter.new(); _lp.cutoff_hz = 20000
	AudioServer.add_bus_effect(_machines_bus, _lp)
	for i in range(12):
		var p := AudioStreamPlayer.new(); add_child(p); pool.append(p)
	_build()

func set_muffs(on: bool) -> void:
	muffs = on
	_lp.cutoff_hz = 650.0 if on else 20000.0
	AudioServer.set_bus_volume_db(_machines_bus, linear_to_db(0.38) if on else 0.0)
	AudioServer.set_bus_volume_db(0, linear_to_db(0.7) if on else 0.0)

func play(name: String, vol := 1.0, pitch := 1.0) -> void:
	if not sounds.has(name): return
	for p in pool:
		if not p.playing:
			p.stream = sounds[name]; p.volume_db = linear_to_db(maxf(vol, 0.001)); p.pitch_scale = pitch; p.bus = "Master"; p.play()
			return

# ------------------------------------------------------------ synthesis helpers
class Biquad:
	var b0 := 1.0; var b1 := 0.0; var b2 := 0.0; var a1 := 0.0; var a2 := 0.0
	var x1 := 0.0; var x2 := 0.0; var y1 := 0.0; var y2 := 0.0
	func _init(type: String, f: float, q: float, rate: float) -> void:
		var w := TAU * f / rate; var al := sin(w) / (2 * q); var c := cos(w)
		var a0 := 1.0
		match type:
			"lowpass":
				b0 = (1 - c) / 2; b1 = 1 - c; b2 = (1 - c) / 2; a0 = 1 + al; a1 = -2 * c; a2 = 1 - al
			"highpass":
				b0 = (1 + c) / 2; b1 = -(1 + c); b2 = (1 + c) / 2; a0 = 1 + al; a1 = -2 * c; a2 = 1 - al
			_:
				b0 = al; b1 = 0; b2 = -al; a0 = 1 + al; a1 = -2 * c; a2 = 1 - al
		b0 /= a0; b1 /= a0; b2 /= a0; a1 /= a0; a2 /= a0
	func run(x: float) -> float:
		var y := b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
		x2 = x1; x1 = x; y2 = y1; y1 = y
		return y

func _buf(dur: float) -> PackedFloat32Array:
	var b := PackedFloat32Array(); b.resize(int(dur * RATE)); return b

func _noise(b: PackedFloat32Array, dur: float, freq: float, q: float, vol: float, type := "bandpass", delay := 0.0) -> void:
	var f := Biquad.new(type, freq, q, RATE)
	var n0 := int(delay * RATE); var n := int(dur * RATE)
	for i in range(n):
		var t := float(i) / RATE
		var env := clampf(t / 0.01, 0, 1) * exp(-t / dur * 6.9)
		var k := n0 + i
		if k < b.size(): b[k] += f.run(randf() * 2 - 1) * vol * env * 2.5

func _tone(b: PackedFloat32Array, dur: float, f0: float, f1: float, vol: float, wave := "sine", delay := 0.0) -> void:
	var n0 := int(delay * RATE); var n := int(dur * RATE); var ph := 0.0
	for i in range(n):
		var t := float(i) / RATE
		var f := f0 * pow(maxf(f1, 1) / f0, t / dur)
		ph += f / RATE
		var x := 0.0
		match wave:
			"sine": x = sin(ph * TAU)
			"square": x = 1.0 if fmod(ph, 1.0) < 0.5 else -1.0
			"sawtooth": x = fmod(ph, 1.0) * 2 - 1
			"triangle": x = absf(fmod(ph, 1.0) * 4 - 2) - 1
		var k := n0 + i
		if k < b.size(): b[k] += x * vol * exp(-t / dur * 6.9)

func _wav(b: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	var data := PackedByteArray(); data.resize(b.size() * 2)
	for i in range(b.size()):
		data.encode_s16(i * 2, int(clampf(b[i], -1, 1) * 32000))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS; w.mix_rate = RATE; w.stereo = false; w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD; w.loop_begin = 0; w.loop_end = b.size()
	return w

func _build() -> void:
	var b: PackedFloat32Array
	b = _buf(0.45); _noise(b, 0.35, 900, 1.2, 0.25); _tone(b, 0.3, 180, 90, 0.08, "sawtooth"); sounds.pull = _wav(b)
	b = _buf(0.35); _tone(b, 0.12, 60, 40, 0.2, "sawtooth"); _noise(b, 0.15, 300, 1, 0.2); _tone(b, 0.1, 55, 35, 0.15, "sawtooth", 0.15); sounds.sputter = _wav(b)
	b = _buf(0.5); _noise(b, 0.25, 2200, 1.5, 0.6); _noise(b, 0.4, 500, 1, 0.5, "lowpass", 0.02); sounds.crack = _wav(b)
	b = _buf(0.8); _tone(b, 0.7, 70, 30, 0.9); _noise(b, 0.5, 250, 0.8, 0.7, "lowpass"); _noise(b, 0.35, 1800, 1, 0.25, "bandpass", 0.03); sounds.thud = _wav(b)
	b = _buf(0.35)
	for i in range(5): _noise(b, 0.08, 2500 + randf() * 2000, 2, 0.25, "bandpass", i * 0.05)
	sounds.crunch = _wav(b)
	for g in range(3):
		b = _buf(0.22); _noise(b, 0.18, 320 + g * 40, 4, 0.35); _tone(b, 0.15, 220, 140, 0.08); sounds["glug%d" % g] = _wav(b)
	b = _buf(0.3)
	for i in range(6): _noise(b, 0.05, 3000 + randf() * 3000, 3, 0.2, "bandpass", i * 0.035)
	sounds.can_crush = _wav(b)
	b = _buf(0.3); _tone(b, 0.25, 1900, 1700, 0.12, "triangle"); _tone(b, 0.18, 2600, 2400, 0.06); sounds.clank = _wav(b)
	b = _buf(0.12); _noise(b, 0.08, 1500, 2, 0.25); _tone(b, 0.06, 400, 300, 0.1, "square"); sounds.door = _wav(b)
	b = _buf(0.4); _tone(b, 0.35, 90, 45, 0.6); _noise(b, 0.2, 800, 1, 0.4, "lowpass"); sounds.slam = _wav(b)
	b = _buf(0.09); _noise(b, 0.07, 650, 1.4, 0.07); sounds.step = _wav(b)
	b = _buf(0.14); _noise(b, 0.12, 700, 1, 0.15); sounds.pick = _wav(b)
	b = _buf(0.18); _noise(b, 0.15, 300, 1, 0.25, "lowpass"); _tone(b, 0.15, 120, 60, 0.15); sounds.drop = _wav(b)
	b = _buf(0.07); _tone(b, 0.06, 180, 166, 0.05, "square"); sounds.blip = _wav(b)
	b = _buf(0.65); _tone(b, 0.12, 1800, 1800, 0.15, "triangle"); _tone(b, 0.5, 2400, 2400, 0.15, "triangle", 0.1); _noise(b, 0.2, 4000, 2, 0.1, "bandpass", 0.05); sounds.cash = _wav(b)
	b = _buf(0.6); _tone(b, 0.4, 880, 880, 0.12); _tone(b, 0.5, 1320, 1320, 0.08, "sine", 0.08); sounds.ding = _wav(b)
	b = _buf(1.5)
	var ph := 0.0
	var bp := Biquad.new("bandpass", 900, 6, RATE)
	for i in range(b.size()):
		var t := float(i) / RATE
		ph += (70 + 70 * t / 1.2) / RATE
		var env := clampf(t / 0.3, 0, 1) * clampf((1.4 - t) / 0.3, 0, 1)
		b[i] += bp.run(fmod(ph, 1.0) * 2 - 1) * 0.5 * env
	sounds.creak = _wav(b)
	# engine loops (1 s, whole number of cycles so they loop cleanly); base pitch 100 Hz
	sounds.engine_saw = _engine_loop(100, 22, 2600)
	sounds.engine_chipper = _engine_loop(100, 9, 700)
	sounds.engine_truck = _engine_loop(100, 6, 520)
	sounds.grit_saw = _grit_loop(2600)
	sounds.grit_chip = _grit_loop(900)

func _engine_loop(f: float, lfo: float, lp: float) -> AudioStreamWAV:
	var b := _buf(1.0)
	var flt := Biquad.new("lowpass", lp, 0.8, RATE)
	for pass_i in range(2):          # run the filter twice over so the loop seam is already settled
		for i in range(b.size()):
			var t := float(i) / RATE
			var saw := fmod(t * f, 1.0) * 2 - 1
			var sq := 1.0 if fmod(t * f * 2, 1.0) < 0.5 else -1.0
			var x := tanh((saw * 0.5 + sq * 0.25) * 3)
			var y := flt.run(x) * (1.0 + 0.25 * sin(TAU * lfo * t))
			if pass_i == 1: b[i] = y * 0.6
	return _wav(b, true)

func _grit_loop(freq: float) -> AudioStreamWAV:
	var b := _buf(1.0)
	var flt := Biquad.new("bandpass", freq, 0.8, RATE)
	for i in range(b.size()): b[i] = flt.run(randf() * 2 - 1) * 1.6
	var fade := 400
	for i in range(fade):   # crossfade the ends for a seamless loop
		var k := float(i) / fade
		b[i] = b[i] * k + b[b.size() - fade + i] * (1 - k)
	return _wav(b.slice(0, b.size() - fade), true)

## a running engine: set(rpm 0..1, load 0..1, volume 0..1); stop()
class MachineSound:
	var hum: AudioStreamPlayer
	var grit: AudioStreamPlayer
	var kind := ""
	func setv(rpm: float, ld: float, vol: float) -> void:
		var f := 40.0 + rpm * 150.0
		if kind == "chipper": f = 34.0 + rpm * 20.0
		elif kind == "truck": f = 30.0 + rpm * 55.0
		hum.pitch_scale = clampf(f / 100.0, 0.1, 4.0)
		hum.volume_db = linear_to_db(maxf(vol, 0.0005))
		var gk := 0.35 if kind == "saw" else 0.5
		grit.volume_db = linear_to_db(maxf(vol * ld * gk * 1.4, 0.0005))
		grit.pitch_scale = clampf(0.8 + rpm * 0.5, 0.2, 3.0)
	func stop() -> void:
		var tw := hum.create_tween()
		tw.tween_property(hum, "volume_db", -60.0, 0.4)
		tw.parallel().tween_property(grit, "volume_db", -60.0, 0.4)
		tw.tween_callback(func(): hum.queue_free(); grit.queue_free())

func engine(kind: String) -> MachineSound:
	var e := MachineSound.new()
	e.kind = kind
	e.hum = AudioStreamPlayer.new(); e.hum.stream = sounds["engine_" + kind]; e.hum.bus = "Machines"; e.hum.volume_db = -60
	e.grit = AudioStreamPlayer.new(); e.grit.stream = sounds["grit_saw" if kind == "saw" else "grit_chip"]; e.grit.bus = "Machines"; e.grit.volume_db = -60
	add_child(e.hum); add_child(e.grit)
	e.hum.play(); e.grit.play()
	return e
