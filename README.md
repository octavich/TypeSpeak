# TypeSpeak

**Your keyboard is your microphone.**

TypeSpeak is a macOS menu-bar app for people who can't (or won't) talk into a mic.
Type text, pick a voice, and it synthesizes speech straight into a virtual
microphone — Discord, Zoom, games, anything that reads a mic hears it as you.
Optional headphone monitoring lets you hear yourself live.

```
text → synthesizer → buffers ─┬─→ BlackHole (virtual mic) → Discord / game / Zoom
                              └─→ headphones (optional monitor) → you
```

## Features

- Type-to-speech into a virtual microphone
- English (`en-US`) and Russian (`ru-RU`) voices, Premium / Enhanced quality
- Live monitoring — hear yourself in your own headphones
- Adjustable speech rate
- Lives in the menu bar, out of your way

## Requirements

- macOS 14+
- [BlackHole](https://github.com/ExistentialAudio/BlackHole) virtual audio driver

## Install

```bash
# 1. virtual audio driver (one time)
brew install --cask blackhole-2ch
sudo killall coreaudiod          # reload audio so BlackHole shows up

# 2. build & run
git clone https://github.com/octavich/TypeSpeak.git
cd TypeSpeak
swift run
```

A microphone icon appears in the menu bar.

## Usage

1. In TypeSpeak, set **Output** to `BlackHole 2ch`.
2. (Optional) Enable **monitor** and pick your headphones.
3. In Discord / Zoom / your game, select `BlackHole 2ch` as the **microphone**.
4. Type, press **⌘↵** — it speaks into the mic.

### Voices

Apple does **not** expose the Siri voice to apps — no third-party app can use it.
The closest match is **Ava (Premium)** for English. Download more voices in:

**System Settings → Accessibility → Spoken Content → System Voice → Manage Voices…**

Premium > Enhanced > default (compact) in quality.

## Notes

- BlackHole is a separate GPLv3 driver installed by the user; TypeSpeak does not
  bundle or link it.
- Setting one device as both mic and monitor is skipped automatically to avoid echo.

## License

[MIT](LICENSE)
