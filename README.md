# Sheets Into Music

Android-first Flutter app that renders sheet-music PDFs locally, sends each page to a Hugging Face OMR service, and plays the detected notes.

Pipeline:

PDF -> Android PdfRenderer -> Hugging Face OMR page analysis -> MusicXML parsing -> note events -> local audio playback

Remote analysis endpoint:

- https://p3st0-omr-server.hf.space/analyze

## Hugging Face Space backend notes

The current Space runs `homr` through the CLI, not a Python API call like `homr.run(...)`.

Expected server behavior for `/analyze`:

- Accept JSON with `image_base64` (PNG bytes encoded as base64).
- Write temp `.png` file.
- Execute `homr <temp.png>` (or fallback to `python -m homr.main <temp.png>`).
- Read generated `.musicxml` file and return it as `{"status":"ok","musicxml":"..."}`.

Important for Docker on Hugging Face:

- `python:3.10-slim` is missing native libs needed by OpenCV (`cv2`).
- Install at least these system packages before `pip install`:
	- `libxcb1`
	- `libx11-6`
	- `libxext6`
	- `libxrender1`
	- `libgl1`
	- `libglib2.0-0`

If these are missing, OMR requests can fail with:

- `ImportError: libxcb.so.1: cannot open shared object file`

## Current state

Implemented end-to-end on Android:

- Pick a PDF from device storage.
- Render PDF pages on-device through a Kotlin method channel.
- Send each rendered page to the Hugging Face Space for OMR.
- Convert returned MusicXML into playable note events.
- Build page previews and note-event timeline.
- Render multi-page score preview in Flutter.
- Draw playback progress over the page previews.
- Auto-scroll to the page currently being played.
- Play extracted notes with a native Android synth path.

Important: note extraction now depends on the remote OMR service response and network availability.

## Tech stack

- Flutter (Dart) UI/app flow

- Kotlin Android native channels for:
	- PDF preview generation
	- audio playback
- Hugging Face Space running `homr` for OMR
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
3. Wait while each page is uploaded to the Hugging Face Space and converted to MusicXML.
4. Inspect Warnings for per-page parse counts and remote-analysis issues.
5. Tap Play to hear extracted notes and see page-following playback.

## Known limitations

- Best results are with clean, digital sheet PDFs.
- Photo-scans, low contrast, skew, or heavy text can reduce detection quality.
- The app requires network access to reach the Hugging Face Space.
- Returned MusicXML currently drives timing and playback, but not exact note-position overlays.
- Complex notation may still be simplified or omitted by the upstream OMR model.

## Troubleshooting

If analysis is slow or returns few/no notes:

- Prefer exported PDFs from notation software rather than camera scans.
- Try fewer pages first to validate the pipeline quickly.
- Confirm the device can reach `https://p3st0-omr-server.hf.space/analyze`.
- Check warning lines in-app for per-page parse counts or remote server errors.
- If device connection drops during debug, re-run flutter run and test with a smaller PDF.

If remote analysis fails with `HTTP 500` and traceback shows `libxcb.so.1` missing:

- Update the Space `Dockerfile` to install the OpenCV runtime libraries listed above.
- Rebuild/restart the Space after committing the Dockerfile change.

If Android toolchain is not detected:

- Verify adb devices lists your device.
- Confirm platform-tools are on PATH.
- Re-check USB/Wi-Fi debugging authorization on phone.

## Next improvement targets

- Return symbol bounding boxes from the remote service so Flutter can restore note overlays.
- Preserve richer rhythm, tempo, and measure metadata from MusicXML.
- Add request retry/backoff and batch progress UI for large PDFs.
- MIDI export and richer instrument playback.