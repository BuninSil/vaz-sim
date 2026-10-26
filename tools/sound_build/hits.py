# Одиночные удары из реальных записей стука — их проигрывают по углу коленвала.
import sys, os, numpy as np, soundfile as sf
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__))); from track import load
from scipy.signal import resample_poly, butter, sosfilt
SRC, OUT = sys.argv[1], sys.argv[2]; R = 22050
def hits(file, t0, t1, period, n, length, hpf, name, up=1.0):
    x, sr = load(os.path.join(SRC, file), t0, t1)
    y = sosfilt(butter(2, hpf, "highpass", fs=sr, output="sos"), x)
    env = np.abs(y); h = int(sr*0.002); env = np.convolve(env, np.ones(h)/h, "same")
    # Пики огибающей не чаще периода стука.
    idx = []; i = 0; P = int(period*sr*0.7)
    order = np.argsort(-env)
    taken = np.zeros(len(env), bool)
    for k in order:
        if len(idx) >= n: break
        if k < int(0.01*sr) or k + int(length*sr) >= len(y) or taken[max(0, k-P):k+P].any(): continue
        taken[k] = True; idx.append(k)
    out = []
    for k in sorted(idx):
        a = k - int(0.004*sr); seg = y[a:a+int(length*sr)].copy()
        w = np.ones(len(seg)); f = int(len(seg)*0.5); w[-f:] = np.linspace(1, 0, f)**2; w[:int(0.002*sr)] = np.linspace(0, 1, int(0.002*sr))
        seg *= w
        seg = resample_poly(seg, int(R), int(sr*up)) if up != 1.0 else resample_poly(seg, R, sr)
        out.append(seg / (np.max(np.abs(seg)) + 1e-9) * 0.9)
    for j, seg in enumerate(out):
        sf.write(os.path.join(OUT, "%s_%d.wav" % (name, j)), seg.astype(np.float32), R, subtype="PCM_16")
    print(name, len(out), "hits", [round(len(s)/R, 3) for s in out][:3])
hits("fs_rod_knock.ogg", 3.0, 25.0, 0.078, 6, 0.07, 120, "hit_knock")
hits("fs_bearing_knock.ogg", 0.2, 8.8, 0.154, 6, 0.06, 1500, "hit_tick")
hits("fs_bearing_knock.ogg", 0.2, 8.8, 0.154, 4, 0.05, 2500, "hit_ping", up=2.0)
