# Stable Audio 3 Pinokio ランチャー

このランチャーは、公開ミラーモデルを使用して [Stable Audio 3](https://github.com/Stability-AI/stable-audio-3) をインストール・実行します。

- `small-music`: CPU対応の音楽生成、最大120秒、`cocktailpeanut/stable-audio-3-small-music` から読み込み。
- `small-sfx`: CPU対応の効果音生成、最大120秒、`cocktailpeanut/stable-audio-3-small-sfx` から読み込み。
- `medium`: 高品質な音楽生成、最大380秒、`cocktailpeanut/stable-audio-3-medium` から読み込み。

smallモデルは最も幅広い環境で動作します。`medium` は現在の Gradio/PyTorch の構成が CUDA と Flash Attention 2 を必要とするため、NVIDIA搭載の Windows および Linux マシンでのみ Pinokio メニューに表示されます。アップストリームの報告によると、`medium` は約 5.1〜6.5 GB のピークVRAMを必要とし、smallモデルはGPU不要で、H200クラスGPUで実行した場合でも約 1.7〜2.4 GB のピークVRAMを使用します。CPU環境では、smallモデルを快適に利用するために最低 16 GB のシステムRAMを推奨します。

## インストール

Pinokioで **Install** をクリックします。インストーラーはアップストリームのリポジトリを `app/` にクローンし、以下を実行します。

```bash
uv sync --extra ui --active
```

NVIDIA搭載の Windows および Linux マシンでは、インストーラーが続いてランチャー `torch.js` ヘルパーを実行し、CPU専用PyTorchをCUDA版PyTorchに置き換え、対応するプリビルドFlash Attentionホイールをインストールします。macOS および CPU専用環境では、アップストリームの `uv sync` ルートがそのまま使用されます。

ランチャーは公開Hugging Faceミラーを使用するため、`HF_TOKEN` の入力は求められません。初回起動時に選択したモデルとそのT5Gemmaテキストエンコーダーのファイルが、通常のHugging Faceキャッシュにダウンロードされます。以降の起動ではキャッシュされたファイルが再利用されます。Mediumミラーはキャッシュオーバーヘッドを除いて約 10 GB です。

## 使い方

インストール完了後:

1. `small-music` を起動するには **Start Small Music** をクリックします（`cocktailpeanut/stable-audio-3-small-music`）。
2. `small-sfx` を起動するには **Start Small SFX** をクリックします（`cocktailpeanut/stable-audio-3-small-sfx`）。
3. NVIDIA搭載の Windows または Linux では、**Start Medium** をクリックして `medium` を起動します（`cocktailpeanut/stable-audio-3-medium`）。
4. GradioがローカルURLを出力すると、Pinokioが **Open Web UI** を開きます。

ランチャーはGradioの公開共有リンクを無効化しているため、起動時に公開されるのはローカル `127.0.0.1` のWeb UIのみです。

生成されたファイルはGradio UIを通じて返されます。アップストリームのインターフェースは、テキストからオーディオ生成、初期オーディオ編集、インペイント、コンティニュエーション、起動時のLoRA読み込み、出力フォーマット制御にも対応しています。

## API

Stable Audio 3 はWeb UIの起動後にGradio APIを公開します。アプリを開き、`/gradio_api/info` にアクセスすると、インストール済みのGradioバージョンに対応する正確なスキーマを確認できます。

### Python

```python
from gradio_client import Client

client = Client("http://127.0.0.1:7860")
print(client.view_api())
```

HTTPを使わずPythonから直接利用する場合は、読み込み前に同じミラーを登録します。

```python
import stable_audio_3.model as model_module
import stable_audio_3.model_configs as model_configs
from stable_audio_3.model_configs import ModelConfig
from stable_audio_3 import StableAudioModel

config = ModelConfig(
    "cocktailpeanut/stable-audio-3-small-music",
    "model_config.json",
    "model.safetensors",
)
model_configs.models["small-music"] = config
model_configs.all_models["small-music"] = config
model_module.all_models = model_configs.all_models

model = StableAudioModel.from_pretrained("small-music")
audio = model.generate(
    prompt="lo-fi hip hop beat, 90 BPM",
    duration=30,
)
```

Mediumの場合は、`cocktailpeanut/stable-audio-3-medium` を `medium` モデル名で登録し、Flash Attentionが利用可能なNVIDIA CUDAマシンで `StableAudioModel.from_pretrained("medium")` を読み込んでください。

### JavaScript

```javascript
const base = "http://127.0.0.1:7860";
const info = await fetch(`${base}/gradio_api/info`).then((res) => res.json());
console.log(info.named_endpoints || info);
```

### Curl

```bash
curl http://127.0.0.1:7860/gradio_api/info
```

生成エンドポイントはアップストリームアプリにより `generate` という名前で公開されています。インストール済みのGradioバージョンに対応するスキーマを `/gradio_api/info` で取得し、そのスキーマに従ってデータペイロードを送信してください。
