# Freeflow

**Hold a key. Speak. Your words appear at your cursor.**

A free, open-source dictation app for Mac that runs entirely on-device. No cloud, no account, no subscription, no API keys.

## Why

I was using Gemini's voice typing, but it kept *answering my questions* instead of transcribing them. I just wanted the words I said to appear where my cursor was — nothing more.

So I built Freeflow around a 178MB speech model ([Parakeet Redux](https://huggingface.co/moondream/parakeet-redux)) that runs locally on any Mac. It never sends your voice anywhere. It never tries to be smart. It just transcribes.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/rohith1-p/freeflow/main/install.sh | sh
```

Or [download Freeflow.app](https://github.com/rohith1-p/freeflow/releases) directly:
1. Unzip and drag to /Applications
2. Right-click → Open (first time only — no Apple Developer cert)
3. Complete the 60-second setup wizard
4. Hold Control, speak, release

## Requirements

- Mac with Apple Silicon (M1/M2/M3/M4) or Intel
- macOS 13+
- Python 3.10+ (for install script)
- ~500MB disk space (model + dependencies)

## How it works

```
You hold a key → mic records → Parakeet Redux transcribes (local, ~0.3s) → text pastes at cursor
```

That's it. One model, one pass, zero network calls.

## Benchmark

| Metric | Result |
|---|---|
| Transcription accuracy (clean speech) | 0% WER |
| Speed | 45x realtime |
| Memory while idle | ~79MB |
| Memory while transcribing | ~600-800MB |
| Network calls | 0 |

Full benchmark: [reports/2026-10-10-gemma-vs-glm-benchmark.md](reports/)

## Features

- **Fully local** — your voice never leaves your Mac
- **Configurable hotkey** — hold any key to talk
- **Works everywhere** — Cursor, browser, Slack, email, terminal, any text field
- **Free forever** — no subscriptions, no usage limits, no account
- **Clipboard-safe** — restores whatever you had copied
- **Stats dashboard** — word count, dictations, daily streak

## License

MIT — do whatever you want with it.

## Built with

- [Parakeet Redux](https://huggingface.co/moondream/parakeet-redux) — 178MB speech-to-text model
- [pynput](https://pynput.readthedocs.io/) — global hotkey listener
- [sounddevice](https://python-sounddevice.readthedocs.io/) — audio capture
- [rumps](https://github.com/jaredks/rumps) — menu bar app
- Much ☕
