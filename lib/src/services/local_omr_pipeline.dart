import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:sheets_into_music/src/models/note_event.dart';
import 'package:sheets_into_music/src/models/ocr_omr_result.dart';
import 'package:sheets_into_music/src/models/page_preview.dart';
import 'package:sheets_into_music/src/services/music_xml_note_parser.dart';

/// Renders PDF pages locally, then sends them to the Hugging Face OMR service.
class OmrPipeline {
  static const MethodChannel _pdfChannel =
      MethodChannel('sheets_into_music/pdf');
  static final Uri _analyzeUri = Uri.parse(
    'https://p3st0-omr-server.hf.space/analyze',
  );

  http.Client? _client;
  final MusicXmlNoteParser _musicXmlParser;

  OmrPipeline({http.Client? client, MusicXmlNoteParser? musicXmlParser})
      : _client = client,
        _musicXmlParser = musicXmlParser ?? const MusicXmlNoteParser();

  Future<OcrOmrResult> analyzePdf(String pdfPath) async {
    if (!pdfPath.toLowerCase().endsWith('.pdf')) {
      throw ArgumentError('Only PDF files are supported.');
    }

    try {
      final Map<Object?, Object?>? previewResult =
          await _pdfChannel.invokeMapMethod<Object?, Object?>(
        'renderPdfPreview',
        <String, Object?>{'pdfPath': pdfPath, 'maxWidth': 1200},
      );

      if (previewResult == null) {
        throw StateError('Native PDF preview renderer returned no data.');
      }

      final List<PagePreview> previews = _parsePreviews(previewResult['pages']);
      if (previews.isEmpty) {
        throw StateError('Could not render any PDF pages for remote analysis.');
      }

      final List<NoteEvent> notes = <NoteEvent>[];
      final List<String> warnings = <String>[];
      int timelineOffsetMs = 0;

      for (final PagePreview preview in previews) {
        final _RemotePageAnalysis response = await _analyzePage(preview);
        final MusicXmlParseResult parsed = _musicXmlParser.parsePage(
          musicXml: response.musicXml,
          pageIndex: preview.pageIndex,
          startOffsetMs: timelineOffsetMs,
        );

        notes.addAll(parsed.notes);
        warnings.addAll(parsed.warnings);

        if (parsed.notes.isEmpty) {
          warnings.add(
            'Page ${preview.pageIndex + 1}: remote OMR returned no playable notes.',
          );
        }

        timelineOffsetMs +=
            parsed.pageDurationMs > 0 ? parsed.pageDurationMs + 250 : 250;
      }

      warnings.add(
        'Analyzed ${previews.length} page(s) with Hugging Face OMR at ${_analyzeUri.host}.',
      );

      return OcrOmrResult(
        notes: notes,
        warnings: warnings,
        pageCount: previews.length,
        firstPageWidth: previews.first.imageWidth,
        firstPageHeight: previews.first.imageHeight,
        previews: previews,
      );
    } on MissingPluginException {
      throw StateError(
        'Native Android PDF renderer is unavailable on this platform. '
        'Run on an Android device/emulator.',
      );
    } on PlatformException catch (e) {
      final String message = e.message ?? 'unknown native error';
      throw StateError('Native PDF rendering failed (${e.code}): $message');
    } on http.ClientException catch (e) {
      throw StateError('Remote OMR request failed: ${e.message}');
    }
  }

  Future<_RemotePageAnalysis> _analyzePage(PagePreview preview) async {
    final http.Response response = await (_client ??= http.Client())
        .post(
          _analyzeUri,
          headers: const <String, String>{
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode(
            <String, String>{
              'image_base64': base64Encode(preview.pngBytes),
            },
          ),
        )
        .timeout(const Duration(seconds: 90));

    if (response.statusCode != 200) {
      String detail = 'HTTP ${response.statusCode}';
      try {
        final Object? errBody = jsonDecode(response.body);
        if (errBody is Map<String, dynamic>) {
          final String? msg = errBody['message'] as String?;
          if (msg != null && msg.trim().isNotEmpty) {
            detail = '${response.statusCode}: $msg';
          }
        }
      } catch (_) {}
      throw StateError(
        'Remote OMR server error on page ${preview.pageIndex + 1} — $detail',
      );
    }

    final Object? decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw StateError('Remote OMR server returned an invalid response body.');
    }

    final String status = (decoded['status'] as String? ?? '').trim();
    if (status.toLowerCase() != 'ok') {
      final String message = decoded['message'] as String? ?? 'unknown error';
      throw StateError(
          'Remote OMR server error on page ${preview.pageIndex + 1}: $message');
    }

    final String? musicXml = decoded['musicxml'] as String?;
    if (musicXml == null || musicXml.trim().isEmpty) {
      throw StateError(
          'Remote OMR server returned no MusicXML for page ${preview.pageIndex + 1}.');
    }

    return _RemotePageAnalysis(musicXml: musicXml);
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

  int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return null;
  }
}

class _RemotePageAnalysis {
  const _RemotePageAnalysis({required this.musicXml});

  final String musicXml;
}
