# Stable Audio 3 LoRA 作成ガイド

LoRA (Low-Rank Adaptation) を使うと、ベースモデル全体を再学習せずに特定のスタイル・音色・ジャンルにモデルを適応できます。結果は 50〜200 MB の `.safetensors` ファイル1つになり、ベースモデルに重ねて使えます。

## 必要なもの

- NVIDIA CUDA GPU（VRAM 要件は下記）
- `lora` 追加依存のインストール
- 音声ファイル + テキストキャプションのペア

### VRAM 目安

| ベースモデル | 標準設定 | 省メモリ設定 (`--adapter_type lora-xs --base_precision bf16`) |
|-------------|---------|----------------------------------------------------------|
| `medium-base` | ~6.5 GB | ~5.5 GB |
| `small-music-base` / `small-sfx-base` | ~2.5 GB | ~2 GB |

---

## 学習データの準備

### データ量の目安

| 規模 | クリップ数 | 傾向 |
|------|-----------|------|
| 最小限 | 20〜50 | 方向性を示唆する程度。過学習に注意 |
| 推奨 | 100〜500 | 安定した結果。スタイル適応には十分 |
| 十分 | 500〜2000 | 高い再現性と汎化性 |
| 大規模 | 2000+ | ほぼフルファインチューニングに近い表現力 |

**重要なのは数より質**。キャプションの正確さと音声の品質が結果を左右します。

### データ形式

音声ファイルと同名の `.txt` ファイルをペアにして1つのフォルダに置きます。

```
my_data/
  track_001.wav       ← 音声（wav, flac, mp3, ogg 対応）
  track_001.txt       ← キャプション（テキスト）
  track_002.flac
  track_002.txt
  kick_01.wav
  kick_01.txt
```

### 対応音声形式

`.wav`, `.flac`, `.mp3`, `.ogg`, `.opus`, `.m4a`, `.aif`

### キャプションの書き方

`.txt` ファイルにその音声を説明するテキストを1行で書きます。

**例:**
```
lo-fi hip hop beat, dusty drums, mellow piano, tape hiss, 90 BPM
```

```
cinematic riser, orchestral strings, building tension, fast crescendo
```

**コツ:**
- **具体的に**: ジャンル、楽器、テンポ、質感をすべて書く
- **生成時のプロンプトと同じ形式** で書くと一貫性が高まる
- 短すぎるキャプション（"music" 等）は避ける
- 長すぎてもよい。10〜30単語が目安

### 音声ファイルの注意点

- **サンプリングレート**: 何でもよい（学習時に自動で44.1kHzにリサンプリングされる）
- **チャンネル**: モノラルでもステレオでもよい（自動でステレオ化される）
- **長さ**: 数秒〜380秒まで対応。長いファイルはランダムにクロップされる
- **品質**: ノイズが多い・歪んでいる音声は避ける
- **無音ファイル**: 自動でスキップされる

---

## 事前準備

### 依存パッケージのインストール

```bash
cd app
uv sync --extra lora
```

### 利用可能なベースモデル

LoRA学習には `-base` 付きのモデルを使います（蒸留後の推論用モデルでは不可）。

| ベースモデル名 | 説明 |
|---------------|------|
| `small-music-base` | 音楽生成ベース |
| `small-sfx-base` | 効果音生成ベース |
| `medium-base` | 高品質音楽生成ベース（CUDA必須） |

---

## 学習の実行

### 基本的なコマンド

```bash
cd app

uv run python scripts/train_lora.py \
  --model small-music-base \
  --data_dir ./my_data \
  --rank 16 \
  --adapter_type dora-rows \
  --steps 1000 \
  --save_dir ./lora_output
```

### 省メモリ設定（16GB GPU向け）

```bash
uv run python scripts/train_lora.py \
  --model medium-base \
  --data_dir ./my_data \
  --rank 16 \
  --adapter_type lora-xs \
  --base_precision bf16 \
  --steps 1000 \
  --save_dir ./lora_output
```

### 主な引数

| 引数 | デフォルト | 説明 |
|------|-----------|------|
| `--model` | `medium-base` | ベースモデル |
| `--data_dir` | (必須) | 音声+キャプションのフォルダ |
| `--rank` | `16` | LoRAランク。低いほど軽量、高いほど表現力が増す |
| `--adapter_type` | `dora-rows` | アダプタの種類（後述） |
| `--lr` | `1e-4` | 学習率 |
| `--steps` | `10000` | 学習ステップ数 |
| `--batch_size` | `1` | バッチサイズ |
| `--duration` | `380.0` | 最大クリップ長（秒） |
| `--save_dir` | `./lora_checkpoints` | 保存先 |
| `--checkpoint_every` | `500` | チェックポイント保存間隔（ステップ） |
| `--seed` | `42` | 乱数シード |
| `--lora_alpha` | (rankと同じ) | スケーリング係数 |
| `--dropout` | `0.0` | LoRA入力へのドロップアウト確率 |
| `--base_precision` | なし | 凍結重みの精度 (`bf16`, `fp16` 等) |
| `--num_workers` | `8` | データローダーのワーカー数 |
| `--logger` | `csv` | ロガー (`wandb`, `comet`, `csv`, `none`) |

### ステップ数の目安

| データ規模 | 推奨ステップ | 傾向 |
|-----------|-------------|------|
| 20〜50クリップ | 500〜1000 | 過学習しやすい。損失を監視する |
| 100〜500クリップ | 1000〜3000 | 安定した学習 |
| 500+クリップ | 3000〜10000 | 汎化性重視なら多めに |

## アダプタの種類

| アダプタ | 特徴 | 向いている用途 |
|---------|------|--------------|
| `dora-rows` (推奨) | 方向+大きさを独立に学習。汎化性が高い | ほとんどのケース |
| `lora` | 標準的なLoRA。シンプルで安定 | 表現力より安定性重視 |
| `dora-cols` | 列方向の大きさを学習 | 入力特徴への適応 |
| `bora` | 行方向+列方向の大きさを両方学習。最も表現力が高い | 大規模データ+高いVRAM |
| `lora-xs` | 学習パラメータが極めて少ない。省メモリ | VRAMが厳しい場合 |
| `dora-rows-xs` | lora-xs + 行方向の大きさ。省メモリかつ高品質 | VRAM制約下での推奨設定 |

---

## レイヤーフィルタリング

特定のレイヤーだけにLoRAを適用することで、VRAMを節約し、過学習を防げます。

### transformerレイヤーのみに適用

```bash
--include transformer.layers
```

### 最初の12層のみ

```bash
--include "layers[0-11]"
```

### seconds_total条件付けを除外（小規模データで推奨）

```bash
--exclude seconds_total
```

条件付け器が学習データの長さに過剰適合するのを防ぎます。

---

## 2段階学習（事前エンコード）

大規模データの場合、音声の潜在表現を事前にエンコードしておくと学習が高速になります。

### Step 1: データセットの事前エンコード

```bash
uv run python scripts/pre_encode_dataset.py \
  --model same-l \
  --data_dir ./my_data \
  --output_path ./latents_out
```

`--model` にはオートエンコーダを指定:
- `same-s` — smallモデル向け
- `same-l` — mediumモデル向け

### Step 2: 事前エンコード済みデータで学習

```bash
uv run python scripts/train_lora.py \
  --model medium-base \
  --encoded_dir ./latents_out \
  --save_dir ./lora_output
```

`--data_dir` の代わりに `--encoded_dir` を使います。

---

## 学習の再開

中断した場合は `--lora_checkpoint` で続きから再開できます。

```bash
uv run python scripts/train_lora.py \
  --model medium-base \
  --data_dir ./my_data \
  --lora_checkpoint ./lora_output/lora_step500.safetensors \
  --steps 2000 \
  --save_dir ./lora_output_continued
```

---

## 推論でのLoRA適用

### Gradio UIで使う

```bash
uv run python run_gradio.py \
  --model small-music \
  --lora-ckpt-path ./lora_output/lora_step1000.safetensors
```

複数のLoRAを同時に読み込むことも可能:

```bash
uv run python run_gradio.py \
  --model small-music \
  --lora-ckpt-path style_a.safetensors style_b.safetensors
```

### Gradio UIのLoRAコントロール

LoRA読み込み時、UIに以下のコントロールが追加されます:

- **Diffusion Transformer Strength** (0.0〜10.0): LoRAの影響度。0で無効、1.0が標準
- **Conditioner Strength** (0.0〜10.0): テキスト条件付けへのLoRA影響度
- **Interval** [min, max]: サンプリング過程のどの段階でLoRAを有効にするか
  - `[0.0, 1.0]` (デフォルト): 全工程で有効
  - `[0.0, 0.5]`: ノイズが少ない後半のみ有効（詳細に影響）
  - `[0.5, 1.0]`: ノイズが多い前半のみ有効（全体構造に影響）

### Python APIで使う

```python
from stable_audio_3.models.lora import set_lora_strength

# 強度を半分に
set_lora_strength(model, 0.5)

# 特定のLoRAだけ無効化（複数読み込み時）
set_lora_strength(model, 0.0, lora_index=1)
```

### Pinokioランチャーで使う

`launch.py` 経由で起動する場合、`--lora-ckpt-path` を追加で渡します。`start.js` を修正するか、直接コマンドを実行してください:

```bash
cd app
GRADIO_SERVER_NAME=127.0.0.1 \
  .venv/bin/python -u ../launch.py \
  --model small-music \
  --title "My Custom LoRA" \
  --default-prompt "lo-fi beat, 90 BPM" \
  --lora-ckpt-path ../lora_output/lora_step1000.safetensors
```

---

## トラブルシューティング

### 過学習（オーバーフィット）

症状: 学習データとほぼ同じ音声ばかり生成される

対策:
- ステップ数を減らす
- `--rank` を下げる（16 → 4〜8）
- `--dropout 0.1` を追加
- `--exclude seconds_total` を追加
- データを増やす

### 学習が進まない

症状: 損失が下がらない

対策:
- キャプションの品質を見直す（具体的に書けているか）
- 学習率を調整（`1e-4` → `5e-4` または `5e-5`）
- `--rank` を上げる（16 → 32）
- データの音質を確認する

### VRAM不足 (OOM)

対策:
- `--adapter_type lora-xs --base_precision bf16` を使う
- `--batch_size 1` にする
- `--include` でレイヤーを限定する
- `--duration` を短くする

### 学習が遅い

対策:
- 事前エンコード (`pre_encode_dataset.py`) を使う
- `--num_workers` を増やす（CPUコア数に合わせる）
- SSD上にデータを置く

---

## 実践ワークフロー例

### 例1: 特定ジャンルのLoRAを作る

```
# 1. データ準備
my_data/
  jazz_001.wav  / jazz_001.txt   ← "jazz piano trio, swinging, brush drums, 120 BPM"
  jazz_002.wav  / jazz_002.txt   ← "bebop, fast saxophone, walking bass, 200 BPM"
  ...（100曲程度）

# 2. 学習
uv run python scripts/train_lora.py \
  --model small-music-base \
  --data_dir ./my_data \
  --rank 16 \
  --adapter_type dora-rows \
  --steps 1500 \
  --save_dir ./jazz_lora

# 3. 確認（途中経過を500ステップごとにチェック）
uv run python run_gradio.py \
  --model small-music \
  --lora-ckpt-path ./jazz_lora/lora_step500.safetensors

# 4. 最適なステップを見つけたら本番運用
```

### 例2: 効果音ライブラリのLoRAを作る

```
# 1. データ準備（短い効果音を集める）
sfx_data/
  explosion_01.wav / explosion_01.txt  ← "massive explosion, deep rumble, debris"
  whoosh_01.wav    / whoosh_01.txt     ← "fast whoosh, air displacement"
  ...（50〜200個）

# 2. small-sfx-baseで学習
uv run python scripts/train_lora.py \
  --model small-sfx-base \
  --data_dir ./sfx_data \
  --rank 8 \
  --adapter_type lora-xs \
  --base_precision bf16 \
  --steps 800 \
  --duration 30 \
  --save_dir ./sfx_lora
```

### 例3: 既存LoRAをベースに追加学習

```
# 前回のLoRAから再開
uv run python scripts/train_lora.py \
  --model small-music-base \
  --data_dir ./additional_data \
  --lora_checkpoint ./lora_v1/lora_step1000.safetensors \
  --steps 2000 \
  --save_dir ./lora_v2
```
