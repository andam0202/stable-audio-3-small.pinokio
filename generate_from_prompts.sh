#!/bin/bash
# ================================================
# orusuban - Stable Audio 3 プロンプト生成スクリプト
# .venv-genを使用してGradioサーバーを自動起動・停止する
#
# 使い方:
#   bash generate_from_prompts.sh                        # 全部生成 (small-music)
#   bash generate_from_prompts.sh --model medium bgm     # BGM全生成 (Medium)
#   bash generate_from_prompts.sh --model small-sfx sfx  # SE全生成
#   bash generate_from_prompts.sh bgm/title              # 個別生成
#   bash generate_from_prompts.sh --list                 # プロンプト一覧
#   bash generate_from_prompts.sh --no-server bgm        # 外部サーバー使用
# ================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="${SCRIPT_DIR}/app"
VENV_PYTHON="${APP_DIR}/.venv-gen/bin/python"
PROMPTS_FILE="${SCRIPT_DIR}/data/input/orusuban3.json"
OUTPUT_DIR="${SCRIPT_DIR}/data/output/orusuban3"
API_BASE="http://127.0.0.1:7860"

# ── 引数パース ────────────────────────────────────
MODEL=""
FILTER=""
NO_SERVER=false

while [ $# -gt 0 ]; do
    case "$1" in
        --model)  MODEL="$2"; shift 2 ;;
        --no-server) NO_SERVER=true; shift ;;
        --list|-l)
            echo "=== プロンプト一覧 ==="
            echo ""
            echo "BGM:"
            python3 -c "
import json
with open('${PROMPTS_FILE}') as f:
    data = json.load(f)
for item in data.get('bgm', []):
    print(f\"  bgm/{item['name']:20s} ({item['duration']}s) {item['prompt'][:60]}...\")
"
            echo ""
            echo "SFX:"
            python3 -c "
import json
with open('${PROMPTS_FILE}') as f:
    data = json.load(f)
for item in data.get('sfx', []):
    print(f\"  sfx/{item['name']:25s} ({item['duration']}s) {item['prompt'][:60]}...\")
"
            exit 0 ;;
        --help|-h)
            echo "使い方:"
            echo "  $0                                    全部生成"
            echo "  $0 --model medium bgm                 BGM全生成 (Medium)"
            echo "  $0 --model small-music bgm            BGM全生成"
            echo "  $0 --model small-sfx sfx              SE全生成"
            echo "  $0 bgm/title                          個別生成"
            echo "  $0 --list                             プロンプト一覧"
            echo "  $0 --no-server bgm                    外部サーバー使用時"
            echo "  $0 --help                             ヘルプ"
            exit 0 ;;
        *) FILTER="$1"; shift ;;
    esac
done

# ── 前提チェック ─────────────────────────────────
command -v ffmpeg >/dev/null 2>&1 || { echo "エラー: ffmpeg が必要です"; exit 1; }

if [ ! -f "$VENV_PYTHON" ]; then
    echo "エラー: $VENV_PYTHON が見つかりません"
    echo "  CLAUDE.md の「.venv-gen の初期構築」手順を実行してください"
    exit 1
fi

if [ ! -f "$PROMPTS_FILE" ]; then
    echo "エラー: $PROMPTS_FILE が見つかりません"
    exit 1
fi

# ── サーバー自動起動 ──────────────────────────────
SERVER_PID=""

if [ "$NO_SERVER" = false ]; then
    # 既に起動しているかチェック
    if curl -s "$API_BASE" > /dev/null 2>&1; then
        echo "既存のGradioサーバーを検出 ($API_BASE)"
    else
        LAUNCH_MODEL="${MODEL:-small-music}"
        echo "Gradioサーバーを起動中 (model=${LAUNCH_MODEL}) ..."
        cd "$APP_DIR"
        GRADIO_SERVER_NAME=127.0.0.1 $VENV_PYTHON ../launch.py \
            --model "$LAUNCH_MODEL" \
            --title "Stable Audio 3 ${LAUNCH_MODEL}" \
            > /tmp/sa3_gen_server.log 2>&1 &
        SERVER_PID=$!

        # 起動待ち (最大300秒)
        echo "モデルロード中..."
        for i in $(seq 1 75); do
            if curl -s "$API_BASE" > /dev/null 2>&1; then
                echo "サーバー準備完了"
                break
            fi
            if [ $i -eq 75 ]; then
                echo "エラー: サーバー起動タイムアウト"
                echo "ログ: /tmp/sa3_gen_server.log"
                kill $SERVER_PID 2>/dev/null
                exit 1
            fi
            sleep 4
        done
    fi
fi

# ── クリーンアップ ────────────────────────────────
cleanup() {
    if [ -n "$SERVER_PID" ]; then
        echo "サーバーを停止中..."
        kill $SERVER_PID 2>/dev/null || true
    fi
}
trap cleanup EXIT

# ── メイン処理 ───────────────────────────────────
$VENV_PYTHON << PYEOF
import json, os, sys, subprocess

API = "${API_BASE}"
PROMPTS = "${PROMPTS_FILE}"
OUT = "${OUTPUT_DIR}"
FILTER = "${FILTER}"
MODEL_OVERRIDE = "${MODEL}"

with open(PROMPTS) as f:
    data = json.load(f)

from gradio_client import Client

print(f"API接続: {API} ...")
try:
    client = Client(API, verbose=False)
    print("接続成功")
except Exception as e:
    print(f"エラー: {API} に接続できません")
    sys.exit(1)

# サポートするsamplerを確認
try:
    info = client.view_api(format="dict")
    gen_info = info.get("named_endpoints", {}).get("/generate", {})
    for p in gen_info.get("parameters", []):
        if "ampler" in p.get("label", ""):
            choices = p.get("type", {}).get("enum", [])
            if choices:
                sampler = choices[0]
                break
    else:
        sampler = "pingpong"
except:
    sampler = "pingpong"
print(f"sampler: {sampler}")
print("")

def generate_one(category, item):
    name = item["name"]
    key = f"{category}/{name}"
    prompt = item["prompt"]
    neg = item.get("negative_prompt", "")
    duration = item.get("duration", 10)
    steps = item.get("steps", 8)
    cfg = item.get("cfg_scale", 1.0)
    seed = item.get("seed", -1)

    # フィルタチェック
    if FILTER:
        if FILTER != category and FILTER != key:
            return

    out_dir = os.path.join(OUT, "bgm" if category == "bgm" else "sfx")
    if category == "sfx" and "/" in name:
        sub = os.path.dirname(name)
        out_dir = os.path.join(out_dir, sub)
    os.makedirs(out_dir, exist_ok=True)
    base_name = os.path.basename(name)
    # 常に _0001, _0002... と採番（ベース名直接は使わない）
    n = 1
    while True:
        candidate = os.path.join(out_dir, f"{base_name}_{n:04d}.ogg")
        if not os.path.exists(candidate):
            out_file = candidate
            break
        n += 1

    print(f"[{key}]")
    print(f"  prompt: {prompt[:70]}...")
    print(f"  duration={duration}s steps={steps} cfg={cfg} seed={seed}")

    try:
        result = client.predict(
            prompt, neg, duration, cfg, steps,
            0, seed, sampler,
            0, 0, 1, 0, 0, 0,
            "wav", "output.wav", True,
            None, 0.9, 0, 0, None,
            api_name="/generate"
        )
        if isinstance(result, (list, tuple)):
            wav_path = result[0] if len(result) > 0 else None
        else:
            wav_path = result

        if wav_path and os.path.exists(wav_path):
            subprocess.run([
                "ffmpeg", "-y", "-i", wav_path,
                "-c:a", "libvorbis", "-q:a", "3",
                "-ar", "22050", "-ac", "1",
                out_file
            ], capture_output=True, check=True)
            print(f"  -> {out_file}")
        else:
            print(f"  エラー: 生成結果が見つかりません")
    except Exception as e:
        print(f"  エラー: {e}")
    print("")

for item in data.get("bgm", []):
    generate_one("bgm", item)
for item in data.get("sfx", []):
    generate_one("sfx", item)

print("=== 完了 ===")
PYEOF
