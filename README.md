# Stable Audio 3 Pinokio Launcher

This launcher installs and runs [Stable Audio 3](https://github.com/Stability-AI/stable-audio-3) with public mirrored model copies:

- `small-music`: CPU-capable music generation, up to 120 seconds, loaded from `cocktailpeanut/stable-audio-3-small-music`.
- `small-sfx`: CPU-capable sound-effect generation, up to 120 seconds, loaded from `cocktailpeanut/stable-audio-3-small-sfx`.
- `medium`: higher-quality music generation, up to 380 seconds, loaded from `cocktailpeanut/stable-audio-3-medium`.

The small models are the broadest compatibility path. `medium` is shown in the Pinokio menu only on NVIDIA Windows and Linux machines because the current Gradio/PyTorch path requires CUDA and Flash Attention 2. Upstream reports roughly 5.1-6.5 GB peak VRAM for `medium`, while the small models need no GPU and use about 1.7-2.4 GB peak VRAM when run on H200-class GPU. On CPU, use at least 16 GB system RAM for a comfortable small-model experience.

## Install

Click **Install** in Pinokio. The installer clones the upstream repository into `app/` and runs:

```bash
uv sync --extra ui --active
```

On NVIDIA Windows and Linux machines, the installer then runs the launcher `torch.js` helper to replace CPU-only PyTorch with CUDA PyTorch and install a matching prebuilt Flash Attention wheel. macOS and CPU-only installs keep the upstream `uv sync` route unchanged.

The launcher uses public Hugging Face mirrors, so it does not prompt for `HF_TOKEN`. The first launch downloads the selected model and its T5Gemma text encoder files into the normal Hugging Face cache. Later launches reuse the cached files. The Medium mirror is about 10 GB before cache overhead.

## Use

After installation:

1. Click **Start Small Music** for `small-music` from `cocktailpeanut/stable-audio-3-small-music`.
2. Click **Start Small SFX** for `small-sfx` from `cocktailpeanut/stable-audio-3-small-sfx`.
3. On NVIDIA Windows or Linux, click **Start Medium** for `medium` from `cocktailpeanut/stable-audio-3-medium`.
4. Pinokio opens **Open Web UI** when Gradio prints the local URL.

The launcher disables Gradio public share links, so startup should only expose the local `127.0.0.1` Web UI.

Generated files are returned through the Gradio UI. The upstream interface also supports text-to-audio, init-audio editing, inpainting, continuation, LoRA loading at launch, and output format controls.

## API

Stable Audio 3 exposes a Gradio API after the Web UI is running. Open the app and check `/gradio_api/info` for the exact schema for the installed Gradio version.

### Python

```python
from gradio_client import Client

client = Client("http://127.0.0.1:7860")
print(client.view_api())
```

For direct Python use without HTTP, register the same mirrors before loading:

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

For Medium, register `cocktailpeanut/stable-audio-3-medium` under the `medium` model name and load `StableAudioModel.from_pretrained("medium")` on an NVIDIA CUDA machine with Flash Attention available.

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

The generation endpoint is named `generate` by the upstream app. Use the schema returned by `/gradio_api/info` to submit the ordered data payload for your installed Gradio version.
