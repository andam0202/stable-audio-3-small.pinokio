import os
import runpy
import sys

import stable_audio_3.model as model_module
import stable_audio_3.model_configs as model_configs
from stable_audio_3.model_configs import ModelConfig


MIRROR_MODELS = {
    "small-music": os.environ.get(
        "SA3_SMALL_MUSIC_REPO", "cocktailpeanut/stable-audio-3-small-music"
    ),
    "small-sfx": os.environ.get(
        "SA3_SMALL_SFX_REPO", "cocktailpeanut/stable-audio-3-small-sfx"
    ),
    "medium": os.environ.get(
        "SA3_MEDIUM_REPO", "cocktailpeanut/stable-audio-3-medium"
    ),
}


def register_mirrors():
    for name, repo_id in MIRROR_MODELS.items():
        config = ModelConfig(repo_id, "model_config.json", "model.safetensors")
        model_configs.models[name] = config
        model_configs.all_models[name] = config

    model_module.all_models = model_configs.all_models


def disable_gradio_share_links():
    import gradio.blocks

    original_launch = gradio.blocks.Blocks.launch

    def launch_without_share(self, *args, **kwargs):
        kwargs["share"] = False
        return original_launch(self, *args, **kwargs)

    gradio.blocks.Blocks.launch = launch_without_share


if __name__ == "__main__":
    register_mirrors()
    disable_gradio_share_links()
    sys.argv[0] = "run_gradio.py"
    runpy.run_path("run_gradio.py", run_name="__main__")
