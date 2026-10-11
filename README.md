# Freeflow

Free, private dictation for Mac. **Hold a key, speak, release — your words appear at your cursor, in any app.**

- 100% on-device: Parakeet TDT (CoreML, Neural Engine) via [FluidAudio](https://github.com/FluidInference/FluidAudio)
- No cloud, no account, no subscription
- Native Swift, ~9 MB download (model auto-downloads once, ~465 MB)
- macOS 14+, Apple Silicon

## Features
- Push-to-talk with any key (default: left Control)
- Live recording pill with voice-reactive level bars
- Dictation history + stats
- Theme picker (System / Light / Dark)
- Launch at login

## Build
```bash
swift build -c release
```

MIT license.
