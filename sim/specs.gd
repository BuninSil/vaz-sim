class_name EngineSpecs
extends RefCounted

# Паспортные данные двигателя и трансмиссии. По умолчанию — ВАЗ-2103 (1,5 л),
# который ставился на ВАЗ-21061; apply_engine/apply_gearbox переключают на другие
# моторы семейства (тот же блок, цепной ГРМ — разборка и поломки общие).
# Все величины в СИ: метры, килограммы, секунды, паскали, кельвины.
# Углы распределения фаз и опережения — в градусах поворота коленвала.

const CYLINDERS := 4
static var BORE := 0.076
static var STROKE := 0.080
static var CRANK_RADIUS := 0.040
static var ROD_LENGTH := 0.136
static var COMPRESSION_RATIO := 8.5
const BORE_PITCH := 0.095
# Порядок работы 1-3-4-2: смещение рабочего цикла каждого цилиндра (рад поворота коленвала).
const FIRING_ORDER := [1, 3, 4, 2]
const CYCLE_OFFSET: Array[float] = [0.0, 3.0 * PI, 1.0 * PI, 2.0 * PI]

# Фазы газораспределения ВАЗ-2101/2103 (при зазоре 0,15 мм).
static var IVO_BTDC := 12.0
static var IVC_ABDC := 40.0
static var EVO_BBDC := 42.0
static var EVC_ATDC := 10.0
static var INTAKE_VALVE_DIAMETER := 0.038
static var EXHAUST_VALVE_DIAMETER := 0.033
static var VALVE_LIFT := 0.0095
const ROCKER_RATIO := 1.5
const VALVE_CLEARANCE := 0.00015
# Клапанная пружина: обороты, выше которых клапан перестаёт отслеживать кулачок.
static var VALVE_FLOAT_RPM := 6900.0
# Дребезг контактов прерывателя: с этих оборотов искра начинает пропадать.
static var POINTS_BOUNCE_RPM := 6700.0
# Длина впускного канала от коллектора до клапана: определяет обороты резонансного наддува.
static var RUNNER_LENGTH := 0.22

# Массы кривошипно-шатунного механизма.
static var PISTON_MASS := 0.43
static var ROD_MASS := 0.81
static var RECIP_MASS := 0.43 + 0.81 * 0.33
static var CRANK_INERTIA := 0.135  # коленвал + маховик + сцепление, кг·м²

# Объёмы впуска и выпуска.
const INTAKE_MANIFOLD_VOLUME := 0.0012
const EXHAUST_MANIFOLD_VOLUME := 0.0028
static var EXHAUST_SYSTEM_AREA := 0.00105  # эффективное сечение глушителя
const BLOWBY_AREA := 0.12e-6  # зазоры колец нового двигателя на цилиндр

# Карбюратор «Озон 2107»: диаметры камер, диффузоров и жиклёров.
static var PRIMARY_BORE := 0.028
static var SECONDARY_BORE := 0.032
static var PRIMARY_VENTURI := 0.022
static var SECONDARY_VENTURI := 0.025
static var PRIMARY_MAIN_JET := 0.00112
static var SECONDARY_MAIN_JET := 0.00150
static var IDLE_FUEL_JET := 0.00050
const THROTTLE_CLOSED_DEG := 6.0
const FUEL_DENSITY := 740.0
const FUEL_LHV := 43.5e6
const AFR_STOICH := 14.7

# Зажигание: контактный трамблёр 30.3706, катушка Б117А.
static var IGNITION_INITIAL_DEG := 3.0
static var CENTRIFUGAL_CURVE := [[0.0, 0.0], [1000.0, 0.0], [1500.0, 4.0], [2000.0, 9.0], [2500.0, 14.0], [3000.0, 19.0], [3500.0, 23.0], [4000.0, 25.0], [7000.0, 27.0]]
const VACUUM_ADVANCE_MAX_DEG := 16.0
const DWELL_FRACTION := 0.61  # угол замкнутого состояния 55° из 90° кулачка
const COIL_RESISTANCE := 3.4
const COIL_INDUCTANCE := 0.0085

# Эталонные паспортные точки — по ним проверяется модель.
static var RATED_POWER_KW := 52.9
static var RATED_POWER_RPM := 5600.0
static var MAX_TORQUE_NM := 104.0
static var MAX_TORQUE_RPM := 3400.0
static var IDLE_RPM := 850.0
static var REDLINE_RPM := 6000.0

# Трансмиссия ВАЗ-2106.
static var GEAR_RATIOS: Array[float] = [-3.53, 0.0, 3.667, 2.100, 1.361, 1.000]
static var GEAR_NAMES: Array[String] = ["R", "N", "1", "2", "3", "4"]
static var FINAL_DRIVE := 3.9
const WHEEL_RADIUS := 0.284
const VEHICLE_MASS := 1120.0
const DRAG_AREA := 0.48 * 1.85
const STARTER_RATIO := 129.0 / 11.0


static func displacement() -> float:
	return PI * BORE * BORE * 0.25 * STROKE * CYLINDERS


static func piston_area() -> float:
	return PI * BORE * BORE * 0.25


static func clearance_volume() -> float:
	return piston_area() * STROKE / (COMPRESSION_RATIO - 1.0)


# --- Варианты ------------------------------------------------------------------
# Моторы классики: диаметр × ход, степень сжатия, фазы и подъём клапанов,
# карбюратор (жиклёры), паспорт для проверки.
const ENGINES := {
	"21011": {"title": "ВАЗ-21011 — 1,3 л, 69 л.с. (ставился на 21063)", "bore": 0.079, "stroke": 0.066, "cr": 8.8,
		"rod": 0.136, "piston": 0.42, "jets": [0.00107, 0.00150, 0.00047], "power": [50.6, 5600.0], "torque": [94.0, 3400.0], "redline": 6000.0},
	"2103": {"title": "ВАЗ-2103 — 1,45 л, 71 л.с. (ставился на 21061)", "bore": 0.076, "stroke": 0.080, "cr": 8.5,
		"rod": 0.136, "piston": 0.43, "jets": [0.00112, 0.00150, 0.00050], "power": [52.9, 5600.0], "torque": [104.0, 3400.0], "redline": 6000.0},
	"2106": {"title": "ВАЗ-2106 «шестёрочный» — 1,57 л, 75 л.с.", "bore": 0.079, "stroke": 0.080, "cr": 8.5,
		"rod": 0.136, "piston": 0.46, "jets": [0.00117, 0.00155, 0.00050], "power": [55.5, 5400.0], "torque": [116.0, 3000.0], "redline": 6000.0},
	"21213": {"title": "ВАЗ-21213 (от «Нивы») — 1,69 л, 80 л.с.", "bore": 0.082, "stroke": 0.080, "cr": 9.3,
		"rod": 0.136, "piston": 0.49, "jets": [0.00122, 0.00162, 0.00052], "power": [58.0, 5200.0], "torque": [127.0, 3000.0], "redline": 5800.0},
	"2106s": {"title": "ВАЗ-2106 доработанный — 1,6 л, ≈95 л.с. (спортвал, сжатие 10, клапаны 39,5/34,5, бесконтактное зажигание)", "bore": 0.079, "stroke": 0.080, "cr": 10.0,
		"rod": 0.136, "piston": 0.40, "jets": [0.00114, 0.00150, 0.00055], "power": [70.0, 6400.0], "torque": [128.0, 4500.0], "redline": 7000.0,
		"cam": [24.0, 60.0, 62.0, 22.0, 0.0108], "float": 7700.0, "points": 7300.0, "runner": 0.15, "valves": [0.0395, 0.0345], "carb": [0.032, 0.034, 0.024, 0.026], "flywheel": 0.115, "exhaust": 0.0013},
}

const GEARBOXES := {
	"4": {"title": "4-ступенчатая ВАЗ-2106", "ratios": [-3.53, 0.0, 3.667, 2.100, 1.361, 1.000], "names": ["R", "N", "1", "2", "3", "4"]},
	"5": {"title": "5-ступенчатая ВАЗ-21074 (5-я 0,82)", "ratios": [-3.53, 0.0, 3.667, 2.100, 1.361, 1.000, 0.820], "names": ["R", "N", "1", "2", "3", "4", "5"]},
	"5s": {"title": "5-ступенчатая близкорядная (раллийная)", "ratios": [-3.53, 0.0, 2.950, 1.940, 1.400, 1.130, 0.940], "names": ["R", "N", "1", "2", "3", "4", "5"]},
}

const FINAL_DRIVES: Array[float] = [3.9, 4.1, 4.3, 4.44]

static var engine_id := "2103"
static var gearbox_id := "4"


static func apply_engine(id: String) -> void:
	var e: Dictionary = ENGINES[id]
	engine_id = id
	BORE = e["bore"]
	STROKE = e["stroke"]
	CRANK_RADIUS = STROKE * 0.5
	ROD_LENGTH = e["rod"]
	COMPRESSION_RATIO = e["cr"]
	PISTON_MASS = e["piston"]
	RECIP_MASS = PISTON_MASS + ROD_MASS * 0.33
	var cam: Array = e.get("cam", [12.0, 40.0, 42.0, 10.0, 0.0095])
	IVO_BTDC = cam[0]
	IVC_ABDC = cam[1]
	EVO_BBDC = cam[2]
	EVC_ATDC = cam[3]
	VALVE_LIFT = cam[4]
	VALVE_FLOAT_RPM = e.get("float", 6900.0)
	POINTS_BOUNCE_RPM = e.get("points", 6700.0)
	RUNNER_LENGTH = e.get("runner", 0.22)
	var valves: Array = e.get("valves", [0.038, 0.033])
	INTAKE_VALVE_DIAMETER = valves[0]
	EXHAUST_VALVE_DIAMETER = valves[1]
	var carb: Array = e.get("carb", [0.028, 0.032, 0.022, 0.025])
	PRIMARY_BORE = carb[0]
	SECONDARY_BORE = carb[1]
	PRIMARY_VENTURI = carb[2]
	SECONDARY_VENTURI = carb[3]
	var jets: Array = e["jets"]
	PRIMARY_MAIN_JET = jets[0]
	SECONDARY_MAIN_JET = jets[1]
	IDLE_FUEL_JET = jets[2]
	CRANK_INERTIA = e.get("flywheel", 0.135)
	EXHAUST_SYSTEM_AREA = e.get("exhaust", 0.00105)
	RATED_POWER_KW = e["power"][0]
	RATED_POWER_RPM = e["power"][1]
	MAX_TORQUE_NM = e["torque"][0]
	MAX_TORQUE_RPM = e["torque"][1]
	REDLINE_RPM = e["redline"]


static func apply_gearbox(id: String, final_drive: float) -> void:
	var g: Dictionary = GEARBOXES[id]
	gearbox_id = id
	GEAR_RATIOS.assign(g["ratios"])
	GEAR_NAMES.assign(g["names"])
	FINAL_DRIVE = final_drive
