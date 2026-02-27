# Tachy

Voice dictation for macOS with live transcription and AI refinement.

## Features

- **Live transcription** via OpenAI Realtime API — text appears as you speak
- **Multilingual** — switch between Portuguese and English naturally
- **AI refinement** via Claude — punctuation, clarity, and formatting
- **Auto-paste** — refined text is pasted into the active field
- **Double-tap Control** — global hotkey to start/stop recording
- **Menubar app** — lightweight, always accessible, no dock icon

## Setup

### Prerequisites

- macOS 13 (Ventura) or later
- Xcode 15+ / Swift 5.9+
- [OpenAI API key](https://platform.openai.com) (Whisper + Realtime)
- [Anthropic API key](https://console.anthropic.com) (Claude refinement)

### Build

```bash
chmod +x build.sh
./build.sh
open Tachy.app
```

Or with Swift Package Manager directly:

```bash
swift build -c release
```

### Configuration

1. Click the waveform icon in the menubar
2. Go to Settings
3. Enter your OpenAI and Anthropic API keys
4. Choose your refinement level

### Permissions

On first launch, macOS will ask for:
- **Microphone** — to record audio
- **Accessibility** — for global hotkey and auto-paste

## Usage

1. **Double-tap Control** — starts recording
2. **Speak naturally** — text appears live in the active field
3. **Double-tap Control** — stops recording, refines, and pastes
4. **Escape** — cancels recording

## Refinement Levels

| Level | Description |
|-------|-------------|
| None | Raw Whisper transcription |
| Light | Punctuation + transcription error correction |
| Moderate | Light + clarity improvement + hesitation removal |
| Technical prompt | Reformats as a structured prompt |

## Project Structure

```
Tachy/
├── Package.swift
├── build.sh
├── README.md
└── Tachy/
    ├── TachyApp.swift
    ├── DictationManager.swift
    ├── AudioRecorder.swift
    ├── WhisperService.swift
    ├── ClaudeService.swift
    ├── RealtimeTranscriptionService.swift
    ├── LiveTextInserter.swift
    ├── SettingsManager.swift
    ├── DictationError.swift
    ├── MenuBarView.swift
    ├── SettingsView.swift
    ├── Info.plist
    └── Tachy.entitlements
```
