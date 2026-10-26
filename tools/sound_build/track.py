import numpy as np, soundfile as sf
from scipy.signal import stft, resample_poly

def load(path, t0=0, t1=None, mono=True):
    info = sf.info(path); sr = info.samplerate
    x, _ = sf.read(path, start=int(t0*sr), stop=None if t1 is None else int(t1*sr), always_2d=True)
    return (x.mean(axis=1) if mono else x), sr

def track(x, sr, fmin, fmax, hop=0.01, win=0.3, orders=(1, 2, 3, 4), weights=(1.0, 0.8, 0.8, 0.5), jump=1.5):
    """Отслеживает частоту вспышек (2-й порядок) по сумме гармоник с Витерби."""
    q = max(1, int(sr // 2400)); d = resample_poly(x, 1, q); r = sr / q
    nper = int(r*win); f, t, Z = stft(d, r, nperseg=nper, noverlap=nper-int(r*hop), nfft=1 << (nper*8).bit_length())
    L = np.log(np.abs(Z) + 1e-9)
    cand = np.arange(fmin, fmax, 0.25)
    S = np.zeros((len(cand), L.shape[1]))
    for o, w in zip(orders, weights):
        idx = np.clip(np.round(cand*o/(f[1]-f[0])).astype(int), 0, len(f)-1)
        S += w * L[idx, :]
    S -= S.mean(axis=0, keepdims=True)
    # Витерби: штраф за скачок частоты
    n = len(cand); T = S.shape[1]; step = cand[1]-cand[0]
    maxj = int(jump/step)
    acc = S[:, 0].copy(); back = np.zeros((n, T), dtype=np.int32)
    for k in range(1, T):
        best = np.full(n, -1e18); arg = np.zeros(n, dtype=np.int32)
        for dj in range(-maxj, maxj+1):
            sh = np.roll(acc, dj) - 0.02*abs(dj)
            if dj > 0: sh[:dj] = -1e18
            elif dj < 0: sh[dj:] = -1e18
            m = sh > best; best[m] = sh[m]; arg[m] = (np.arange(n) - dj)[m]
        acc = best + S[:, k]; back[:, k] = arg
    path = np.zeros(T, dtype=np.int32); path[-1] = np.argmax(acc)
    for k in range(T-1, 0, -1): path[k-1] = back[path[k], k]
    return t, cand[path]

def dechirp(x, sr, tt, ff, f_target):
    """Переводит участок с меняющимися оборотами в постоянную частоту f_target."""
    ts = np.arange(len(x)) / sr
    fi = np.interp(ts, tt, ff)
    phase = np.cumsum(fi) / sr          # число вспышек от начала
    n_out = int(phase[-1] / f_target * sr)
    want = np.arange(n_out) * f_target / sr
    src = np.interp(want, phase, ts) * sr
    i = np.clip(src.astype(int), 0, len(x)-2); fr = src - i
    if x.ndim == 1: return x[i]*(1-fr) + x[i+1]*fr
    return x[i]*(1-fr)[:, None] + x[i+1]*fr[:, None]

def make_loop(y, sr, f, cycles=None, xfade=0.08):
    """Бесшовная петля длиной в целое число вспышек с перекрёстным затуханием."""
    per = sr / f
    if cycles is None: cycles = int((len(y) - xfade*sr) / per)
    L = int(round(cycles * per)); X = int(xfade*sr)
    body = y[:L].copy(); tail = y[L:L+X]
    w = np.sin(np.linspace(0, np.pi/2, X))**2
    body[:X] = body[:X]*w + tail*(1-w)
    return body

def norm(y, rms_db):
    r = np.sqrt(np.mean(y**2)); return y * (10**(rms_db/20) / max(r, 1e-9))

def hp(y, sr, fc=25):
    from scipy.signal import butter, sosfilt
    return sosfilt(butter(2, fc, "highpass", fs=sr, output="sos"), y)
