"""
Auto-tag audio files using CLAP zero-shot classification + librosa BPM estimation.
Generates .txt caption files suitable for Stable Audio 3 LoRA training.

Usage:
    cd app
    .venv/bin/python ../scripts/auto_tag.py
"""

import os
import glob
import shutil
import warnings

import torch
import torchaudio
import librosa
import numpy as np
from transformers import ClapProcessor, ClapModel

warnings.filterwarnings("ignore")

INPUT_DIR = os.path.join(os.path.dirname(__file__), "..", "data", "input", "deathsmiles")
OUTPUT_DIR = os.path.join(os.path.dirname(__file__), "..", "data", "temp", "deathsmiles", "tagged")
CLAP_MODEL = "laion/clap-htsat-unfused"
SAMPLE_RATE = 48000
MAX_AUDIO_SEC = 30  # CLAP max input length

CATEGORIES = {
    "genre": [
        "gothic music", "orchestral music", "electronic music", "rock music",
        "heavy metal", "ambient music", "classical music", "chiptune",
        "synth music", "baroque music", "darkwave", "industrial music",
        "piano music", "organ music", "video game music",
    ],
    "mood": [
        "dark mood", "eerie mood", "haunting mood", "epic mood",
        "intense mood", "melancholic mood", "mysterious mood",
        "aggressive mood", "dramatic mood", "powerful mood",
        "tense mood", "upbeat mood", "peaceful mood", "sad mood",
    ],
    "instrument": [
        "strings", "piano", "organ", "synthesizer", "electric guitar",
        "choir vocals", "brass instruments", "drums", "flute",
        "harpsichord", "bass guitar", "percussion", "violin",
        "trumpet", "harp", "tubular bells",
    ],
    "tempo": [
        "very fast tempo", "fast tempo", "medium tempo", "slow tempo",
        "driving rhythm", "marching rhythm", "swinging rhythm",
    ],
    "character": [
        "cinematic sound", "video game soundtrack", "atmospheric sound",
        "retro sound", "layered arrangement", "complex composition",
        "boss battle music", "stage background music", "menu music",
        "ending theme", "intro theme", "action music",
    ],
}


def load_clap():
    device = "cuda" if torch.cuda.is_available() else "cpu"
    print(f"Loading CLAP model on {device}...")
    processor = ClapProcessor.from_pretrained(CLAP_MODEL)
    model = ClapModel.from_pretrained(CLAP_MODEL).to(device)
    model.eval()
    return processor, model, device


def classify_audio(processor, model, device, audio_array, sr, categories, top_k=3):
    """Run zero-shot classification for each category."""
    if sr != SAMPLE_RATE:
        import librosa as _librosa
        audio_array = _librosa.resample(audio_array, orig_sr=sr, target_sr=SAMPLE_RATE)
        sr = SAMPLE_RATE

    max_samples = MAX_AUDIO_SEC * sr
    if len(audio_array) > max_samples:
        mid = len(audio_array) // 2
        half = max_samples // 2
        audio_array = audio_array[mid - half : mid + half]

    results = {}
    for cat_name, labels in categories.items():
        inputs = processor(
            text=labels,
            audio=audio_array,
            sampling_rate=sr,
            return_tensors="pt",
            padding=True,
        )
        inputs = {k: v.to(device) for k, v in inputs.items()}

        with torch.no_grad():
            outputs = model(**inputs)

        audio_embeds = outputs.audio_embeds
        text_embeds = outputs.text_embeds
        audio_embeds = audio_embeds / audio_embeds.norm(dim=-1, keepdim=True)
        text_embeds = text_embeds / text_embeds.norm(dim=-1, keepdim=True)
        similarity = (audio_embeds @ text_embeds.T).squeeze(0)
        probs = similarity.softmax(dim=0)

        top_indices = probs.argsort(descending=True)[:top_k]
        results[cat_name] = [
            (labels[i].replace(" music", "").replace(" mood", "").replace(" sound", "").replace(" soundtrack", "").replace(" tempo", "").replace(" rhythm", ""),
             probs[i].item())
            for i in top_indices
        ]

    return results


def estimate_bpm(audio_path):
    """Estimate BPM using librosa."""
    try:
        y, sr = librosa.load(audio_path, sr=22050, duration=60)
        tempo, _ = librosa.beat.beat_track(y=y, sr=sr)
        if isinstance(tempo, np.ndarray):
            tempo = float(tempo[0]) if len(tempo) > 0 else 0.0
        return round(float(tempo))
    except Exception:
        return None


def extract_context_from_filename(filename):
    """Extract context hints from the filename."""
    name = os.path.splitext(filename)[0].lower()
    hints = []

    if "boss" in name:
        hints.append("boss battle theme")
    if "final" in name:
        hints.append("final stage")
    if "stage" in name:
        hints.append("stage background music")
    if "select" in name:
        hints.append("selection menu music")
    if "clear" in name:
        hints.append("stage clear jingle")
    if "extra" in name:
        hints.append("extra stage")
    if "name" in name or "demo" in name:
        hints.append("ending theme")
    if "waltz" in name:
        hints.append("waltz")
    if "halloween" in name:
        hints.append("halloween")
    if "hades" in name or "hell" in name:
        hints.append("underworld")
    if "forest" in name:
        hints.append("forest")
    if "grave" in name:
        hints.append("graveyard")
    if "witch" in name or "swamp" in name:
        hints.append("swamp")
    if "castle" in name:
        hints.append("castle")
    if "village" in name or "lake" in name:
        hints.append("lake village")
    if "giant" in name or "beast" in name:
        hints.append("giant beast")
    if "ghost" in name or "aristocrat" in name:
        hints.append("aristocratic ghosts")
    if "bach" in name or "toccata" in name or "fugue" in name:
        hints.append("classical arrangement")
    if "invitation" in name:
        hints.append("intro invitation")
    if "banquet" in name or "madness" in name:
        hints.append("banquet of madness")
    if "soul" in name or "wandering" in name:
        hints.append("wandering souls")

    return hints


def compose_caption(tags, bpm, context_hints):
    """Compose a natural language caption from tags and context."""
    genre = [t for t, s in tags.get("genre", []) if s > 0.05]
    mood = [t for t, s in tags.get("mood", []) if s > 0.08]
    instruments = [t for t, s in tags.get("instrument", []) if s > 0.08]
    tempo_feel = [t for t, s in tags.get("tempo", []) if s > 0.1]
    character = [t for t, s in tags.get("character", []) if s > 0.08]

    parts = []

    if context_hints:
        parts.extend(context_hints[:2])

    if genre:
        parts.append(", ".join(genre[:2]))
    if mood:
        parts.append(", ".join(mood[:2]))
    if instruments:
        parts.append(", ".join(instruments[:3]))
    if tempo_feel:
        parts.append(tempo_feel[0])

    if bpm and 40 < bpm < 250:
        parts.append(f"{bpm} BPM")

    if character:
        parts.append(", ".join(character[:2]))

    caption = ", ".join(parts)
    return caption if caption else "instrumental music"


def main():
    input_dir = os.path.abspath(INPUT_DIR)
    output_dir = os.path.abspath(OUTPUT_DIR)
    os.makedirs(output_dir, exist_ok=True)

    audio_files = sorted(glob.glob(os.path.join(input_dir, "*.mp3")))
    audio_files += sorted(glob.glob(os.path.join(input_dir, "*.wav")))
    audio_files += sorted(glob.glob(os.path.join(input_dir, "*.flac")))
    audio_files += sorted(glob.glob(os.path.join(input_dir, "*.ogg")))

    print(f"Found {len(audio_files)} audio files in {input_dir}")

    processor, model, device = load_clap()

    for i, audio_path in enumerate(audio_files):
        basename = os.path.basename(audio_path)
        name_stem = os.path.splitext(basename)[0]
        print(f"\n[{i+1}/{len(audio_files)}] Processing: {basename}")

        print("  Estimating BPM...")
        bpm = estimate_bpm(audio_path)
        print(f"  BPM: {bpm}")

        print("  Running CLAP classification...")
        y, sr = librosa.load(audio_path, sr=SAMPLE_RATE, duration=MAX_AUDIO_SEC, mono=True)
        tags = classify_audio(processor, model, device, y, SAMPLE_RATE, CATEGORIES, top_k=3)

        for cat, items in tags.items():
            top = ", ".join(f"{name}({score:.2f})" for name, score in items)
            print(f"  {cat}: {top}")

        context = extract_context_from_filename(basename)
        caption = compose_caption(tags, bpm, context)
        print(f"  Caption: {caption}")

        dest_audio = os.path.join(output_dir, basename)
        shutil.copy2(audio_path, dest_audio)

        caption_path = os.path.join(output_dir, f"{name_stem}.txt")
        with open(caption_path, "w", encoding="utf-8") as f:
            f.write(caption + "\n")

        print(f"  Saved: {caption_path}")

    print(f"\nDone. {len(audio_files)} files tagged in {output_dir}")


if __name__ == "__main__":
    main()
