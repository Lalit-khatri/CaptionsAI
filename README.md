# 🎬 CaptionsAI

> **Import any video → get styled AI captions in seconds → export ready for Instagram/TikTok/YouTube. On-device speech recognition wherever your device supports it.**

[![Platform](https://img.shields.io/badge/platform-iOS%2017+-blue.svg)](https://developer.apple.com/ios/)
[![Swift](https://img.shields.io/badge/swift-5.9+-orange.svg)](https://swift.org/)
[![License](https://img.shields.io/badge/license-proprietary-lightgrey.svg)](LICENSE)

---

## ✨ Features

- **AI-Powered Captions** — Apple's Speech framework, on-device wherever the device and language support it (see [PRIVACY.md](PRIVACY.md))
- **30 Caption Styles** — from Hormozi-style word-by-word highlighting to outlined, boxed, monospaced, serif and hand-lettered looks
- **Word-by-Word Highlighting** — colour switch, pill box, pop scale, underline and dim-inactive effects
- **Export Presets** — Instagram Reels / TikTok / Shorts (9:16), YouTube (16:9), Original
- **No accounts, no analytics** — your videos stay on your device
- **Pro Tier** — Unlimited exports and no watermark, via StoreKit 2

## 🏗️ Architecture

```
CaptionsAI/
├── App/                    # App entry point & global state
├── Models/                 # SwiftData models (Project, CaptionSegment), CaptionStyle + Styles/
├── Engine/                 # Core business logic (Speech, Rendering, Export)
├── ViewModels/             # @Observable view models
├── Views/                  # SwiftUI screens & components
├── Services/               # StoreKit, video library, feedback mail
└── Resources/              # Assets
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
| Concurrency | Swift Concurrency (async/await) |

## 🚀 Setup

The Xcode project is generated from `project.yml` with
[XcodeGen](https://github.com/yonaskolb/XcodeGen). Regenerate it after
pulling and whenever files are added or removed — a stale
`CaptionsAI.xcodeproj` does not list new files and will not compile.

1. Clone the repo:
   ```bash
   git clone git@github.com:Lalit-khatri/CaptionsAI.git
   ```
2. Generate the project:
   ```bash
   brew install xcodegen   # once
   xcodegen generate
   ```
3. Open `CaptionsAI.xcodeproj` in Xcode 16+
4. Select your development team in Signing & Capabilities
5. Build and run on a device (Speech framework requires a real device)

## 📱 Screens

1. **Onboarding** — Welcome + feature highlights
2. **Home** — Video picker and recent projects
3. **Editor** — Caption editing, style sheet, caption position
4. **Export** — Platform presets + progress
5. **Paywall** — Free vs Pro comparison

## 📄 License

Copyright © 2026 Lalit Khatri. All Rights Reserved. See [LICENSE](LICENSE) for details.
