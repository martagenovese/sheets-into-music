import 'package:flutter/material.dart';
import 'package:sheets_into_music/src/models/note_event.dart';

/// Draws note markers, active-note highlights, and playback playhead.
class ScoreOverlayPainter extends CustomPainter {
  const ScoreOverlayPainter({
    required this.notes,
    required this.activeNotes,
    required this.playbackMs,
    required this.totalDurationMs,
    required this.imageWidth,
    required this.imageHeight,
  });

  final List<NoteEvent> notes;
  final List<NoteEvent> activeNotes;
  final int playbackMs;
  final int totalDurationMs;
  final int imageWidth;
  final int imageHeight;

  @override
  void paint(Canvas canvas, Size size) {
    if (notes.isEmpty) {
      return;
    }

    final Paint notePaint = Paint()
      ..color = Colors.orange.withOpacity(0.68)
      ..style = PaintingStyle.fill;

    final Paint activePaint = Paint()
      ..color = Colors.greenAccent.withOpacity(0.85)
      ..style = PaintingStyle.fill;

    final double widthScale = size.width / imageWidth;
    final double heightScale = size.height / imageHeight;

    for (final NoteEvent note in notes) {
      if (note.x == null || note.y == null) {
        continue;
      }
      final Offset pos = Offset(note.x! * widthScale, note.y! * heightScale);
      canvas.drawCircle(pos, 4.2, notePaint);
    }

    for (final NoteEvent note in activeNotes) {
      if (note.x == null || note.y == null) {
        continue;
      }
      final Offset pos = Offset(note.x! * widthScale, note.y! * heightScale);
      canvas.drawCircle(pos, 8.0, activePaint);
    }

    if (totalDurationMs > 0 && playbackMs >= 0) {
      final double ratio = (playbackMs / totalDurationMs).clamp(0.0, 1.0);
      final double x = ratio * size.width;
      final Paint playhead = Paint()
        ..color = Colors.redAccent.withOpacity(0.7)
        ..strokeWidth = 2;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), playhead);
    }
  }

  @override
  bool shouldRepaint(covariant ScoreOverlayPainter oldDelegate) {
    return oldDelegate.playbackMs != playbackMs ||
        oldDelegate.notes != notes ||
        oldDelegate.activeNotes != activeNotes ||
        oldDelegate.imageWidth != imageWidth ||
        oldDelegate.imageHeight != imageHeight;
  }
}
