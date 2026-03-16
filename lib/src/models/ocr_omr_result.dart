import 'package:sheets_into_music/src/models/note_event.dart';
import 'package:sheets_into_music/src/models/page_preview.dart';

/// Aggregated output from native PDF analysis.
class OcrOmrResult {
  const OcrOmrResult({
    required this.notes,
    required this.warnings,
    required this.pageCount,
    required this.firstPageWidth,
    required this.firstPageHeight,
    required this.previews,
  });

  final List<NoteEvent> notes;
  final List<String> warnings;
  final int? pageCount;
  final int? firstPageWidth;
  final int? firstPageHeight;
  final List<PagePreview> previews;
}
