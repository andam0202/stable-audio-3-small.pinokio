"""
Generate gothic STG BGM using DeathSmiles LoRA step500.
Produces 20 tracks (8 normal + 8 classical homage + 4 boss), each 90 seconds.

Usage:
    cd app
    HF_TOKEN=... .venv/bin/python -u ../scripts/generate_bgm.py
"""

import json
import os
import sys

import torch
import torchaudio

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "app"))

from stable_audio_3 import StableAudioModel

BASE_DIR = os.path.join(os.path.dirname(__file__), "..")
PROMPTS_PATH = os.path.join(BASE_DIR, "data", "input", "gothic_stg_prompts.json")
LORA_DIR = os.path.join(BASE_DIR, "data", "temp", "deathsmiles", "lora_output", "DeathSmiles_v1")
OUTPUT_DIR = os.path.join(BASE_DIR, "data", "temp", "deathsmiles", "generated", "step500_90s_v2")

LORA_STEP = 500
DURATION = 90.0
STEPS = 8
CFG_SCALE = 4.0
SEED = 42

MODEL_NAME = "cocktailpeanut/stable-audio-3-small-music"
MODEL_CONFIG = "model_config.json"
MODEL_CKPT = "model.safetensors"


def register_mirror(model_module, configs_module):
    from stable_audio_3.model_configs import ModelConfig
    config = ModelConfig(MODEL_NAME, MODEL_CONFIG, MODEL_CKPT)
    configs_module.models["small-music"] = config
    configs_module.all_models["small-music"] = config
    model_module.all_models = configs_module.all_models


def main():
    with open(PROMPTS_PATH) as f:
        prompts = json.load(f)

    print(f"Loaded {len(prompts)} prompts")

    import stable_audio_3.model as model_module
    import stable_audio_3.model_configs as model_configs
    register_mirror(model_module, model_configs)

    device = "cuda" if torch.cuda.is_available() else "cpu"
    print(f"Device: {device}")

    lora_path = os.path.join(LORA_DIR, f"DeathSmiles_v1_step{LORA_STEP}.safetensors")
    out_dir = OUTPUT_DIR
    os.makedirs(out_dir, exist_ok=True)

    # Skip if all files already exist
    all_exist = all(
        os.path.exists(os.path.join(out_dir, f"{p['id']}.wav"))
        for p in prompts
    )
    if all_exist:
        print("All files already generated, skipping.")
        return

    print(f"\n{'='*60}")
    print(f"Generating with LoRA step {LORA_STEP}")
    print(f"LoRA: {lora_path}")
    print(f"Output: {out_dir}")
    print(f"Duration: {DURATION}s per track")
    print(f"{'='*60}")

    print("Loading base model...")
    model = StableAudioModel.from_pretrained("small-music", model_half=True)
    print("Model loaded. Applying LoRA...")
    model.load_lora([lora_path])
    print("LoRA applied.")

    for i, p in enumerate(prompts):
        pid = p["id"]
        prompt = p["prompt"]
        out_path = os.path.join(out_dir, f"{pid}.wav")

        if os.path.exists(out_path):
            print(f"\n  [{i+1}/{len(prompts)}] {pid}: already exists, skipping.")
            continue

        print(f"\n  [{i+1}/{len(prompts)}] {pid}: {prompt}")

        audio = model.generate(
            prompt=prompt,
            duration=DURATION,
            steps=STEPS,
            cfg_scale=CFG_SCALE,
            seed=SEED,
        )

        sample_rate = model.model.sample_rate
        waveform = audio[0].cpu().float().clamp(-1, 1)
        torchaudio.save(out_path, waveform, sample_rate)
        duration_sec = waveform.shape[-1] / sample_rate
        print(f"  Saved: {out_path} ({duration_sec:.1f}s)")

    print(f"\nDone. {len(prompts)} tracks in {out_dir}")
    del model
    torch.cuda.empty_cache()


if __name__ == "__main__":
    main()
