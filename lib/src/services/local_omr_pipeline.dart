import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:sheets_into_music/src/models/note_event.dart';
import 'package:sheets_into_music/src/models/ocr_omr_result.dart';
import 'package:sheets_into_music/src/models/page_preview.dart';

/// Bridges Flutter with native Android PDF analysis/rendering logic.
class LocalOmrPipeline {
  static const MethodChannel _pdfChannel =
      MethodChannel('sheets_into_music/pdf');

  Future<OcrOmrResult> analyzePdf(String pdfPath) async {
    if (!pdfPath.toLowerCase().endsWith('.pdf')) {
      throw ArgumentError('Only PDF files are supported.');
    }

    try {
      final Map<Object?, Object?>? result =
          await _pdfChannel.invokeMapMethod<Object?, Object?>(
        'analyzePdfBasic',
        <String, Object?>{'pdfPath': pdfPath},
      );

      if (result == null) {
        throw StateError('Native PDF analyzer returned no data.');
      }

      final List<PagePreview> previews = _parsePreviews(result['pages']);

      return OcrOmrResult(
        notes: _parseNotes(result['notes']),
        warnings: _parseWarnings(result['warnings']),
        pageCount: _asInt(result['pageCount']),
        firstPageWidth: _asInt(result['firstPageWidth']),
        firstPageHeight: _asInt(result['firstPageHeight']),
        previews: previews,
      );
    } on MissingPluginException {
      throw StateError(
        'Native Android PDF analyzer is unavailable on this platform. '
        'Run on an Android device/emulator.',
      );
    } on PlatformException catch (e) {
      final String message = e.message ?? 'unknown native error';
      throw StateError('Native PDF analysis failed (${e.code}): $message');
    }
  }

  List<NoteEvent> _parseNotes(Object? rawNotes) {
    if (rawNotes is! List<Object?>) {
      return <NoteEvent>[];
    }

    final List<NoteEvent> notes = <NoteEvent>[];
    for (int index = 0; index < rawNotes.length; index++) {
      final Object? raw = rawNotes[index];
      if (raw is! Map<Object?, Object?>) {
        continue;
      }

      final int durationMs = _asInt(raw['durationMs']) ?? 400;
      final int startMs = _asInt(raw['startMs']) ?? (index * durationMs);
      final int midi = _asInt(raw['midi']) ?? 60;
      final String pitch = (raw['pitch'] as String?) ?? 'C4';

      notes.add(
        NoteEvent(
          pitch: pitch,
          midi: midi,
          startMs: startMs,
          durationMs: durationMs,
          pageIndex: _asInt(raw['pageIndex']) ?? 0,
          x: _asInt(raw['x']),
          y: _asInt(raw['y']),
        ),
      );
    }

    return notes;
  }

  List<PagePreview> _parsePreviews(Object? rawPages) {
    if (rawPages is! List<Object?>) {
      return <PagePreview>[];
    }

    final List<PagePreview> pages = <PagePreview>[];
    for (final Object? raw in rawPages) {
      if (raw is! Map<Object?, Object?>) {
        continue;
      }

      final Uint8List? bytes = raw['pngBytes'] as Uint8List?;
      final int? width = _asInt(raw['imageWidth']);
      final int? height = _asInt(raw['imageHeight']);
      final int pageIndex = _asInt(raw['pageIndex']) ?? 0;

      if (bytes == null || width == null || height == null) {
        continue;
      }

      pages.add(
        PagePreview(
          pageIndex: pageIndex,
          pngBytes: bytes,
          imageWidth: width,
          imageHeight: height,
        ),
      );
    }

    pages.sort(
        (PagePreview a, PagePreview b) => a.pageIndex.compareTo(b.pageIndex));
    return pages;
  }

  List<String> _parseWarnings(Object? rawWarnings) {
    if (rawWarnings is! List<Object?>) {
      return <String>[];
    }

    return rawWarnings
        .whereType<String>()
        .where((String message) => message.trim().isNotEmpty)
        .toList(growable: false);
  }

  int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return null;
  }
}
