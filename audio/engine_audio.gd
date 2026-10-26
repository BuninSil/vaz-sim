class_name EngineAudio
extends Node

# Звук машины целиком собран из настоящих записей (источники — CREDITS.md):
#  • двигатель — петли «Лады 1500» 1981 года (запись Yle), снятые при разгоне под
#    нагрузкой и при торможении двигателем; каждая петля выровнена по высоте тона
#    до своих оборотов, здесь они перетекают одна в другую по оборотам и нагрузке
#    из модели и подстраиваются по высоте;
#  • стартер — запись пуска «Лады 1500 S» (Beeld en Geluid);
#  • стук вкладышей, стук клапанов и детонационный звон — одиночные удары из
#    записей неисправных моторов, проигрываются точно по углу коленвала;
#  • шины, дорога, удары, двери, ручник, реле поворотов, клаксон, пар, свист
#    ремня, хлопки в глушителе — отдельные записи.

signal backfire(strength: float)

const DIR := "res://models/sounds/"
const HIT_RATE := 22050.0

var volume := 0.8
var car: Car                    # машина на трассе (null на стенде)
var belt_loose := false         # неисправность: ослаб ремень генератора
var horn := false

var _manifest := {}
# Петли двигателя: [плеер, обороты записи]
var _on: Array = []
var _off: Array = []
var _idle: AudioStreamPlayer
var _idle_rpm := 880.0
var _loops := {}                # имя -> AudioStreamPlayer (бесконечные петли)
var _shots := {}                # имя -> AudioStreamPlayer (одиночные звуки)
var _hits := {}                 # имя -> Array[PackedFloat32Array]

var _gen: AudioStreamGeneratorPlayback
var _voices: Array = []         # [буфер, позиция, громкость]
var _knock_angle := 0.0
var _tick_angle := 0.0
var _ping_pending := 0.0
var _burst := 0

var _load := 0.3
var _fire_rate := 0.0
var _misfire_rate := 0.0
var _duck := 1.0
var _running := false
var _was_cranking := false
var _prev_rpm := 0.0
var _rpm_rate := 0.0
var _prev_key := 0
var _prev_blink := false
var _prev_handbrake := false
var _prev_grind := 0.0
var _prev_bump: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _prev_accel := Vector3.ZERO
var _impact_cool := 0.0
var _horn_on := false
var _key2_time := 0.0
var _starter_failed := false
var _rng := RandomNumberGenerator.new()
var _engine_bus := 0
var _muffle: AudioEffectLowPassFilter


func _ready() -> void:
	_setup_buses()
	var f := FileAccess.open(DIR + "manifest.json", FileAccess.READ)
	if f != null:
		_manifest = JSON.parse_string(f.get_as_text())
	for name in _manifest:
		if not str(name).begins_with("eng_") or name == "eng_stop":
			continue
		var p := _loop_player(name, "Engine")
		var rpm: float = _manifest[name].get("rpm", 1000.0)
		if name == "eng_idle":
			_idle = p
			_idle_rpm = rpm
		elif str(name).begins_with("eng_on"):
			_on.append([p, rpm])
		else:
			_off.append([p, rpm])
	_on.sort_custom(func(a, b) -> bool: return a[1] < b[1])
	_off.sort_custom(func(a, b) -> bool: return a[1] < b[1])
	for name in ["starter_loop", "belt_squeal", "steam", "road", "gravel", "tire_squeal", "tire_squeal2", "horn_loop"]:
		_loops[name] = _loop_player(name, "Master")
	for name in ["eng_stop", "starter_engage", "starter_fail", "backfire", "bump", "bump2", "crash", "crash_glass", "impact",
			"door_open", "door_close", "door_close2", "door_squeak", "hood_open", "hood_close", "trunk_open", "trunk_close",
			"handbrake_on", "handbrake_off", "indicator_tick", "indicator_tock", "horn_start", "horn_end"]:
		var p := AudioStreamPlayer.new()
		p.stream = _ogg(name)
		p.max_polyphony = 3
		add_child(p)
		_shots[name] = p
	for name in ["hit_knock", "hit_tick", "hit_ping"]:
		var list: Array[PackedFloat32Array] = []
		for i in 8:
			var buf := _read_wav(DIR + "hits/%s_%d.wav" % [name, i])
			if buf.is_empty():
				break
			list.append(buf)
		_hits[name] = list
	# Генератор для ударов, привязанных к углу коленвала.
	var gp := AudioStreamPlayer.new()
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = HIT_RATE
	gen.buffer_length = 0.1
	gp.stream = gen
	gp.bus = "Engine"
	add_child(gp)
	gp.play()
	_gen = gp.get_stream_playback()


func _setup_buses() -> void:
	_engine_bus = AudioServer.get_bus_index("Engine")
	if _engine_bus < 0:
		AudioServer.add_bus()
		_engine_bus = AudioServer.bus_count - 1
		AudioServer.set_bus_name(_engine_bus, "Engine")
		AudioServer.set_bus_send(_engine_bus, "Master")
		_muffle = AudioEffectLowPassFilter.new()
		_muffle.cutoff_hz = 16000.0
		AudioServer.add_bus_effect(_engine_bus, _muffle)
		# Мягкий ограничитель, чтобы разгон с хлопками не перегружал выход.
		var lim := AudioEffectHardLimiter.new()
		lim.ceiling_db = -0.5
		AudioServer.add_bus_effect(0, lim)
	else:
		_muffle = AudioServer.get_bus_effect(_engine_bus, 0) as AudioEffectLowPassFilter


func _ogg(name: String) -> AudioStreamOggVorbis:
	return AudioStreamOggVorbis.load_from_file(MeshUtil.raw_path(DIR + name + ".ogg"))


func _loop_player(name: String, bus: String) -> AudioStreamPlayer:
	var s := _ogg(name)
	s.loop = true
	var p := AudioStreamPlayer.new()
	p.stream = s
	p.bus = bus
	p.volume_db = -80.0
	add_child(p)
	# Каждая петля начинает со своего места, чтобы они не звучали в унисон.
	p.play(_rng.randf() * s.get_length())
	return p


# 16-битный WAV моно → массив отсчётов.
func _read_wav(path: String) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return out
	var data := f.get_buffer(f.get_length())
	var pos := 12
	while pos + 8 <= data.size():
		var id := data.slice(pos, pos + 4).get_string_from_ascii()
		var size := data.decode_u32(pos + 4)
		if id == "data":
			var n := size / 2
			out.resize(n)
			for i in n:
				out[i] = data.decode_s16(pos + 8 + i * 2) / 32768.0
			break
		pos += 8 + size + (size & 1)
	return out


func play(name: String, gain := 1.0, pitch := 1.0) -> void:
	var p: AudioStreamPlayer = _shots.get(name)
	if p == null:
		return
	p.volume_db = linear_to_db(maxf(gain * volume, 1e-4))
	p.pitch_scale = pitch
	p.play()


func _set_loop(name: String, gain: float, pitch := 1.0) -> void:
	var p: AudioStreamPlayer = _loops[name]
	p.volume_db = linear_to_db(maxf(gain * volume, 1e-5))
	p.pitch_scale = clampf(pitch, 0.3, 3.0)


# Вес соседних петель по оборотам: равномощный переход в логарифмической шкале.
func _anchor_weights(anchors: Array, rpm: float) -> PackedFloat32Array:
	var w := PackedFloat32Array()
	w.resize(anchors.size())
	if rpm <= anchors[0][1]:
		w[0] = 1.0
		return w
	if rpm >= anchors[-1][1]:
		w[anchors.size() - 1] = 1.0
		return w
	for i in anchors.size() - 1:
		var a: float = anchors[i][1]
		var b: float = anchors[i + 1][1]
		if rpm >= a and rpm < b:
			var t := log(rpm / a) / log(b / a)
			w[i] = cos(t * PI * 0.5)
			w[i + 1] = sin(t * PI * 0.5)
			break
	return w


func feed(sim: EngineSim, real_dt: float) -> void:
	var dt := maxf(real_dt, 1e-4)
	var rpm := sim.rpm()
	var e := sim.electrical
	var cranking := e.key == 2 and e.starter_current > 5.0
	# --- Состояние сгорания по событиям модели ----------------------------------
	var fires := sim.out_fires
	var misfires := sim.out_misfires
	sim.out_fires = 0
	sim.out_misfires = 0
	var k_rate := 1.0 - exp(-dt / 0.2)
	_fire_rate += (fires / dt - _fire_rate) * k_rate
	_misfire_rate += (misfires / dt - _misfire_rate) * k_rate
	var expected := maxf(rpm / 30.0, 1.0)
	var activity := clampf(_fire_rate / expected, 0.0, 1.0)
	var misfire_share := clampf(_misfire_rate / expected, 0.0, 1.0)
	# Пропуск вспышки — провал звука выпуска на один такт.
	if misfires > 0 and rpm > 300.0:
		_duck = minf(_duck, 1.0 - 0.45 * minf(misfires, 2) * 0.5)
		# Несгоревшая смесь вспыхивает в горячем глушителе.
		if sim.exhaust_temp > 720.0 and rpm > 1200.0 and _rng.randf() < 0.06 * misfires:
			var s := clampf((sim.exhaust_temp - 700.0) / 400.0, 0.3, 1.0)
			play("backfire", 0.55 * s, _rng.randf_range(0.85, 1.15))
			backfire.emit(s)
	_duck = move_toward(_duck, 1.0, dt * 9.0)
	var map := sim.im_p / Gas.P_ATM
	var load_target := clampf((map - 0.3) / 0.6, 0.0, 1.0)
	_load += (load_target - _load) * (1.0 - exp(-dt / 0.08))
	_rpm_rate += ((rpm - _prev_rpm) / dt - _rpm_rate) * (1.0 - exp(-dt / 0.1))
	_prev_rpm = rpm
	# Мотор «звучит», пока в нём есть вспышки или пока его крутят колёса.
	var gate := clampf(maxf(smoothstep(0.05, 0.45, activity), smoothstep(450.0, 800.0, rpm) * 0.8), 0.0, 1.0)
	if sim.seized:
		gate = 0.0
	var was_running := _running
	_running = gate > 0.3 and rpm > 350.0
	if was_running and not _running and not cranking and rpm < 600.0:
		play("eng_stop", 0.35)
	# --- Петли двигателя -------------------------------------------------------
	var amp := lerpf(0.5, 1.0, _load) * pow(clampf(rpm / 3000.0, 0.15, 2.2), 0.45) * gate * _duck
	amp *= 1.0 - 0.25 * misfire_share * _rng.randf()
	var w_on := _anchor_weights([[_idle, _idle_rpm]] + _on, rpm)
	var w_off := _anchor_weights([[_idle, _idle_rpm]] + _off, rpm)
	var idle_w := w_on[0] * _load + w_off[0] * (1.0 - _load)
	_set_engine(_idle, idle_w * amp, rpm / _idle_rpm)
	for i in _on.size():
		_set_engine(_on[i][0], w_on[i + 1] * _load * amp, rpm / _on[i][1])
	for i in _off.size():
		_set_engine(_off[i][0], w_off[i + 1] * (1.0 - _load) * amp, rpm / _off[i][1])
	# Засорённый глушитель глушит верх и делает звук «ватным».
	_muffle.cutoff_hz = lerpf(16000.0, 1200.0, pow(sim.exhaust_clog, 0.7))
	# --- Стартер ---------------------------------------------------------------
	if cranking and not _was_cranking:
		play("starter_engage", 0.7)
	_key2_time = _key2_time + dt if e.key == 2 else 0.0
	if _key2_time > 0.15 and not _starter_failed and rpm < 20.0 and (e.starter_current < 5.0 or sim.seized):
		# Щелчок и скрежет: стартер не провернул (сел аккумулятор или заклинило мотор).
		play("starter_fail", 0.7)
		_starter_failed = true
	if e.key != 2:
		_starter_failed = false
	_was_cranking = cranking
	_prev_key = e.key
	var crank_gain := 0.0
	if cranking:
		crank_gain = clampf(e.starter_current / 150.0, 0.3, 1.0) * (1.0 - 0.6 * smoothstep(500.0, 900.0, rpm))
	_set_loop("starter_loop", crank_gain * 0.8, clampf(rpm / 330.0, 0.5, 1.6))
	# --- Неисправности -----------------------------------------------------------
	var squeal := 0.0
	if belt_loose and rpm > 300.0:
		squeal = clampf(_rpm_rate / 2500.0, 0.0, 1.0) + clampf(e.alternator_current / 45.0 - 0.5, 0.0, 0.4)
	_set_loop("belt_squeal", squeal * 0.7, clampf(0.85 + rpm / 9000.0, 0.8, 1.5))
	var steam := 0.0
	if sim.thermal.boiling:
		steam = clampf((sim.thermal.t_coolant - 375.0) / 15.0, 0.25, 1.0)
	steam = maxf(steam, clampf(sim.head_gasket_damage - 0.5, 0.0, 0.5) * gate)
	_set_loop("steam", steam * 0.6)
	_mix_hits(sim, rpm, dt, gate)
	# Сырые отсчёты модели здесь больше не нужны — не даём очереди расти.
	sim.out_exhaust.clear()
	sim.out_intake.clear()
	sim.out_mech.clear()
	sim.out_knock.clear()
	sim.out_dt.clear()
	# --- Машина на дороге --------------------------------------------------------
	_vehicle_sounds(dt)


func _set_engine(p: AudioStreamPlayer, gain: float, pitch: float) -> void:
	p.volume_db = linear_to_db(maxf(gain * volume, 1e-5))
	p.pitch_scale = clampf(pitch, 0.3, 3.0)


# Удары по углу коленвала: стук вкладышей раз за оборот, клапаны — по числу
# закрытий, детонационный звон — по вспышкам с детонацией.
func _mix_hits(sim: EngineSim, rpm: float, dt: float, gate: float) -> void:
	var knock_amp := 0.0
	if sim.bearing_damage > 0.15 or sim.rod_failure:
		knock_amp = clampf((sim.bearing_damage - 0.15) * 1.6, 0.0, 1.0) * lerpf(0.4, 1.0, _load)
		if sim.rod_failure:
			knock_amp = 1.0
	var tick_amp := clampf(sim.valve_clearance_extra / 0.0003, 0.0, 1.0) * 0.45
	# Зависание клапанов: тарелки бьют по сёдлам — частый металлический дребезг.
	tick_amp = maxf(tick_amp, sim.valve_float * 0.9)
	# Перекрутка: срыв цепи ГРМ, удары клапанов о поршни, обрыв шатуна.
	if sim.ev_chain > 0:
		sim.ev_chain = 0
		play("impact", 1.0, 1.35)
		_burst += 9
	if sim.ev_valve_hits > 0:
		_burst += 3 * sim.ev_valve_hits
		sim.ev_valve_hits = 0
	if sim.ev_rod > 0:
		sim.ev_rod = 0
		play("impact", 1.0, 0.7)
		play("crash_glass", 0.35, 0.6)
		_burst += 14
	var knock_sum := 0.0
	for v in sim.out_knock:
		knock_sum += v
	_ping_pending += clampf(knock_sum * 0.5, 0.0, 6.0)
	if _gen == null:
		return
	var frames := mini(_gen.get_frames_available(), int(dt * HIT_RATE) + 64)
	if frames <= 0:
		return
	var rev_per_sample := rpm / 60.0 / HIT_RATE
	var pings := int(_ping_pending)
	_ping_pending -= pings
	var ping_every := frames / maxi(pings, 1)
	for n in frames:
		if rpm > 60.0 and gate > 0.0:
			_knock_angle += rev_per_sample
			if _knock_angle >= 1.0:
				_knock_angle -= 1.0
				if knock_amp > 0.0:
					_spawn("hit_knock", knock_amp * 0.9)
			# 8 клапанов за два оборота — 4 удара на оборот.
			_tick_angle += rev_per_sample * 4.0
			if _tick_angle >= 1.0:
				_tick_angle -= 1.0
				if tick_amp > 0.0:
					_spawn("hit_tick", tick_amp * _rng.randf_range(0.6, 1.0))
		# Серия ударов при поломке: частые глухие удары с затуханием.
		if _burst > 0 and n % 220 == 0:
			_burst -= 1
			_spawn("hit_knock", 1.0)
			_spawn("hit_ping", 0.6)
		if pings > 0 and n % ping_every == 0:
			pings -= 1
			_spawn("hit_ping", 0.35)
		var s := 0.0
		var i := _voices.size() - 1
		while i >= 0:
			var vc: Array = _voices[i]
			var buf: PackedFloat32Array = vc[0]
			var pos: int = vc[1]
			s += buf[pos] * vc[2]
			pos += 1
			if pos >= buf.size():
				_voices.remove_at(i)
			else:
				vc[1] = pos
			i -= 1
		s *= volume
		_gen.push_frame(Vector2(s, s))


func _spawn(name: String, gain: float) -> void:
	var list: Array = _hits.get(name, [])
	if list.is_empty() or _voices.size() > 12:
		return
	_voices.append([list[_rng.randi() % list.size()], 0, gain])


func _vehicle_sounds(dt: float) -> void:
	if car == null or not car.visible:
		for n in ["road", "gravel", "tire_squeal", "tire_squeal2"]:
			_set_loop(n, 0.0)
		_horn(dt)
		return
	var vd := car.vd
	var v := absf(car.speed_kmh()) / 3.6
	var pos := car.global_position
	var off_road := absf(pos.x) > Road.WIDTH * 0.5 + 0.8
	var zone := car.road.zone_type(-pos.z)
	var rough := 0.0
	match zone:
		"cobble", "rails": rough = 1.0
		"broken", "holes", "wash": rough = 0.6
	var any_contact := false
	for c in car.contact:
		any_contact = any_contact or c
	var roll := clampf(v / 25.0, 0.0, 1.4) if any_contact else 0.0
	_set_loop("road", roll * (0.35 + 0.35 * rough) * (0.0 if off_road else 1.0), 0.75 + 0.35 * clampf(v / 30.0, 0.0, 1.2) + 0.1 * rough)
	_set_loop("gravel", roll * 0.8 * (1.0 if off_road else 0.0), 0.8 + 0.3 * clampf(v / 20.0, 0.0, 1.0))
	# Визг шин: боковой увод сверх предела сцепления и продольное проскальзывание.
	var lat := 0.0
	var lon := 0.0
	for i in 4:
		if not car.contact[i]:
			continue
		lat = maxf(lat, smoothstep(0.09, 0.2, absf(car.slip_angle[i])))
		lon = maxf(lon, smoothstep(0.12, 0.35, absf(vd.slip[i])))
	var wet := zone == "wet"
	var asphalt := not off_road and zone != "cobble"
	var sq := clampf(v / 4.0, 0.0, 1.0) * (0.0 if not asphalt else (0.45 if wet else 1.0))
	_set_loop("tire_squeal", lat * sq * 0.9, 0.95 + 0.1 * lat)
	_set_loop("tire_squeal2", lon * sq * 0.9, 0.9 + 0.15 * lon)
	# Удары подвески в отбойники и резкие толчки кузова.
	for i in 4:
		var b: float = car.bump_hit[i]
		if b > _prev_bump[i] + 0.5:
			play("bump" if i < 2 else "bump2", clampf(0.4 + v / 25.0, 0.3, 1.0), _rng.randf_range(0.9, 1.1))
		_prev_bump[i] = b
	_impact_cool -= dt
	var jerk := (car.accel_g - _prev_accel).length()
	_prev_accel = car.accel_g
	if car.accel_g.length() > 3.0 and jerk > 2.0 and _impact_cool <= 0.0:
		play("impact", clampf(car.accel_g.length() / 6.0, 0.4, 1.0))
		_impact_cool = 0.8
	# Скрежет синхронизатора при переключении без выжима сцепления.
	if vd.grinding > 0.9 and _prev_grind <= 0.9:
		play("starter_fail", 0.6, 1.35)
	_prev_grind = vd.grinding
	var hb := vd.handbrake > 0.5
	if hb != _prev_handbrake:
		play("handbrake_on" if hb else "handbrake_off", 0.8)
	_prev_handbrake = hb
	var bm := car.body_model
	if bm.blink_on != _prev_blink:
		play("indicator_tick" if bm.blink_on else "indicator_tock", 0.5)
	_prev_blink = bm.blink_on
	_horn(dt)


func _horn(_dt: float) -> void:
	if horn and not _horn_on:
		play("horn_start", 0.9)
	elif not horn and _horn_on:
		play("horn_end", 0.9)
		(_shots["horn_start"] as AudioStreamPlayer).stop()
	_horn_on = horn
	var start: AudioStreamPlayer = _shots["horn_start"]
	# Сустейн вступает, когда атака почти отзвучала.
	var sustain := horn and (not start.playing or start.get_playback_position() > 0.8)
	_set_loop("horn_loop", 0.9 if sustain else 0.0)
