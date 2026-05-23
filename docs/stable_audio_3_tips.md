# Stable Audio 3 プロンプトエンジニアリング Tips

SA3でBGM生成する際の知見まとめ。主にmediumモデル（post-trained）+ LoRA使用時のノウハウ。

## モデル別パラメータ

SA3モデルには2種類あり、推奨パラメータが全く異なる。

| パラメータ | Post-trained (medium/small-music/small-sfx) | Base (medium-base等) |
|-----------|---------------------------------------------|----------------------|
| steps | **8** | ~50 |
| cfg_scale | **1.0** | 7.0 |
| sampler | **pingpong**（自動選択） | euler |
| 用途 | 生成（推論） | LoRA学習のベース |

Post-trainedモデルは敵対的事後学習（ARC）を受けており、8ステップで高品質な出力を生成する。steps/cfg_scaleを上げても品質は向上せず、計算コストだけ増える。

**教訓**: LoRA学習はbaseモデル、生成はpost-trainedモデル。パラメータを使い分けること。

## プロンプトの基本構造

公式推奨順序:

```
1. Genre/Style（ジャンル）
2. Key instruments（主要楽器）
3. Mood/emotion（感情）
4. BPM
5. Production details（制作ディテール）
```

### キーワード羅列 vs 自然文

SA3では**自然な文章**で書く方が良い結果が出る。

```
# 悪い例（キーワード羅列）
"acid synth, 909 kick, techno bass, catchy melody, heroic, 170 BPM"

# 良い例（自然文）
"A fierce Detroit techno track featuring a soaring acid synth lead solo.
Supported by driving 909 kick and pulsating techno bass.
The mood is heroic and exhilarating. 170 BPM."
```

### featuring...supported by...パターン

主楽器と補助楽器を明確に区別する構文。メロディの目立ち方が劇的に改善する。

```
"[ジャンル] track titled '[タイトル]',
featuring [主楽器] lead solo [演奏内容].
Supported by [補助楽器1], [補助楽器2], and [補助楽器3].
The mood is [感情]. [BPM] BPM."
```

- `featuring ... solo` → メロディ楽器を指定
- `Supported by ...` → リズム・ハーモニー・ベース等の補助

## メロディを強調するテクニック

### 1. `Solo` キーワード

最強のメロディ強調キーワード。モデルに「この楽器でメロディを演奏しろ」と指示する。

```
"Horns solo."        # ホルンがメロディを取る
"Piano lead solo."   # ピアノが主旋律
```

### 2. `Live` と `Band`

MIDIっぽさを消し、有機的な演奏感を出す。

```
"Live."    # ライブ録音の質感
"Band."    # バンドアンサンブル感
```

### 3. `Well-arranged composition`

曲構造（イントロ→展開→クライマックス）を促す。

### 4. 生成時間は最低45秒

20秒以下ではメロディが確立せず、パッドやドローンになりやすい。メロディが必要な場合は45秒以上、理想は1〜2分。90秒は十分な長さ。

### 5. Seedを変えて複数生成 → 最良を選択

同一プロンプトでもSeedで結果が大きく変わる。キュレーション（選別）が品質向上の鍵。

## AudioSparxタグ

SA3の学習データ（AudioSparx）のメタデータ形式に合わせると精度が向上する。

```
"TrackType: Music, VocalType: Instrumental, Genre: [ジャンル], Format: Band."
```

| タグ | 値 | 効果 |
|------|-----|------|
| TrackType | `Music` / `Instrument` / `SFX` | 生成タイプの指定 |
| VocalType | `Instrumental` | ボーカルなし（BGMに必須） |
| Genre | `Techno`, `Rock`, `Jazz` 等 | ジャンル指定。複数可 |
| Format | `Solo` / `Duo` / `Band` | アンサンブル規模 |

## 曲タイトルの活用

`titled '[タイトル]'` を追加すると、モデルに感情的・音楽的な方向性を与えられる。

```
"A fierce techno track titled 'Bloody Cathedral', ..."
"An emotional ambient track titled 'Lullaby of Rebirth', ..."
```

タイトルは英語で、曲の雰囲気に合ったものを付ける。

## メロディ関連キーワード一覧

| キーワード | 効果 |
|-----------|------|
| `solo` | 特定楽器でメロディを強調 |
| `catchy melody` | キャッチーな旋律 |
| `melodic` | メロディックな生成を促す |
| `soaring` | 上昇する感情的高揚 |
| `emotional` | 感情的なメロディ |
| `beautiful` | 美しい音色・旋律 |
| `live` | 有機的な演奏感 |
| `band` | バンドアンサンブル感 |
| `well-arranged composition` | 構造的な楽曲展開 |

## プロンプトテンプレート（BGM用）

```
TrackType: Music, VocalType: Instrumental, Genre: [ジャンル], Format: Band.
A [形容詞] [ジャンル] track titled '[タイトル]',
featuring a [形容詞] [主楽器] lead solo [演奏スタイル].
Supported by [補助楽器1], [補助楽器2], and [補助楽器3].
The mood is [感情1], [感情2], and [感情3].
[追加指示]. Well-arranged composition. Live. [BPM] BPM.
```

## その他のTips

### 地理的コンテキスト

`Detroit techno`, `Chicago blues`, `Bossa Nova from Brazil` 等の地名でスタイルを具体化。

### ユースケース指定

`perfect for a video game boss battle`, `perfect for opening credits` 等で用途を明示。

### 録音品質の指定

低品質になりがちな場合は以下を追加:

```
"44.1k Hz, high-quality, stereo"
```

### 時代参照

`80s gated reverb`, `90s grunge distortion` 等の年代参照が有効。

### Inpainting（部分再生成）

メロディが弱い区間だけをマスクして再生成可能。Gradio UIで利用できる。

## バージョン履歴

| Version | パラメータ | プロンプト | 主な変更 |
|---------|-----------|-----------|---------|
| v3 | steps=16, cfg=6.0 | キーワード羅列 + 厚み強化 | mediumモデル化、LoRA再学習 |
| v4 | steps=16, cfg=6.0 | キーワード羅列 + 苛烈/ポジティブ | 感情表現の強化 |
| v5 | steps=16, cfg=6.0 | キーワード羅列 + 並木学techno | Detroit techno + gothic |
| v6 | **steps=8, cfg=1.0** | **自然文 + Solo + AudioSparx + タイトル** | SA3最適パラメータ + プロンプト改善 |

## 参考情報源

- SA3公式プロンプトガイド: `github.com/Stability-AI/stable-audio-3/docs/guides/prompting.md`
- SA 2.5プロンプトガイド: `stability.ai/guides/stable-audio-25-prompt-guide`
- Jordi Pons "On Prompting Stable Audio": `jordipons.me/on-prompting-stable-audio`
- SA3技術論文: `arxiv.org/abs/2605.17991`
