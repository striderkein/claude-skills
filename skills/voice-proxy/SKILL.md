---
name: voice-proxy
description: 本人の声のクローン（合成音声）で引数で渡されたテキストを代読する。発言内容のテキストを話し言葉スクリプトに整形し、TTS で音声合成して仮想オーディオデバイス経由で会議アプリに流す。「ミーティングで音声流して」「合成音声で発言して」「代読して」「meeting voice」等で発動。
argument-hint: <しゃべらせたい内容>
---

# voice-proxy — 合成音声での発言代読

発言内容をテキストで受け取り、本人の声のクローンで読み上げ音声を作って会議に流す skill。
「喋るのが面倒」を「書くだけでよい」に変換する。

## 前提セットアップ（初回のみ・ユーザ作業）

1. **声のクローン登録**: ElevenLabs で自分の声を Voice Clone として登録（Instant Voice Cloning で数分の録音から作れる）
2. **環境変数**: `ELEVENLABS_API_KEY` と `ELEVENLABS_VOICE_ID` を設定
3. **仮想オーディオデバイス**: macOS → [BlackHole 2ch](https://existential.audio/blackhole/) / Windows → VB-Cable
4. **会議アプリ側**: Zoom / Meet のマイク入力を仮想デバイス（BlackHole 等）に設定

セットアップが未完了なら、まずどこまで済んでいるかをユーザに確認し、不足分の手順を案内する。

## ワークフロー

1. **内容を受け取る**: 発言したい内容（箇条書き・メモ書きで可）を受け取る
2. **話し言葉に整形**:
   - 1 文を短く。書き言葉（「〜である」「〜につきまして」）を会話体に崩す
   - 数字・記号は読み上げ形式に展開（`3/15` → 「3 月 15 日」、`PR #3177` → 「PR 3177 番」）
3. **スクリプト確認**: 整形したスクリプトをユーザに見せて OK をもらう（読み上げてしまうと取り消せないため必須）
4. **音声合成**:
   ```bash
   curl -sS -X POST "https://api.elevenlabs.io/v1/text-to-speech/${ELEVENLABS_VOICE_ID}" \
     -H "xi-api-key: ${ELEVENLABS_API_KEY}" \
     -H "Content-Type: application/json" \
     -d '{"text": "<スクリプト>", "model_id": "eleven_multilingual_v2"}' \
     -o /tmp/voice-proxy/speech.mp3
   ```
5. **仮想デバイスへ再生**:
   - macOS: `ffplay` は出力デバイス指定が弱いので、システム出力を BlackHole に切り替えてから `afplay /tmp/voice-proxy/speech.mp3`（切り替えは `SwitchAudioSource -s "BlackHole 2ch"`、再生後に元へ戻す）
   - 自分でもモニタしたい場合は Audio MIDI 設定で「複数出力装置」（BlackHole + 内蔵出力）を作ってそちらに切り替える

## 質疑への対応

リアルタイムの質疑には向かない（本人の判断を偽装しない）。質問が来たら:
- チャットでのテキスト回答に誘導する
- または「持ち帰って後で回答します」の定型音声を流す

## 代替手段の提案

喋る内容が定型の進捗報告なら、そもそも音声にせず `/setup-mtg` の事前 Slack 共有に載せる方が軽い。
skill 発動時に内容が「報告のみ・質疑なし」だった場合は、非同期化の選択肢も一度提案すること。
