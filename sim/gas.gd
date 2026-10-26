class_name Gas
extends RefCounted

# Газодинамика: расход через отверстие (сопло) для идеального газа.
# Функция расхода psi(pr) заранее табулирована, чтобы в основном цикле не считать pow().

const R_AIR := 287.0
const R_FUEL := 83.0
const R_BURNED := 290.0
const P_ATM := 101325.0
const T_AMB := 293.15
const GAMMA := 1.35
const TABLE_SIZE := 1024

static var _psi := PackedFloat64Array()
static var _critical := 0.0


static func _ensure_table() -> void:
	if _psi.size() == TABLE_SIZE + 1:
		return
	_critical = pow(2.0 / (GAMMA + 1.0), GAMMA / (GAMMA - 1.0))
	_psi.resize(TABLE_SIZE + 1)
	for i in TABLE_SIZE + 1:
		var pr := maxf(float(i) / TABLE_SIZE, _critical)
		var v := 2.0 * GAMMA / (GAMMA - 1.0) * (pow(pr, 2.0 / GAMMA) - pow(pr, (GAMMA + 1.0) / GAMMA))
		_psi[i] = sqrt(maxf(v, 0.0))


# Массовый расход (кг/с) от p_up к p_down. Отрицательный — если поток обратный.
static func orifice(cd_area: float, p_up: float, t_up: float, r_up: float, p_down: float, t_down: float, r_down: float) -> float:
	if cd_area <= 0.0:
		return 0.0
	_ensure_table()
	if p_up >= p_down:
		var pr := p_down / p_up
		var f := pr * TABLE_SIZE
		var i := int(f)
		var psi := _psi[i] if i >= TABLE_SIZE else lerpf(_psi[i], _psi[i + 1], f - i)
		return cd_area * p_up / sqrt(r_up * t_up) * psi
	var pr2 := p_up / p_down
	var f2 := pr2 * TABLE_SIZE
	var j := int(f2)
	var psi2 := _psi[j] if j >= TABLE_SIZE else lerpf(_psi[j], _psi[j + 1], f2 - j)
	return -cd_area * p_down / sqrt(r_down * t_down) * psi2


# Масса, при перетекании которой давления двух объёмов сравняются.
# Ограничивает шаг, чтобы явная схема не «перепрыгивала» равновесие.
static func equalizing_mass(p1: float, v1: float, rt1: float, p2: float, v2: float, rt2: float) -> float:
	return absf(p1 - p2) / (rt1 / v1 + rt2 / v2)
