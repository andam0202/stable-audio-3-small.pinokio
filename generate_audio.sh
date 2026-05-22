#!/bin/bash
# ================================================
# orusuban - GBA風サウンドジェネレーター
# エッチな日常系ビジュアルノベル用 SE & BGM
#
# 必要環境: python3, ffmpeg
# 出力先: assets/audio/bgm/, assets/audio/sfx/
# ================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUT_DIR="${SCRIPT_DIR}/data/orusuban1/output"
SE_DIR="${OUT_DIR}/sfx"
BGM_DIR="${OUT_DIR}/bgm"

mkdir -p "${SE_DIR}/ui" "${SE_DIR}/character" "${SE_DIR}/environment" "${SE_DIR}/jingle" "${BGM_DIR}" "${SCRIPT_DIR}/data/input"

echo "=== orusuban GBA風サウンドジェネレーター ==="
echo ""

command -v python3 >/dev/null 2>&1 || { echo "エラー: python3 が必要です"; exit 1; }
command -v ffmpeg >/dev/null 2>&1 || { echo "エラー: ffmpeg が必要です"; exit 1; }

python3 << 'PYEOF'
import wave, struct, math, random, os

SAMPLE_RATE = 22050  # GBA風サンプルレート

# ── 音階定義 ──────────────────────────────────────
NOTE_FREQ = {}
for octave in range(1, 8):
    for i, name in enumerate(['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B']):
        midi = (octave + 1) * 12 + i
        NOTE_FREQ[f"{name}{octave}"] = 440.0 * (2.0 ** ((midi - 69) / 12.0))

def freq(note):
    return NOTE_FREQ.get(note, 0.0)

# ── 波形生成 ──────────────────────────────────────
def gen_square(f, dur, vol=0.5, sr=SAMPLE_RATE, duty=0.5):
    n = int(sr * dur)
    if f <= 0: return [0.0] * n
    buf = []
    for i in range(n):
        t = i / sr
        phase = (f * t) % 1.0
        buf.append(vol if phase < duty else -vol)
    return buf

def gen_triangle(f, dur, vol=0.5, sr=SAMPLE_RATE):
    n = int(sr * dur)
    if f <= 0: return [0.0] * n
    buf = []
    for i in range(n):
        t = i / sr
        phase = (f * t) % 1.0
        buf.append(vol * (4.0 * abs(phase - 0.5) - 1.0))
    return buf

def gen_sine(f, dur, vol=0.5, sr=SAMPLE_RATE):
    n = int(sr * dur)
    if f <= 0: return [0.0] * n
    buf = []
    for i in range(n):
        t = i / sr
        buf.append(vol * math.sin(2.0 * math.pi * f * t))
    return buf

def gen_saw(f, dur, vol=0.4, sr=SAMPLE_RATE):
    n = int(sr * dur)
    if f <= 0: return [0.0] * n
    buf = []
    for i in range(n):
        t = i / sr
        phase = (f * t) % 1.0
        buf.append(vol * (2.0 * phase - 1.0))
    return buf

def gen_noise(dur, vol=0.3, sr=SAMPLE_RATE, pitch=1.0):
    n = int(sr * dur)
    buf = []
    rng = random.Random(42)
    hold = 0
    val = 0
    period = max(1, int(sr / (8000 * pitch)))
    for i in range(n):
        if hold <= 0:
            val = rng.uniform(-1, 1) * vol
            hold = period
        buf.append(val)
        hold -= 1
    return buf

# ── エンベロープ & ユーティリティ ────────────────
def apply_env(buf, a=0.005, d=0.02, s=0.7, r=0.05, sr=SAMPLE_RATE):
    n = len(buf)
    out = [0.0] * n
    ai = int(a * sr)
    di = int(d * sr)
    ri = int(r * sr)
    for i in range(n):
        if i < ai:
            env = i / max(ai, 1)
        elif i < ai + di:
            env = 1.0 - (1.0 - s) * ((i - ai) / max(di, 1))
        elif i >= n - ri:
            env = s * ((n - i) / max(ri, 1))
        else:
            env = s
        out[i] = buf[i] * env
    return out

def apply_fadeout(buf, dur=0.3, sr=SAMPLE_RATE):
    n = len(buf)
    fi = int(dur * sr)
    for i in range(max(0, n - fi), n):
        buf[i] *= (n - i) / fi
    return buf

def silence(dur, sr=SAMPLE_RATE):
    return [0.0] * int(sr * dur)

def concat(*bufs):
    r = []
    for b in bufs:
        r.extend(b)
    return r

def mix(*bufs):
    ml = max(len(b) for b in bufs)
    out = [0.0] * ml
    for b in bufs:
        for i in range(len(b)):
            out[i] += b[i]
    mx = max(abs(v) for v in out) or 1.0
    return [v / mx * 0.85 for v in out]

def normalize(buf, vol=0.85):
    mx = max(abs(v) for v in buf) or 1.0
    return [v / mx * vol for v in buf]

# ── シーケンサー ──────────────────────────────────
def play_seq(notes, bpm, waveform='square', vol=0.5, duty=0.5, env=(0.005, 0.02, 0.7, 0.05)):
    beat = 60.0 / bpm
    buf = []
    gen = {
        'square': lambda f, d: gen_square(f, d, vol, duty=duty),
        'triangle': lambda f, d: gen_triangle(f, d, vol),
        'sine': lambda f, d: gen_sine(f, d, vol),
        'saw': lambda f, d: gen_saw(f, d, vol),
    }[waveform]
    for note_name, beats in notes:
        dur = beat * beats * 0.9
        if note_name == 'R':
            buf.extend(silence(beat * beats))
        else:
            f = freq(note_name)
            nbuf = gen(f, dur)
            nbuf = apply_env(nbuf, *env)
            nbuf.extend(silence(beat * beats * 0.1))
            buf.extend(nbuf)
    return buf

def play_drum(pattern, bpm, sr=SAMPLE_RATE):
    beat = 60.0 / bpm
    buf = []
    for kind, beats in pattern:
        dur = beat * beats
        if kind == 'R':
            buf.extend(silence(dur))
        elif kind == 'K':  # キック
            k = gen_sine(60, 0.1, 0.6)
            for i in range(len(k)):
                t = i / sr
                k[i] *= math.exp(-t * 30)
            k.extend(silence(dur - 0.1))
            buf.extend(k[:int(dur * sr)])
        elif kind == 'S':  # スネア
            s = gen_noise(0.1, 0.4)
            for i in range(len(s)):
                t = i / sr
                s[i] *= math.exp(-t * 25)
            s.extend(silence(dur - 0.1))
            buf.extend(s[:int(dur * sr)])
        elif kind == 'H':  # ハイハット
            h = gen_noise(0.04, 0.2, pitch=2.0)
            for i in range(len(h)):
                t = i / sr
                h[i] *= math.exp(-t * 60)
            h.extend(silence(dur - 0.04))
            buf.extend(h[:int(dur * sr)])
    return buf

# ── 音声書き出し (一時WAV → OGG → WAV削除) ────────
import subprocess, tempfile

def write_wav(path, buf, sr=SAMPLE_RATE):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with wave.open(path, 'w') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        frames = b''
        for s in buf:
            v = max(-1.0, min(1.0, s))
            frames += struct.pack('<h', int(v * 32767))
        w.writeframes(frames)

def write_audio(path, buf, sr=SAMPLE_RATE):
    base, _ = os.path.splitext(path)
    ogg_path = base + '.ogg'
    os.makedirs(os.path.dirname(ogg_path), exist_ok=True)
    tmp = tempfile.NamedTemporaryFile(suffix='.wav', delete=False)
    tmp_name = tmp.name
    tmp.close()
    try:
        write_wav(tmp_name, buf, sr)
        subprocess.run([
            'ffmpeg', '-y', '-i', tmp_name,
            '-c:a', 'libvorbis', '-q:a', '3',
            '-ar', str(sr), '-ac', '1',
            ogg_path
        ], capture_output=True, check=True)
    finally:
        os.unlink(tmp_name)
    return ogg_path

# ── 出力パス ──────────────────────────────────────
SE = os.environ.get('SE_DIR', '')
BGM = os.environ.get('BGM_DIR', '')
if not SE or not BGM:
    SE = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'data', 'output', 'sfx')
    BGM = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'data', 'output', 'bgm')

print("── SE生成 ──")

# ═══════════════════════════════════════════════════
# SE - UI系
# ═══════════════════════════════════════════════════

# テキスト送り音
b = gen_square(800, 0.03, 0.3, duty=0.25)
b = apply_env(b, 0.001, 0.005, 0.5, 0.02)
write_audio(f"{SE}/ui/text_advance.ogg", b)
print("  text_advance.ogg")

# カーソル移動
b = gen_square(660, 0.025, 0.25, duty=0.5)
b = apply_env(b, 0.001, 0.005, 0.4, 0.015)
write_audio(f"{SE}/ui/cursor.ogg", b)
print("  cursor.ogg")

# 決定音
b1 = gen_square(880, 0.06, 0.3, duty=0.5)
b2 = gen_square(1100, 0.08, 0.25, duty=0.5)
b1 = apply_env(b1, 0.003, 0.01, 0.6, 0.03)
b2 = apply_env(b2, 0.003, 0.01, 0.6, 0.04)
b = concat(b1, b2)
write_audio(f"{SE}/ui/select.ogg", b)
print("  select.ogg")

# キャンセル音
b1 = gen_square(440, 0.06, 0.3, duty=0.5)
b2 = gen_square(330, 0.08, 0.25, duty=0.5)
b1 = apply_env(b1, 0.003, 0.01, 0.6, 0.03)
b2 = apply_env(b2, 0.003, 0.01, 0.6, 0.04)
b = concat(b1, b2)
write_audio(f"{SE}/ui/cancel.ogg", b)
print("  cancel.ogg")

# セーブ
b1 = gen_square(523, 0.1, 0.3)
b2 = gen_square(659, 0.1, 0.3)
b3 = gen_square(784, 0.15, 0.3)
for x in [b1, b2, b3]:
    apply_env(x, 0.005, 0.02, 0.7, 0.05)
b = concat(b1, b2, b3)
write_audio(f"{SE}/ui/save.ogg", b)
print("  save.ogg")

# ロード
b1 = gen_square(784, 0.1, 0.3)
b2 = gen_square(659, 0.1, 0.3)
b3 = gen_square(523, 0.15, 0.3)
for x in [b1, b2, b3]:
    apply_env(x, 0.005, 0.02, 0.7, 0.05)
b = concat(b1, b2, b3)
write_audio(f"{SE}/ui/load.ogg", b)
print("  load.ogg")

# 選択肢出現
b = gen_triangle(440, 0.15, 0.3)
b = apply_env(b, 0.01, 0.03, 0.6, 0.05)
write_audio(f"{SE}/ui/choice_appear.ogg", b)
print("  choice_appear.ogg")

# 画面遷移
n = int(SAMPLE_RATE * 0.4)
b = []
for i in range(n):
    t = i / SAMPLE_RATE
    f = 200 + 1500 * (t / 0.4)
    v = 0.2 * math.sin(2 * math.pi * f * t) * (1 - t / 0.4)
    b.append(v)
write_audio(f"{SE}/ui/transition.ogg", b)
print("  transition.ogg")

# オートモード切替
b1 = gen_square(660, 0.04, 0.2, duty=0.25)
b2 = gen_square(880, 0.04, 0.2, duty=0.25)
b1 = apply_env(b1, 0.002, 0.01, 0.5, 0.02)
b2 = apply_env(b2, 0.002, 0.01, 0.5, 0.02)
b = concat(b1, b2)
write_audio(f"{SE}/ui/auto_toggle.ogg", b)
print("  auto_toggle.ogg")

print("")
print("── SE生成 (キャラクター・環境) ──")

# ═══════════════════════════════════════════════════
# SE - キャラクター系
# ═══════════════════════════════════════════════════

# ドキドキ (心臓の鼓動)
beat_buf = []
for _ in range(4):
    b1 = gen_sine(50, 0.12, 0.5)
    b2 = gen_sine(40, 0.08, 0.35)
    for i in range(len(b1)):
        t = i / SAMPLE_RATE
        b1[i] *= math.exp(-t * 12)
    for i in range(len(b2)):
        t = i / SAMPLE_RATE
        b2[i] *= math.exp(-t * 15)
    beat_buf.extend(b1)
    beat_buf.extend(silence(0.1))
    beat_buf.extend(b2)
    beat_buf.extend(silence(0.25))
write_audio(f"{SE}/character/heartbeat.ogg", beat_buf)
print("  heartbeat.ogg")

# 息を呑む
n = int(SAMPLE_RATE * 0.3)
b = []
for i in range(n):
    t = i / SAMPLE_RATE
    noise = random.random() * 2 - 1
    env = math.sin(math.pi * t / 0.3) * 0.15
    b.append(noise * env)
write_audio(f"{SE}/character/gasp.ogg", b)
print("  gasp.ogg")

# ため息
n = int(SAMPLE_RATE * 0.6)
b = []
for i in range(n):
    t = i / SAMPLE_RATE
    noise = random.random() * 2 - 1
    env = 0.15 * (1 - t / 0.6) ** 2
    f = 300 + 200 * (1 - t / 0.6)
    b.append(noise * env + 0.05 * math.sin(2 * math.pi * f * t) * env)
write_audio(f"{SE}/character/sigh.ogg", b)
print("  sigh.ogg")

# 衣擦れ
n = int(SAMPLE_RATE * 0.25)
b = []
rng = random.Random(123)
for i in range(n):
    t = i / SAMPLE_RATE
    noise = rng.random() * 2 - 1
    env = math.sin(math.pi * t / 0.25) * 0.12
    b.append(noise * env)
write_audio(f"{SE}/character/rustle.ogg", b)
print("  rustle.ogg")

# 足音 (室内)
steps = []
for _ in range(3):
    s = gen_noise(0.08, 0.25, pitch=0.8)
    for i in range(len(s)):
        t = i / SAMPLE_RATE
        s[i] *= math.exp(-t * 30)
    steps.extend(s)
    steps.extend(silence(0.35))
write_audio(f"{SE}/character/footstep_indoor.ogg", steps)
print("  footstep_indoor.ogg")

# ═══════════════════════════════════════════════════
# SE - 環境系
# ═══════════════════════════════════════════════════

# ドアを開ける
n = int(SAMPLE_RATE * 0.5)
b = []
for i in range(n):
    t = i / SAMPLE_RATE
    noise = random.random() * 2 - 1
    creak = math.sin(2 * math.pi * (120 + 80 * t) * t) * 0.15
    env = (1 - t / 0.5) ** 1.5
    b.append((noise * 0.2 + creak) * env)
write_audio(f"{SE}/environment/door_open.ogg", b)
print("  door_open.ogg")

# ドアを閉める
n = int(SAMPLE_RATE * 0.35)
b = []
for i in range(n):
    t = i / SAMPLE_RATE
    noise = random.random() * 2 - 1
    thud = math.sin(2 * math.pi * 60 * t) * 0.3
    env = math.exp(-t * 8)
    if t < 0.02:
        b.append((noise * 0.3 + thud) * env)
    else:
        b.append((noise * 0.1 + thud) * env)
write_audio(f"{SE}/environment/door_close.ogg", b)
print("  door_close.ogg")

# チャイム (来客)
chime = []
for note_f in [1318, 1568, 1318]:
    c = gen_sine(note_f, 0.3, 0.3)
    for i in range(len(c)):
        t = i / SAMPLE_RATE
        c[i] *= math.exp(-t * 4)
    chime.extend(c)
write_audio(f"{SE}/environment/chime.ogg", chime)
print("  chime.ogg")

# 電話着信 (GBA風)
phone = []
for rep in range(3):
    for note_f in [1046, 1318]:
        p = gen_square(note_f, 0.15, 0.25, duty=0.5)
        p = apply_env(p, 0.003, 0.01, 0.7, 0.03)
        phone.extend(p)
    phone.extend(silence(0.3))
write_audio(f"{SE}/environment/phone_ring.ogg", phone)
print("  phone_ring.ogg")

# メッセージ通知
b1 = gen_sine(1046, 0.06, 0.3)
b2 = gen_sine(1318, 0.1, 0.25)
b1 = apply_env(b1, 0.003, 0.01, 0.6, 0.03)
b2 = apply_env(b2, 0.003, 0.01, 0.6, 0.05)
b = concat(b1, b2)
write_audio(f"{SE}/environment/notification.ogg", b)
print("  notification.ogg")

# 風
n = int(SAMPLE_RATE * 2.0)
b = []
rng = random.Random(77)
for i in range(n):
    t = i / SAMPLE_RATE
    noise = rng.random() * 2 - 1
    env = 0.08 * (0.5 + 0.5 * math.sin(2 * math.pi * 0.3 * t))
    b.append(noise * env)
write_audio(f"{SE}/environment/wind.ogg", b)
print("  wind.ogg")

# 雨
n = int(SAMPLE_RATE * 2.0)
b = []
rng = random.Random(99)
for i in range(n):
    t = i / SAMPLE_RATE
    noise = rng.random() * 2 - 1
    env = 0.1 * (0.7 + 0.3 * math.sin(2 * math.pi * 0.2 * t))
    b.append(noise * env)
write_audio(f"{SE}/environment/rain.ogg", b)
print("  rain.ogg")

# 鐘の音 (学校)
bell = []
for note_f in [880, 1100, 880]:
    n = int(SAMPLE_RATE * 0.8)
    for i in range(n):
        t = i / SAMPLE_RATE
        bell.append(0.3 * math.sin(2 * math.pi * note_f * t) * math.exp(-t * 3))
    bell.extend(silence(0.05))
write_audio(f"{SE}/environment/school_bell.ogg", bell)
print("  school_bell.ogg")

print("")
print("── SE生成 (ジングル) ──")

# ═══════════════════════════════════════════════════
# SE - ジングル
# ═══════════════════════════════════════════════════

# 成功ジングル
b = play_seq([
    ('C5', 0.5), ('E5', 0.5), ('G5', 0.5), ('C6', 1.0)
], 160, 'square', 0.35, duty=0.5, env=(0.005, 0.02, 0.7, 0.08))
b = apply_fadeout(b, 0.15)
write_audio(f"{SE}/jingle/success.ogg", b)
print("  success.ogg")

# 失敗ジングル
b = play_seq([
    ('B4', 0.5), ('Bb4', 0.5), ('A4', 0.5), ('Ab4', 1.0)
], 140, 'square', 0.3, duty=0.5, env=(0.005, 0.02, 0.7, 0.08))
b = apply_fadeout(b, 0.15)
write_audio(f"{SE}/jingle/failure.ogg", b)
print("  failure.ogg")

# 甘い成功 (好感度アップ等)
b = play_seq([
    ('E5', 0.5), ('G5', 0.5), ('A5', 0.5), ('B5', 0.5), ('E6', 1.0)
], 140, 'sine', 0.3, env=(0.01, 0.03, 0.7, 0.1))
b = apply_fadeout(b, 0.2)
write_audio(f"{SE}/jingle/sweet_success.ogg", b)
print("  sweet_success.ogg")

# 不穏 (何かが起きる予感)
b = play_seq([
    ('E4', 1.0), ('F4', 0.5), ('E4', 0.5), ('D#4', 1.0)
], 100, 'triangle', 0.3, env=(0.01, 0.03, 0.6, 0.1))
b = apply_fadeout(b, 0.2)
write_audio(f"{SE}/jingle/ominous.ogg", b)
print("  ominous.ogg")

# 発見ジングル
b = play_seq([
    ('G5', 0.25), ('A5', 0.25), ('B5', 0.25), ('C6', 0.25),
    ('D6', 0.25), ('C6', 0.25), ('B5', 0.5)
], 180, 'square', 0.3, duty=0.25, env=(0.003, 0.01, 0.7, 0.05))
b = apply_fadeout(b, 0.1)
write_audio(f"{SE}/jingle/discovery.ogg", b)
print("  discovery.ogg")

# 幕開け
b1 = gen_triangle(262, 0.15, 0.3)
b2 = gen_triangle(330, 0.15, 0.3)
b3 = gen_triangle(392, 0.15, 0.3)
b4 = gen_triangle(523, 0.3, 0.35)
for x in [b1, b2, b3, b4]:
    apply_env(x, 0.005, 0.02, 0.7, 0.05)
b = concat(b1, b2, b3, b4)
write_audio(f"{SE}/jingle/curtain_open.ogg", b)
print("  curtain_open.ogg")

# 幕閉じ
b1 = gen_triangle(523, 0.15, 0.3)
b2 = gen_triangle(392, 0.15, 0.3)
b3 = gen_triangle(330, 0.15, 0.3)
b4 = gen_triangle(262, 0.3, 0.35)
for x in [b1, b2, b3, b4]:
    apply_env(x, 0.005, 0.02, 0.7, 0.05)
b = concat(b1, b2, b3, b4)
write_audio(f"{SE}/jingle/curtain_close.ogg", b)
print("  curtain_close.ogg")

print("")
print("── BGM生成 ──")

# ═══════════════════════════════════════════════════
# BGM - 各シーン
# ═══════════════════════════════════════════════════

def make_bgm(name, melody_notes, bass_notes, bpm, mel_wave='square', mel_duty=0.5,
             mel_vol=0.35, bass_vol=0.3, drum_pat=None, loops=2):
    mel = play_seq(melody_notes, bpm, mel_wave, mel_vol, duty=mel_duty,
                   env=(0.005, 0.02, 0.7, 0.04))
    bass = play_seq(bass_notes, bpm, 'triangle', bass_vol,
                    env=(0.008, 0.03, 0.7, 0.06))
    if drum_pat:
        drums = play_drum(drum_pat, bpm)
        mel_len = len(mel)
        bass_len = len(bass)
        drums_len = len(drums)
        max_len = max(mel_len, bass_len, drums_len)
        mel.extend([0.0] * (max_len - mel_len))
        bass.extend([0.0] * (max_len - bass_len))
        drums.extend([0.0] * (max_len - drums_len))
        # ループ
        mixed = mix(mel, bass, drums)
    else:
        max_len = max(len(mel), len(bass))
        mel.extend([0.0] * (max_len - len(mel)))
        bass.extend([0.0] * (max_len - len(bass)))
        mixed = mix(mel, bass)

    if loops > 1:
        mixed = mixed * loops
    mixed = apply_fadeout(mixed, 0.5)
    write_audio(f"{BGM}/{name}.ogg", mixed)
    dur = len(mixed) / SAMPLE_RATE
    print(f"  {name}.ogg ({dur:.1f}s)")

# ── 1. タイトル ──────────────────────────────────
# 明るくキャッチー、Cメジャー、140BPM
make_bgm('title',
    melody_notes=[
        ('C5',1),('E5',1),('G5',0.5),('A5',0.5),('G5',1),('E5',0.5),('C5',0.5),
        ('D5',1),('F5',1),('A5',0.5),('G5',0.5),('E5',1),('D5',1),
        ('C5',0.5),('D5',0.5),('E5',1),('G5',1),('A5',0.5),('G5',0.5),('E5',0.5),('D5',0.5),
        ('C5',1),('E5',0.5),('D5',0.5),('C5',2),
    ],
    bass_notes=[
        ('C3',2),('G3',2),('A3',2),('E3',2),
        ('F3',2),('C3',2),('G3',2),('C3',2),
    ],
    bpm=140, mel_duty=0.5,
    drum_pat=[
        ('K',1),('R',0.5),('H',0.5),('S',1),('H',0.5),('R',0.5),
        ('K',1),('H',0.5),('S',0.5),('H',1),('K',1),
        ('K',1),('R',0.5),('H',0.5),('S',1),('H',0.5),('R',0.5),
        ('K',0.5),('S',0.5),('K',0.5),('S',0.5),('K',1),('K',1),
    ],
    loops=2)

# ── 2. 日常・朝 ──────────────────────────────────
# のんびり明るい、Gメジャー、110BPM
make_bgm('daily_morning',
    melody_notes=[
        ('G4',1),('A4',0.5),('B4',0.5),('D5',1),('B4',0.5),('A4',0.5),
        ('G4',1),('E5',1),('D5',0.5),('B4',0.5),('A4',1),('G4',1),
        ('B4',0.5),('A4',0.5),('G4',1),('A4',0.5),('B4',0.5),('D5',1.5),
        ('B4',0.5),('A4',0.5),('G4',2),
    ],
    bass_notes=[
        ('G2',2),('D3',2),('E3',2),('C3',2),
        ('G2',2),('A2',2),('D3',2),('G2',2),
    ],
    bpm=110, mel_wave='square', mel_duty=0.25,
    drum_pat=[
        ('K',1),('R',1),('H',0.5),('R',0.5),('S',1),('R',1),
        ('K',1),('R',1),('H',0.5),('R',0.5),('K',1),('S',1),
    ],
    loops=2)

# ── 3. 日常・午後 ────────────────────────────────
# ゆったり、Fメジャー、85BPM
make_bgm('daily_afternoon',
    melody_notes=[
        ('C5',1.5),('A4',0.5),('F4',1),('G4',0.5),('A4',0.5),
        ('C5',1),('D5',0.5),('C5',0.5),('A4',1.5),('G4',0.5),
        ('F4',1),('G4',0.5),('A4',0.5),('C5',1),('A4',1),
        ('G4',0.5),('F4',0.5),('E4',0.5),('F4',0.5),('G4',1),('F4',2),
    ],
    bass_notes=[
        ('F3',2),('C3',2),('D3',2),('A2',2),
        ('Bb3',2),('F3',2),('C3',2),('F3',2),
    ],
    bpm=85, mel_wave='sine', mel_vol=0.3,
    loops=2)

# ── 4. 学校 ──────────────────────────────────────
# 活発な青春感、Dメジャー、130BPM
make_bgm('school',
    melody_notes=[
        ('D5',0.5),('E5',0.5),('F#5',1),('A5',0.5),('F#5',0.5),
        ('D5',0.5),('E5',0.5),('F#5',0.5),('E5',0.5),('D5',1),('C#5',1),
        ('E5',0.5),('F#5',0.5),('G5',1),('F#5',0.5),('E5',0.5),
        ('D5',0.5),('C#5',0.5),('D5',2),
    ],
    bass_notes=[
        ('D3',2),('A3',2),('G3',2),('A3',2),
        ('B3',2),('G3',2),('A3',2),('D3',2),
    ],
    bpm=130, mel_duty=0.75,
    drum_pat=[
        ('K',0.5),('H',0.5),('S',0.5),('H',0.5),('K',0.5),('H',0.5),('S',0.5),('H',0.5),
        ('K',0.5),('H',0.5),('S',0.5),('H',0.5),('K',0.5),('S',0.5),('K',0.5),('S',0.5),
    ],
    loops=2)

# ── 5. 甘い時間 ──────────────────────────────────
# 甘くロマンチック、Aマイナー→Cメジャー、95BPM
make_bgm('sweet_moment',
    melody_notes=[
        ('E5',1.5),('D5',0.5),('C5',1),('B4',0.5),('A4',0.5),
        ('C5',1),('D5',0.5),('E5',0.5),('C5',1.5),('E5',0.5),
        ('A5',1),('G5',0.5),('E5',0.5),('D5',1),('E5',1),
        ('C5',0.5),('B4',0.5),('A4',2),
    ],
    bass_notes=[
        ('A2',2),('E3',2),('F3',2),('C3',2),
        ('D3',2),('E3',2),('F3',2),('E3',2),
    ],
    bpm=95, mel_wave='sine', mel_vol=0.28,
    loops=2)

# ── 6. ドキドキ ──────────────────────────────────
# 緊張・期待、Eマイナー、115BPM
make_bgm('dokidoki',
    melody_notes=[
        ('B4',0.5),('E5',1),('D5',0.5),('B4',0.5),('A4',0.5),
        ('G4',1),('A4',0.5),('B4',0.5),('E5',1.5),
        ('D5',0.5),('C5',0.5),('B4',1),('A4',0.5),('G4',0.5),
        ('A4',0.5),('B4',0.5),('E5',2),
    ],
    bass_notes=[
        ('E3',2),('B2',2),('C3',2),('A2',2),
        ('E3',2),('D3',2),('C3',2),('B2',2),
    ],
    bpm=115, mel_wave='square', mel_duty=0.25, mel_vol=0.3,
    drum_pat=[
        ('K',1),('R',0.5),('H',0.5),('R',1),('K',0.5),('R',0.5),
        ('K',1),('R',0.5),('H',0.5),('R',1),('S',0.5),('R',0.5),
    ],
    loops=2)

# ── 7. いたずら ──────────────────────────────────
# 茶目っ気、ちょっとエッチな雰囲気、Bbメジャー、120BPM
make_bgm('mischief',
    melody_notes=[
        ('Bb4',0.5),('C5',0.5),('D5',0.5),('Eb5',0.5),('F5',0.5),('Eb5',0.5),('D5',0.5),('C5',0.5),
        ('Bb4',0.5),('D5',0.5),('F5',1),('Eb5',0.5),('D5',0.5),
        ('C5',0.5),('Eb5',0.5),('G5',0.5),('F5',0.5),('Eb5',0.5),('D5',0.5),('C5',1),
        ('D5',0.5),('C5',0.5),('Bb4',2),
    ],
    bass_notes=[
        ('Bb2',1),('R',0.5),('Bb2',0.5),('Eb3',1),('R',0.5),('Bb2',0.5),
        ('F3',1),('R',0.5),('F3',0.5),('Bb2',1),('R',0.5),('Bb2',0.5),
        ('Eb3',1),('R',0.5),('Eb3',0.5),('F3',1),('R',0.5),('F3',0.5),
        ('Eb3',1),('Bb2',1),
    ],
    bpm=120, mel_wave='square', mel_duty=0.75, mel_vol=0.32,
    drum_pat=[
        ('K',0.5),('H',0.5),('S',0.5),('H',0.5),('K',0.5),('H',0.5),('S',0.5),('H',0.5),
        ('K',0.5),('H',0.5),('S',0.5),('H',0.5),('K',0.5),('S',0.5),('K',0.5),('S',0.5),
    ],
    loops=2)

# ── 8. 夜・穏やか ────────────────────────────────
# 静かな夜、Ebメジャー、75BPM
make_bgm('night_calm',
    melody_notes=[
        ('Eb5',1.5),('D5',0.5),('C5',1),('Bb4',0.5),('Ab4',0.5),
        ('Bb4',1.5),('C5',0.5),('Eb5',2),
        ('F5',1.5),('Eb5',0.5),('D5',1),('C5',0.5),('Bb4',0.5),
        ('Ab4',1),('Bb4',1),('Eb5',2),
    ],
    bass_notes=[
        ('Eb3',2),('Bb2',2),('Ab2',2),('Bb2',2),
        ('Eb3',2),('C3',2),('F3',2),('Bb2',2),
    ],
    bpm=75, mel_wave='sine', mel_vol=0.25,
    loops=2)

# ── 9. 夜・センチメンタル ────────────────────────
# 感情の深い夜、Cマイナー、72BPM
make_bgm('night_sentimental',
    melody_notes=[
        ('G4',1.5),('Eb4',0.5),('F4',1),('G4',0.5),('C5',0.5),
        ('Bb4',1.5),('G4',0.5),('Ab4',2),
        ('Bb4',1),('C5',0.5),('Bb4',0.5),('Ab4',1),('G4',0.5),('F4',0.5),
        ('Eb4',1.5),('F4',0.5),('G4',2),
    ],
    bass_notes=[
        ('C3',2),('Ab2',2),('F2',2),('G2',2),
        ('Ab2',2),('Eb3',2),('F2',2),('G2',2),
    ],
    bpm=72, mel_wave='triangle', mel_vol=0.3,
    loops=2)

# ── 10. 切ない ────────────────────────────────────
# 悲しみ・後悔、Gマイナー、70BPM
make_bgm('sad',
    melody_notes=[
        ('G4',1.5),('Bb4',0.5),('A4',1),('G4',0.5),('F4',0.5),
        ('Eb4',1.5),('F4',0.5),('G4',2),
        ('Bb4',1),('A4',0.5),('G4',0.5),('F4',1),('Eb4',0.5),('D4',0.5),
        ('Eb4',1),('F4',1),('G4',2),
    ],
    bass_notes=[
        ('G2',2),('Eb3',2),('C3',2),('D3',2),
        ('Eb3',2),('Bb2',2),('C3',2),('D3',2),
    ],
    bpm=70, mel_wave='sine', mel_vol=0.25,
    loops=2)

# ── 11. クライマックス ───────────────────────────
# ドラマチック、Dマイナー、135BPM
make_bgm('climax',
    melody_notes=[
        ('A4',0.5),('D5',1),('F5',0.5),('E5',0.5),('D5',0.5),('C5',0.5),
        ('D5',1),('E5',0.5),('F5',0.5),('A5',1.5),
        ('G5',0.5),('F5',0.5),('E5',1),('D5',0.5),('C5',0.5),
        ('D5',0.5),('E5',0.5),('F5',0.5),('E5',0.5),('D5',1),('A4',1),
    ],
    bass_notes=[
        ('D3',2),('A2',2),('Bb2',2),('A2',2),
        ('G2',2),('A2',2),('Bb2',2),('A2',2),
    ],
    bpm=135, mel_wave='square', mel_duty=0.5, mel_vol=0.35,
    drum_pat=[
        ('K',0.5),('H',0.5),('K',0.5),('H',0.5),('S',0.5),('H',0.5),('K',0.5),('H',0.5),
        ('K',0.5),('H',0.5),('S',0.5),('H',0.5),('K',0.5),('S',0.5),('K',0.5),('S',0.5),
    ],
    loops=2)

# ── 12. エンディング ─────────────────────────────
# 余韻、Cメジャー、95BPM
make_bgm('ending',
    melody_notes=[
        ('E5',1.5),('D5',0.5),('C5',1),('E5',0.5),('G5',0.5),
        ('A5',1.5),('G5',0.5),('E5',2),
        ('D5',1),('E5',0.5),('G5',0.5),('A5',1),('G5',0.5),('E5',0.5),
        ('D5',1),('C5',1),('E5',2),
    ],
    bass_notes=[
        ('C3',2),('E3',2),('A2',2),('C3',2),
        ('F3',2),('C3',2),('G2',2),('C3',2),
    ],
    bpm=95, mel_wave='sine', mel_vol=0.28,
    loops=2)

# ── 13. お風呂 ────────────────────────────────────
# 湯気・リラックス、F#メジャー、80BPM
make_bgm('bathroom',
    melody_notes=[
        ('F#5',1.5),('E5',0.5),('D5',1),('C#5',0.5),('D5',0.5),
        ('E5',1.5),('F#5',0.5),('A5',2),
        ('G5',1),('F#5',0.5),('E5',0.5),('D5',1),('C#5',0.5),('D5',0.5),
        ('E5',1),('D5',1),('F#5',2),
    ],
    bass_notes=[
        ('F#3',2),('C#3',2),('D3',2),('A2',2),
        ('B2',2),('D3',2),('C#3',2),('F#3',2),
    ],
    bpm=80, mel_wave='sine', mel_vol=0.22,
    loops=2)

# ── 14. 秘密の時間 ────────────────────────────────
# こっそり・いたずら心、Aマイナー、105BPM
make_bgm('secret_time',
    melody_notes=[
        ('A4',0.5),('B4',0.5),('C5',0.5),('B4',0.5),('A4',0.5),('G4',0.5),('A4',0.5),('C5',0.5),
        ('E5',1),('D5',0.5),('C5',0.5),('B4',1),('A4',0.5),('G4',0.5),
        ('A4',0.5),('C5',0.5),('E5',0.5),('D5',0.5),('C5',1),('B4',0.5),('A4',0.5),
        ('G4',0.5),('A4',0.5),('B4',2),
    ],
    bass_notes=[
        ('A2',2),('E3',2),('F3',2),('C3',2),
        ('A2',2),('D3',2),('E3',2),('A2',2),
    ],
    bpm=105, mel_wave='square', mel_duty=0.25, mel_vol=0.3,
    drum_pat=[
        ('K',1),('R',1),('H',0.5),('R',0.5),('K',1),('H',0.5),('R',0.5),
        ('K',1),('R',0.5),('S',0.5),('H',0.5),('R',0.5),('K',1),('R',1),
    ],
    loops=2)

# ── 15. 素肌の温もり ────────────────────────────
# 亲密・温かい、Dbメジャー、78BPM
make_bgm('warm_skin',
    melody_notes=[
        ('Db5',1.5),('Eb5',0.5),('F5',1),('Eb5',0.5),('Db5',0.5),
        ('C5',1.5),('Db5',0.5),('Eb5',2),
        ('F5',1.5),('Eb5',0.5),('Db5',1),('C5',0.5),('Db5',0.5),
        ('Eb5',1),('Db5',1),('Ab4',2),
    ],
    bass_notes=[
        ('Db3',2),('Ab2',2),('Bb2',2),('Eb3',2),
        ('Db3',2),('F2',2),('Bb2',2),('Ab2',2),
    ],
    bpm=78, mel_wave='sine', mel_vol=0.24,
    loops=2)

# ── 16. 追憶 ──────────────────────────────────────
# ノスタルジア、Eメジャー、68BPM
make_bgm('nostalgia',
    melody_notes=[
        ('E5',2),('G#5',1),('F#5',0.5),('E5',0.5),
        ('D5',1.5),('C#5',0.5),('B4',2),
        ('C#5',1),('D5',0.5),('E5',0.5),('G#5',1.5),('F#5',0.5),
        ('E5',2),('B4',2),
    ],
    bass_notes=[
        ('E2',2),('B2',2),('A2',2),('E2',2),
        ('A2',2),('B2',2),('C3',2),('B2',2),
    ],
    bpm=68, mel_wave='sine', mel_vol=0.25,
    loops=2)

PYEOF

echo ""
echo "=== 完了 ==="
echo ""
echo "BGM一覧:"
echo "  title          - タイトル画面"
echo "  daily_morning  - 日常・朝ののんびり"
echo "  daily_afternoon- 日常・午後のゆったり"
echo "  school         - 学校・活発"
echo "  sweet_moment   - 甘い時間・ロマンチック"
echo "  dokidoki       - ドキドキ・緊張"
echo "  mischief       - いたずら・茶目っ気"
echo "  night_calm     - 夜・穏やか"
echo "  night_sentimental - 夜・センチメンタル"
echo "  sad            - 切ない・後悔"
echo "  climax         - クライマックス"
echo "  ending         - エンディング"
echo "  bathroom       - お風呂・リラックス"
echo "  secret_time    - 秘密の時間"
echo "  warm_skin      - 素肌の温もり"
echo "  nostalgia      - 追憶"
echo ""
echo "SE一覧:"
echo "  ui/       text_advance, cursor, select, cancel, save, load,"
echo "            choice_appear, transition, auto_toggle"
echo "  character/heartbeat, gasp, sigh, rustle, footstep_indoor"
echo "  environment/door_open, door_close, chime, phone_ring,"
echo "              notification, wind, rain, school_bell"
echo "  jingle/   success, failure, sweet_success, ominous,"
echo "            discovery, curtain_open, curtain_close"
