# Stable Audio 3 Pinokio - プロジェクトガイド

## 仮想環境の使い分け

このリポジトリには **2つのvenv** があり、用途で使い分ける:

| venv | パス | 用途 | PyTorch | 備考 |
|---|---|---|---|---|
| `.venv` | `app/.venv/` | LoRA学習・開発用 | cu128 (RTX 5070 Ti向け) | ユーザーが管理 |
| `.venv-gen` | `app/.venv-gen/` | 音声生成（Gradioサーバー）用 | cu128 | generate_from_prompts.shが使用 |

**注意:** `.venv` はユーザーがLoRA学習用に管理しているため、`uv sync` 等で変更しないこと。

## スクリプト一覧

### `generate_audio.sh` — チップチューン生成（AI不要）
- Python波形合成でGBA風SE/BGMを生成
- OGGのみ出力
- `data/output/orusuban1/bgm/`, `data/output/orusuban1/sfx/` に出力

### `generate_from_prompts.sh` — Stable Audio 3 AI生成
- Gradio API経由でAI音声生成
- `data/input/orusuban1.json` のプロンプト定義を使用
- サーバーの自動起動・停止機能付き
- 既存ファイルの上書き防止（`_0001`, `_0002`... 自動採番）

```bash
# 使い方
bash generate_from_prompts.sh --model medium bgm       # BGM全生成 (Medium)
bash generate_from_prompts.sh --model small-music bgm   # BGM全生成 (small-music)
bash generate_from_prompts.sh --model small-sfx sfx     # SE全生成
bash generate_from_prompts.sh --model medium bgm/title  # 個別生成
bash generate_from_prompts.sh --list                    # プロンプト一覧
bash generate_from_prompts.sh --no-server bgm           # サーバー起動済みの時
```

## ディレクトリ構造

```
data/
  input/
    orusuban1.json       # GBA風ノベル用プロンプト
    stella_lace.json     # PSP SFアクション用プロンプト
  output/
    orusuban1/           # orusuban1出力
      bgm/*.ogg
      sfx/{ui,character,environment,jingle,touch,intimate}/*.ogg
    stella_lace/         # stella_lace出力
      bgm/*.ogg
      sfx/{ui,combat,lace,enemy,environment,jingle}/*.ogg
```

## 環境構築

### .venv-gen の初期構築
```bash
cd app
uv venv .venv-gen --python 3.10
.venv-gen/bin/pip install torch==2.7.1 torchaudio==2.7.1 --index-url https://download.pytorch.org/whl/cu128
.venv-gen/bin/pip install -e ".[ui]"
```

### .venv-gen の再構築（壊れた場合）
```bash
rm -rf app/.venv-gen
# 上記の初期構築手順を再実行
```

## ハードウェア情報

- GPU: NVIDIA RTX 5070 Ti (sm_120)
- CUDA 12.8対応のPyTorchが必要 (cu128)
- Mediumモデル: 約5-6GB VRAM
- Smallモデル: 約1.7-2.4GB VRAM、CPU fallback可
