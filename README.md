# 🎬 CaptionsAI

> **Import any video → get styled AI captions in seconds → export ready for Instagram/TikTok/YouTube. Works 100% offline.**

[![Platform](https://img.shields.io/badge/platform-iOS%2017+-blue.svg)](https://developer.apple.com/ios/)
[![Swift](https://img.shields.io/badge/swift-5.9+-orange.svg)](https://swift.org/)
[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)

---

## ✨ Features

- **AI-Powered Captions** — On-device speech recognition via Apple's Speech framework
- **10+ Caption Styles** — Clean, Bold, Neon, Minimal, Highlight, Typewriter, Subtitle, Pop
- **Word-by-Word Highlighting** — Hormozi/podcast style word highlighting
- **Export Presets** — Instagram Reels, TikTok, YouTube, YouTube Shorts, Original
- **100% Offline** — No cloud, no API keys, your videos stay on your device
- **Pro Tier** — Unlimited exports, no watermark, all styles via StoreKit 2

## 🏗️ Architecture

```
CaptionsAI/
├── App/                    # App entry point & global state
├── Models/                 # SwiftData models (Project, CaptionSegment, CaptionStyle)
├── Engine/                 # Core business logic (Speech, Rendering, Export)
├── ViewModels/             # @Observable view models
├── Views/                  # SwiftUI screens & components
├── Services/               # StoreKit, Analytics
└── Resources/              # Assets, strings
```

**4-Layer Architecture**: Views → ViewModels → Engine → Apple Frameworks

## 🛠️ Tech Stack

| Layer | Technology |
|-------|-----------|
| UI | SwiftUI (iOS 17+) |
| Persistence | SwiftData |
| Speech | SFSpeechRecognizer |
| Video | AVFoundation, Core Image |
| Payments | StoreKit 2 |
| Analytics | Firebase (lightweight) |
| Concurrency | Swift Concurrency (async/await) |

## 🚀 Setup

1. Clone the repo:
   ```bash
   git clone git@github.com:Lalit-khatri/CaptionsAI.git
   ```
2. Open `CaptionsAI.xcodeproj` in Xcode 15+
3. Select your development team in Signing & Capabilities
4. Build and run on a device (Speech framework requires a real device)

## 📱 Screens

1. **Onboarding** — Welcome + feature highlights
2. **Import** — Video picker from Photo Library
3. **Editor** — Caption editing + style picker
4. **Preview** — Full-screen video with live captions
5. **Export** — Platform presets + progress
6. **Paywall** — Free vs Pro comparison

## 📄 License

MIT License — see [LICENSE](LICENSE) for details.
