# Sheets Into Music

Android-first Flutter starter for a fully local pipeline:

PDF sheet music → on-device OMR (AI/CV) → note events → audio playback.

## Current status

- Flutter project scaffolded.
- Android-focused starter UI added:
  - pick a PDF,
  - run analysis (mocked for now),
  - play notes (mocked for now).
- First real local Android step integrated:
	- native `PdfRenderer` method channel reads PDF page count and first page size.
- Starter code is intentionally structured so real engines can replace mocks.

## Why AI/CV is needed

If the input is PDF sheet music (not MusicXML/MIDI), you need OMR.
OMR is a computer-vision/AI task in practice.

## Free local options (no server)

1. On-device model inference
	- TensorFlow Lite (Android)
	- ONNX Runtime Mobile

2. Computer vision helpers
	- OpenCV for staff-line and symbol preprocessing

3. Playback (local)
	- MIDI generation + synth (for example FluidSynth-based integration)

## Suggested MVP scope

Start narrow for fast progress:

- single staff,
- monophonic melody only,
- clean printed PDFs,
- basic note durations (quarter/half/eighth),
- fixed tempo.

Then add chords, multi-staff, key signatures, dynamics, and articulation.

## Project milestones

1. Replace mock analyzer with real PDF→image rendering and preprocessing.
2. Add on-device notehead/rest/stem detection model.
3. Convert detections to timed notes.
4. Generate MIDI and wire a local synth.
5. Improve accuracy and add score-visual debug overlays.