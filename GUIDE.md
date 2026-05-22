# Stable Audio 3 - Pinokio Launcher ガイド

Stable Audio 3 をローカル環境で動かすための Pinokio ランチャーです。テキストプロンプトから音楽・効果音を生成できます。

## 動作環境

| 項目 | Small (Music/SFX) | Medium |
|------|-------------------|--------|
| GPU | 不要 (CPU可) | NVIDIA CUDA + Flash Attention 2 |
| VRAM | GPU使用時 約1.7-2.4 GB | 約5.1-6.5 GB |
| RAM | 16 GB以上推奨 | 16 GB以上推奨 |
| 最大生成時間 | 120秒 | 380秒 |

## インストール

### Pinokio 経由（推奨）

1. Pinokio でこのリポジトリを登録
2. **Install** ボタンをクリック
3. 完了通知を待つ

### 手動インストール (uv)

```bash
# 上流リポジトリのクローン
git clone https://github.com/Stability-AI/stable-audio-3 app

# 依存パッケージのインストール
cd app
uv sync --extra ui --active

# NVIDIA GPU環境の場合はCUDA版PyTorchに差し替え
# Windows:
uv pip install torch==2.7.1 torchvision==0.22.1 torchaudio==2.7.1 \
  --index-url https://download.pytorch.org/whl/cu128 --force-reinstall --no-deps

# Linux:
uv pip install torch==2.7.1 torchvision==0.22.1 torchaudio==2.7.1 \
  --index-url https://download.pytorch.org/whl/cu128 --force-reinstall
```

## 起動方法

### Pinokio 経由

- **Start Small Music** - 音楽生成 (small-music)
- **Start Small SFX** - 効果音生成 (small-sfx)
- **Start Medium** - 高品質音楽生成 (NVIDIA GPU必須)

### 手動起動 (uv)

```bash
cd app

# Small Music モデルで起動
GRADIO_SERVER_NAME=127.0.0.1 \
  .venv/bin/python -u ../launch.py \
  --model small-music \
  --title "Stable Audio 3" \
  --default-prompt "lo-fi hip hop beat, 90 BPM"

# Small SFX モデルで起動
GRADIO_SERVER_NAME=127.0.0.1 \
  .venv/bin/python -u ../launch.py \
  --model small-sfx \
  --title "Stable Audio 3 SFX" \
  --default-prompt "cinematic whoosh impact"
```

起動後、ブラウザで `http://127.0.0.1:7860` を開きます。
初回起動時はモデルのダウンロード（数GB）が行われます。

## モデル一覧

| モデル名 | 用途 | Hugging Faceミラー | GPU要件 |
|----------|------|---------------------|---------|
| `small-music` | 音楽生成 | cocktailpeanut/stable-audio-3-small-music | 不要 |
| `small-sfx` | 効果音生成 | cocktailpeanut/stable-audio-3-small-sfx | 不要 |
| `medium` | 高品質音楽生成 | cocktailpeanut/stable-audio-3-medium | NVIDIA CUDA必須 |

## Web UI の機能

GradioベースのWeb UIには以下の機能があります：

- **Text-to-Audio** - テキストプロンプトから音声生成
- **Init Audio Editing** - 既存音声をベースに編集
- **Inpainting** - 音声の一部を再生成
- **Continuation** - 生成音声の延長
- **LoRA 読み込み** - カスタムLoRAモデルの適用
- **出力形式制御** - WAV等の形式選択

## プロンプト例

### 音楽生成 (small-music / medium)

```
lo-fi hip hop beat, 90 BPM
ambient piano with soft rain sounds, chill, 80 BPM
epic orchestral battle theme, dramatic strings, 140 BPM
jazz trio, upright bass, brushed drums, warm piano, swing feel
electronic synthwave, retro 80s, arpeggiated synth, 120 BPM
acoustic guitar fingerpicking, folk, gentle, pastoral
dark ambient drone, cinematic tension, slowly evolving
drum and bass, fast breakbeat, deep bass, 170 BPM
```

### 効果音生成 (small-sfx)

```
cinematic whoosh impact
thunder crack with heavy rain
footsteps on gravel, approaching
sword unsheathing, metallic ring
explosion, deep rumble, debris
door creaking open, old wooden door
alarm beeping, electronic, urgent
water dripping in a cave, echo
```

## API 利用

サーバー起動後、Gradio API経由でプログラマティックに音声生成できます。

### Python (gradio_client)

```python
from gradio_client import Client

client = Client("http://127.0.0.1:7860")
print(client.view_api())
```

### Python (直接モデル読み込み - HTTP不要)

```python
import stable_audio_3.model as model_module
import stable_audio_3.model_configs as model_configs
from stable_audio_3.model_configs import ModelConfig
from stable_audio_3 import StableAudioModel

# ミラーモデルの登録
config = ModelConfig(
    "cocktailpeanut/stable-audio-3-small-music",
    "model_config.json",
    "model.safetensors",
)
model_configs.models["small-music"] = config
model_configs.all_models["small-music"] = config
model_module.all_models = model_configs.all_models

# モデル読み込み & 生成
model = StableAudioModel.from_pretrained("small-music")
audio = model.generate(
    prompt="lo-fi hip hop beat, 90 BPM",
    duration=30,
)
```

### cURL

```bash
# APIスキーマ確認
curl http://127.0.0.1:7860/gradio_api/info

# 生成リクエスト（スキーマに従ってペイロードを構築）
curl -X POST http://127.0.0.1:7860/gradio_api/call/generate \
  -H "Content-Type: application/json" \
  -d '{"data": ["lo-fi hip hop beat, 90 BPM", 30]}'
```

### JavaScript

```javascript
const base = "http://127.0.0.1:7860";
const info = await fetch(`${base}/gradio_api/info`).then(res => res.json());
console.log(info.named_endpoints || info);
```

## 応用例

### 1. バッチ生成 - 複数プロンプトを一括処理

```python
from gradio_client import Client

client = Client("http://127.0.0.1:7860")

prompts = [
    ("calm ocean waves, seagulls, morning", "ambient_ocean"),
    ("busy city street, traffic, crowd chatter", "city_noise"),
    ("forest birdsong, wind through trees", "forest"),
]

for prompt, name in prompts:
    result = client.predict(prompt, api_name="/generate")
    print(f"Generated: {name}")
```

### 2. BGM自動生成 - ゲーム/動画用

```
fantasy RPG town theme, lute melody, warm, peaceful, 100 BPM
sci-fi exploration, ambient pads, mysterious, slow tempo
boss battle, intense orchestral, brass, percussion, 160 BPM
game over jingle, sad, descending melody
victory fanfare, triumphant, brass and strings
```

### 3. ポッドキャスト/動画の効果音作成

```
podcast intro jingle, upbeat, electronic, 5 seconds
transition whoosh, soft, modern
notification ding, pleasant, clean
dramatic reveal stinger, rising tension to impact
```

### 4. サウンドデザイン - 映画/アニメ用

```
spaceship engine hum, low frequency, vibrating
magical spell casting, shimmering, ethereal
footsteps in snow, crunching, slow pace
robot voice processing, digital glitch
```

### 5. 音楽制作のアイデア出し

異なるジャンルやテンポでアイデアを量産：

```
boombap hip hop, vinyl crackle, dusty drums, 90 BPM
liquid drum and bass, smooth bassline, atmospheric, 174 BPM
deep house, warm bass, pad chords, 124 BPM
techno, driving kick, minimal, dark, 132 BPM
bossa nova, nylon guitar, soft percussion, breezy
```

## 環境変数

| 変数名 | デフォルト | 説明 |
|--------|-----------|------|
| `GRADIO_SERVER_NAME` | `127.0.0.1` | サーバーのバインドアドレス |
| `SA3_SMALL_MUSIC_REPO` | `cocktailpeanut/stable-audio-3-small-music` | Small MusicモデルのHFリポジトリ |
| `SA3_SMALL_SFX_REPO` | `cocktailpeanut/stable-audio-3-small-sfx` | Small SFXモデルのHFリポジトリ |
| `SA3_MEDIUM_REPO` | `cocktailpeanut/stable-audio-3-medium` | MediumモデルのHFリポジトリ |

## 品質を上げる Tips

### モデルの選択

| シーン | 推奨モデル | 理由 |
|--------|-----------|------|
| 音楽の試聴・アイデア出し | `small-music` | 高速、GPU不要 |
| 効果音・環境音 | `small-sfx` | 短い音響に最適化 |
| 最終品質の音楽出力 | `medium` | 品質最高、長尺対応（NVIDIA CUDA必須） |

Medium が使える環境なら常に Medium が最良。Small は素早い試行に徹する。

### プロンプトの書き方

**ダメな例:**
```
lo-fi beat
```

**良い例:**
```
lo-fi hip hop beat, dusty vinyl crackle, mellow piano chords,
soft kick drum, tape saturation, warm, 90 BPM
```

コツ:
- **ジャンル** を冒頭に明記（hip hop, ambient, orchestral...）
- **楽器** を列挙（piano, synth pad, upright bass...）
- **テンポ (BPM)** を指定する
- **質感・雰囲気** を形容詞で補強（warm, dark, ethereal, gritty...）
- **エフェクト** を含める（reverb, delay, distortion, tape saturation...）

### 機能を組み合わせるワークフロー

1. **Text-to-Audio でベース生成** → 全体の方向性を決める
2. **Inpainting で部分的に修正** → 気に入らない区間だけ再生成
3. **Continuation で延長** → 短い良いテイクを長尺に拡張
4. **Init Audio Editing で微調整** → 既存音声を入力に変化を加える

この順序で進めると、少ない試行回数で満足度の高い結果に到達しやすい。

### LoRA で特定ジャンルに特化

`pyproject.toml` に `lora` オプション依存関係が定義されており、LoRA 学習が可能:

```bash
uv sync --extra lora
```

自分の楽曲コレクションや好みのジャンルで LoRA を学習させると、生成の一貫性が大幅に向上する。コミュニティ公開の LoRA を読み込むだけでも効果的。Web UI の LoRA 読み込み機能から適用できる。

### 生成パラメータの調整

- **duration（秒数）** — 必要最低限に。長すぎると後半の品質が落ちやすい
- **guidance scale** — 高すぎると不自然、低すぎるとプロンプト無視。まずデフォルトから始めて微調整
- **seed の固定** — 良い結果が出たら seed を記録。再現性のあるワークフローが組める

### CPU環境での最適化

Small モデルを CPU で動かす場合:
- **duration を短く** — 30秒以内を推奨。長いと生成時間が実用的でなくなる
- **並列起動しない** — メモリ不足を避けるため、同時に1セッションのみ
- **RAM 16GB 以上** — 最低要件。32GB あれば快適

### 実践的な品質向上パイプライン例

```
[1] small-music で短いプロンプトを何度か試す（10〜20秒）
         ↓ 良い方向性を見つけたら
[2] プロンプトを詳細化して再度生成（30秒）
         ↓ 大枠が満足なら
[3] Inpainting で気になる区間を修正
         ↓ 全体が良ければ
[4] Continuation で延長して完成度を上げる
         ↓ さらに追求するなら
[5] medium で同じプロンプトを再生成（GPU環境がある場合）
```

## トラブルシューティング

### CUDA互換性エラー

```
NVIDIA GeForce RTX 50xx with CUDA capability sm_12x is not compatible
```

PyTorchが新しいGPUアーキテクチャに未対応の場合、SmallモデルはCPUで動作します。Mediumモデルは対応版PyTorchのリリースをお待ちください。

### モデルのダウンロードが遅い

初回起動時に数GBのモデルがダウンロードされます。HF_TOKENを設定するとダウンロード速度が向上します：

```bash
export HF_TOKEN=your_token_here
```

### メモリ不足

SmallモデルはCPU環境で16GB RAM以上を推奨します。より少ないRAMでは生成時間が長くなります。

### リセット

インストール済みのアプリを削除して最初からやり直す場合：

```bash
rm -rf app/
```

Pinokioの **Reset** ボタンでも同等の操作が可能です。
