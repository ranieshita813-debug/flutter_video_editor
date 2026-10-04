# motionGr

Advanced Android video editor foundation built with Flutter, inspired by CapCut, Kinemaster, and professional nonlinear editors.

## Features
- **Splash Screen**: Professional animated intro with motionGr branding
- **Dark Editor UI**: Premium mobile creator interface inspired by top-tier tools
- **Timeline Editor**: Multi-track editing with video, audio, image, and text clips
- **Editor Controller**: Playhead, trim, split, and effect system
- **Inspector Panel**: Professional properties editor for clip editing
- **Tool Palette**: Quick access to cut, split, text, and filter actions

## Planned Advanced Features
- Multi-track timeline with draggable clips
- Snapping, trimming, split, and ripple editing
- Text, stickers, LUTs, and visual effects
- Audio waveform and voice-over tools
- Background music mixing and volume automation
- Crop, transform, keyframe animation, and motion effects
- FFmpeg-based export pipeline for Android
- Media picker and project save/load system
- Slow motion, speed ramping, and time remapping
- Green screen and layer blending modes

## Architecture
```
lib/
├── core/
│   ├── models/          # Project and timeline domain models
│   ├── theme/           # App styling and design tokens
│   └── services/        # Media, export, and storage services (upcoming)
├── features/
│   ├── editor/
│   │   ├── controllers/ # Editing logic and state management
│   │   ├── pages/       # Editor screens UI
│   │   └── widgets/     # Reusable editor components
│   └── splash/
│       └── pages/       # Splash screen with branding
└── main.dart           # App entry point
```

## Getting Started

1. Clone the repository
2. Run `flutter pub get`
3. Run `flutter run` to launch motionGr

## Important Note
This repository is a professional-grade foundation built for expansion into a full Android video editor with advanced features. It is not a single-screen mockup but a production-ready starter architecture.
