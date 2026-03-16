# Sheets Into Music

Android-first Flutter app that analyzes sheet-music PDFs locally and plays detected notes.

Pipeline:

PDF -> Android PdfRenderer -> local CV note detection -> note events -> local audio playback

No server is required for the current implementation.

## Current state

Implemented end-to-end on Android:

- Pick a PDF from device storage.
- Analyze all pages on-device through a Kotlin method channel.
- Build page previews and note-event timeline.
- Render multi-page score preview in Flutter.
- Draw note overlays and playback progress.
- Auto-scroll to the page currently being played.
- Play extracted notes with a native Android synth path.

Important: this is still a heuristic OMR pipeline, not a trained music model. Accuracy depends heavily on PDF quality.

## Tech stack

- Flutter (Dart) UI/app flow
- Kotlin Android native channels for:
	- PDF analysis and preview generation
	- audio playback
- file_picker for PDF selection

Main channels:

- sheets_into_music/pdf
- sheets_into_music/audio

## Project structure

- lib/src/ui: screens, widgets, visual overlays
- lib/src/services: Flutter-side bridges for PDF analysis and playback
- lib/src/models: note/page/result/status models
- android/app/src/main/kotlin/.../MainActivity.kt: native analysis + audio implementation

## Requirements

- Flutter SDK compatible with this project
- Android Studio + Android SDK
- ADB configured and device/emulator available
- Android target with USB debugging or wireless debugging enabled

## Run

Install dependencies:

```bash
flutter pub get
```

List devices:

```bash
flutter devices
```

Run on a specific Android device:

```bash
flutter run -d <device_id>
```

Run tests:

```bash
flutter test
```

## How to use the app

1. Tap Pick PDF and choose a sheet-music PDF.
2. Tap Analyze.
3. Inspect Warnings for per-page diagnostics and total analysis time.
4. Tap Play to hear extracted notes and see page-following overlays.

## Known limitations

- Best results are with clean, digital sheet PDFs.
- Photo-scans, low contrast, skew, or heavy text can reduce detection quality.
- Rhythmic interpretation is simplified (fixed-duration style timeline in current implementation).
- Note detection is capped and heuristic; complex notation may be missed.

## Troubleshooting

If analysis is very slow or returns few/no notes:

- Prefer exported PDFs from notation software rather than camera scans.
- Try fewer pages first to validate the pipeline quickly.
- Check warning lines in-app:
	- per-page analyzed size/time
	- per-page detected note count
	- total analysis time
- If device connection drops during debug, re-run flutter run and test with a smaller PDF.

If Android toolchain is not detected:

- Verify adb devices lists your device.
- Confirm platform-tools are on PATH.
- Re-check USB/Wi-Fi debugging authorization on phone.

## Next improvement targets

- Replace heuristics with a stronger OMR model (TFLite/ONNX) on device.
- Better text-vs-music discrimination.
- More accurate timing/rhythm extraction.
- MIDI export and richer instrument playback.