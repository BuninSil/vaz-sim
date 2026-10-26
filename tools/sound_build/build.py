# Нарезка реальных записей в петли и одиночные звуки для симулятора.
import sys, os, json, numpy as np, soundfile as sf
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__))); from track import *
from scipy.signal import resample_poly, butter, sosfilt
SRC = sys.argv[1]; OUT = sys.argv[2]; os.makedirs(OUT, exist_ok=True)
SR = 44100
manifest = {}

def to44(x, sr):
    if sr == SR: return x
    from math import gcd
    g = gcd(int(sr), SR); return resample_poly(x, SR//g, int(sr)//g)

def fade(y, a=0.005, b=0.03):
    A = int(a*SR); B = int(b*SR)
    if A: y[:A] *= np.linspace(0, 1, A)
    if B: y[-B:] *= np.linspace(1, 0, B)
    return y

def save(name, y, **meta):
    y = np.clip(y, -1, 1).astype(np.float32)
    # Кодер Vorbis в libsndfile падает от переполнения стека на больших блоках — пишем порциями.
    with sf.SoundFile(os.path.join(OUT, name + ".ogg"), "w", SR, 1, format="OGG", subtype="VORBIS") as f:
        for i in range(0, len(y), 4096): f.write(y[i:i+4096])
    meta["len"] = round(len(y)/SR, 3); manifest[name] = meta
    print("%-18s %6.2f s  rms %5.1f dB  peak %5.1f dB" % (name, len(y)/SR, 20*np.log10(np.sqrt(np.mean(y**2))+1e-9), 20*np.log10(np.max(np.abs(y))+1e-9)))

def engine_loop(name, file, t0, t1, fmin, fmax, f_target=None, smooth=0, rms=-20):
    x, sr = load(os.path.join(SRC, file), t0 - 0.3, t1 + 0.3)
    tt, ff = track(x, sr, fmin, fmax)
    if smooth: ff = np.polyval(np.polyfit(tt, ff, smooth), tt)
    a = int(0.3*sr); b = len(x) - int(0.3*sr)
    x = x[a:b]; tt = tt - 0.3
    m = (tt >= 0) & (tt <= (t1 - t0)); tt, ff = tt[m], ff[m]
    if f_target is None: f_target = float(np.median(ff))
    y = dechirp(x, sr, tt, ff, f_target)
    y = to44(hp(y, sr, 22), sr)
    y = make_loop(y, SR, f_target, xfade=min(0.08, len(y)/SR*0.2))
    save(name, norm(y, rms), rpm=round(f_target*30, 1), loop=True)

def cut(name, file, t0, t1, rms=None, peak=None, loop=False, hpf=0, a=0.005, b=0.03, xf=0.15):
    x, sr = load(os.path.join(SRC, file), t0, t1 + (xf if loop else 0))
    y = to44(x, sr)
    if hpf: y = hp(y, SR, hpf)
    if loop: y = make_loop(y, SR, 1.0, cycles=None, xfade=xf) if False else _loop_plain(y, xf)
    else: y = fade(y, a, b)
    if rms is not None: y = norm(y, rms)
    if peak is not None: y = y * (10**(peak/20) / (np.max(np.abs(y)) + 1e-9))
    save(name, y, loop=loop)

def _loop_plain(y, xf):
    X = int(xf*SR); body = y[:-X].copy(); tail = y[-X:]
    w = np.sin(np.linspace(0, np.pi/2, X))**2
    body[:X] = body[:X]*w + tail*(1-w); return body

# --- Двигатель (одна и та же Lada 1500 Combi 1981, запись Yle) ---------------
engine_loop("eng_idle", "yle_approach.wav", 23.2, 26.2, 24, 36, rms=-20)
engine_loop("eng_on_2050", "yle_pulling_away.wav", 11.45, 12.75, 62, 75)
engine_loop("eng_on_2850", "yle_pulling_away.wav", 20.3, 21.7, 88, 104)
engine_loop("eng_on_3300", "yle_pulling_away.wav", 16.75, 17.55, 100, 122)
engine_loop("eng_on_3800", "yle_pulling_away.wav", 17.8, 18.5, 118, 136)
engine_loop("eng_on_4200", "yle_pulling_away.wav", 18.6, 19.3, 132, 148)
engine_loop("eng_off_3700", "yle_approach.wav", 11.0, 12.8, 115, 140, smooth=2)
engine_loop("eng_off_3150", "yle_approach.wav", 13.6, 15.6, 95, 115, smooth=2)
engine_loop("eng_off_2500", "yle_approach.wav", 16.4, 17.9, 72, 95, smooth=2)
cut("eng_stop", "yle_approach.wav", 26.9, 28.9, peak=-3, b=0.4)
cut("starter_engage", "beeld_idle.ogg", 1.9, 2.25, peak=-6)
cut("starter_loop", "beeld_idle.ogg", 2.2, 3.85, rms=-18, loop=True, xf=0.2)
cut("starter_fail", "fs_starter_fail_volvo.ogg", 17.6, 18.75, peak=-4)
cut("crank_nostart", "fs_crank_nostart.ogg", 0.72, 2.42, rms=-18, loop=True, xf=0.15)
# --- Неисправности ---------------------------------------------------------
cut("rod_knock", "fs_rod_knock.ogg", 2.0, 26.0, rms=-20, loop=True, xf=0.3)
cut("bearing_knock", "fs_bearing_knock.ogg", 0.2, 8.8, rms=-20, loop=True, xf=0.2)
cut("belt_squeal", "fs_belt_squeal.ogg", 6.5, 12.5, rms=-18, loop=True, xf=0.4, hpf=300)
cut("steam", "fs_steam_radiator.ogg", 6.0, 34.0, rms=-22, loop=True, xf=0.5)
cut("backfire", "fs_backfire.ogg", 0.0, 1.6, peak=-1, b=0.5)
# --- Дорога и шины ---------------------------------------------------------
cut("road", "fs_interior_road.ogg", 5.0, 80.0, rms=-22, loop=True, xf=0.5)
cut("gravel", "fs_gravel_wheel.ogg", 40.0, 100.0, rms=-22, loop=True, xf=0.5)
cut("tire_squeal", "bg_brake_hard.ogg", 5.35, 7.0, rms=-16, loop=True, xf=0.25, hpf=200)
cut("tire_squeal2", "bg_brake.ogg", 1.9, 4.3, rms=-16, loop=True, xf=0.3, hpf=200)
cut("bump", "fs_speedbump.ogg", 2.17, 2.48, peak=-2, b=0.12)
cut("bump2", "fs_speedbump.ogg", 2.52, 2.85, peak=-2, b=0.12)
cut("crash", "bg_brake_crash.ogg", 10.05, 15.6, peak=-1, b=0.8)
cut("crash_glass", "fs_crash_glass.ogg", 0.0, 2.4, peak=-1, b=0.4)
cut("impact", "fs_crash_squeal.ogg", 1.33, 3.3, peak=-1, b=0.5)
# --- Кузов -------------------------------------------------------------------
cut("door_open", "fs_door_shed.ogg", 0.82, 1.75, peak=-3, b=0.2)
cut("door_close", "fs_door_shed.ogg", 3.8, 5.0, peak=-2, b=0.3)
cut("door_close2", "fs_door_old.ogg", 3.45, 4.4, peak=-2, b=0.3)
cut("door_squeak", "fs_door_squeak.ogg", 3.1, 3.58, peak=-4, b=0.08)
cut("hood_open", "bg_hood.ogg", 2.6, 3.95, peak=-3, b=0.2)
cut("hood_close", "bg_hood.ogg", 8.85, 9.6, peak=-1, b=0.25)
cut("trunk_open", "bg_trunk.ogg", 4.7, 5.35, peak=-3, b=0.15)
cut("trunk_close", "bg_trunk.ogg", 9.4, 10.1, peak=-1, b=0.25)
cut("handbrake_on", "bg_handbrake_on.ogg", 0.85, 2.55, peak=-3, b=0.4)
cut("handbrake_off", "bg_handbrake_off.ogg", 1.4, 2.6, peak=-3, b=0.3)
cut("indicator_tick", "fs_indicator_onoff.ogg", 1.17, 1.34, peak=-3, b=0.05)
cut("indicator_tock", "fs_indicator_onoff.ogg", 1.55, 1.72, peak=-4, b=0.05)
cut("horn_start", "bg_horn.ogg", 0.38, 1.3, peak=-2, a=0.003, b=0.0001)
cut("horn_loop", "bg_horn.ogg", 1.3, 3.9, rms=-12, loop=True, xf=0.2)
cut("horn_end", "bg_horn.ogg", 4.1, 4.6, peak=-6, b=0.15)
json.dump(manifest, open(os.path.join(OUT, "manifest.json"), "w"), indent=1, ensure_ascii=False)
