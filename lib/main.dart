import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const SheetToSoundApp());
}

class SheetToSoundApp extends StatelessWidget {
  const SheetToSoundApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sheets Into Music',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}

enum PipelineStatus {
  idle,
  fileReady,
  analyzing,
  analyzed,
  playing,
  error,
}

class PagePreview {
  const PagePreview({
    required this.pageIndex,
    required this.pngBytes,
    required this.imageWidth,
    required this.imageHeight,
  });

  final int pageIndex;
  final Uint8List pngBytes;
  final int imageWidth;
  final int imageHeight;
}

class NoteEvent {
  const NoteEvent({
    required this.pitch,
    required this.midi,
    required this.startMs,
    required this.durationMs,
    required this.pageIndex,
    this.x,
    this.y,
  });

  final String pitch;
  final int midi;
  final int startMs;
  final int durationMs;
  final int pageIndex;
  final int? x;
  final int? y;

  Map<String, Object> toMap() {
    return <String, Object>{
      'pitch': pitch,
      'midi': midi,
      'startMs': startMs,
      'durationMs': durationMs,
      'pageIndex': pageIndex,
    };
  }
}

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

      final Map<Object?, Object?>? previewResponse =
          await _pdfChannel.invokeMapMethod<Object?, Object?>(
        'renderPdfPreview',
        <String, Object?>{
          'pdfPath': pdfPath,
          'maxWidth': 1400,
        },
      );

      return OcrOmrResult(
        notes: _parseNotes(result['notes']),
        warnings: _parseWarnings(result['warnings']),
        pageCount: _asInt(result['pageCount']),
        firstPageWidth: _asInt(result['firstPageWidth']),
        firstPageHeight: _asInt(result['firstPageHeight']),
        previews: _parsePreviews(previewResponse?['pages']),
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

    pages.sort((PagePreview a, PagePreview b) => a.pageIndex.compareTo(b.pageIndex));
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

class LocalPlaybackEngine {
  static const MethodChannel _audioChannel =
      MethodChannel('sheets_into_music/audio');

  Future<void> playNotes(List<NoteEvent> notes) async {
    if (notes.isEmpty) return;

    try {
      final List<Map<String, Object>> payload = notes
          .asMap()
          .entries
          .map(
            (MapEntry<int, NoteEvent> entry) => <String, Object>{
              ...entry.value.toMap(),
              'index': entry.key,
            },
          )
          .toList(growable: false);

      await _audioChannel.invokeMethod<void>(
        'playNotes',
        <String, Object>{'notes': payload},
      );
    } on MissingPluginException {
      throw StateError(
        'Native Android playback is unavailable on this platform. '
        'Run on an Android device/emulator.',
      );
    } on PlatformException catch (e) {
      final String message = e.message ?? 'unknown native error';
      throw StateError('Native playback failed (${e.code}): $message');
    }
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final LocalOmrPipeline _pipeline = LocalOmrPipeline();
  final LocalPlaybackEngine _playback = LocalPlaybackEngine();
  final ScrollController _scoreScrollController = ScrollController();

  String? _selectedPdfPath;
  PipelineStatus _status = PipelineStatus.idle;
  List<NoteEvent> _notes = <NoteEvent>[];
  List<String> _warnings = <String>[];
  List<PagePreview> _previews = <PagePreview>[];
  String? _error;
  int? _pageCount;
  int? _firstPageWidth;
  int? _firstPageHeight;
  int _playbackMs = 0;
  int? _lastAutoScrolledPage;
  Timer? _playbackTicker;
  final Map<int, GlobalKey> _pageKeys = <int, GlobalKey>{};

  @override
  void dispose() {
    _playbackTicker?.cancel();
    _scoreScrollController.dispose();
    super.dispose();
  }

  Future<void> _pickPdf() async {
    setState(() {
      _error = null;
    });

    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: <String>['pdf'],
      withData: false,
    );

    if (result == null || result.files.single.path == null) {
      return;
    }

    setState(() {
      _selectedPdfPath = result.files.single.path;
      _status = PipelineStatus.fileReady;
      _notes = <NoteEvent>[];
      _warnings = <String>[];
      _previews = <PagePreview>[];
      _pageCount = null;
      _firstPageWidth = null;
      _firstPageHeight = null;
      _playbackMs = 0;
      _lastAutoScrolledPage = null;
      _error = null;
      _pageKeys.clear();
    });
  }

  Future<void> _analyze() async {
    if (_selectedPdfPath == null) {
      return;
    }

    setState(() {
      _status = PipelineStatus.analyzing;
      _error = null;
    });

    try {
      final OcrOmrResult result = await _pipeline.analyzePdf(_selectedPdfPath!);

      setState(() {
        _notes = result.notes;
        _warnings = result.warnings;
        _previews = result.previews;
        _pageCount = result.pageCount;
        _firstPageWidth = result.firstPageWidth;
        _firstPageHeight = result.firstPageHeight;
        _playbackMs = 0;
        _lastAutoScrolledPage = null;
        _pageKeys
          ..clear()
          ..addEntries(
            _previews.map(
              (PagePreview page) => MapEntry<int, GlobalKey>(
                page.pageIndex,
                GlobalKey(),
              ),
            ),
          );
        _status = PipelineStatus.analyzed;
      });
    } catch (e) {
      setState(() {
        _status = PipelineStatus.error;
        _error = e.toString();
      });
    }
  }

  Future<void> _play() async {
    if (_notes.isEmpty) {
      return;
    }

    setState(() {
      _status = PipelineStatus.playing;
      _error = null;
      _playbackMs = 0;
      _lastAutoScrolledPage = null;
    });

    final Stopwatch stopwatch = Stopwatch()..start();
    _playbackTicker?.cancel();
    _playbackTicker = Timer.periodic(const Duration(milliseconds: 33), (Timer t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        _playbackMs = stopwatch.elapsedMilliseconds;
      });
      _autoScrollToActivePage();
    });

    try {
      await _playback.playNotes(_notes);
      if (!mounted) {
        return;
      }
      setState(() {
        _status = PipelineStatus.analyzed;
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _status = PipelineStatus.error;
        _error = e.toString();
      });
    } finally {
      stopwatch.stop();
      _playbackTicker?.cancel();
      _playbackTicker = null;
      if (mounted) {
        setState(() {
          _playbackMs = 0;
          _lastAutoScrolledPage = null;
        });
      }
    }
  }

  void _autoScrollToActivePage() {
    final int? activePage = _activePageIndex;
    if (activePage == null || activePage == _lastAutoScrolledPage) {
      return;
    }

    final GlobalKey? key = _pageKeys[activePage];
    final BuildContext? targetContext = key?.currentContext;
    if (targetContext == null) {
      return;
    }

    _lastAutoScrolledPage = activePage;
    Scrollable.ensureVisible(
      targetContext,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeInOut,
      alignment: 0.08,
    );
  }

  String get _statusLabel {
    switch (_status) {
      case PipelineStatus.idle:
        return 'Pick a PDF to begin';
      case PipelineStatus.fileReady:
        return 'PDF selected';
      case PipelineStatus.analyzing:
        return 'Analyzing full PDF with local OMR...';
      case PipelineStatus.analyzed:
        return 'Analysis complete';
      case PipelineStatus.playing:
        return 'Playing extracted notes...';
      case PipelineStatus.error:
        return 'An error occurred';
    }
  }

  int get _totalDurationMs {
    if (_notes.isEmpty) {
      return 0;
    }
    return _notes
        .map((NoteEvent n) => n.startMs + n.durationMs)
        .reduce((int a, int b) => a > b ? a : b);
  }

  List<NoteEvent> get _activeNotes {
    return _notes.where((NoteEvent n) {
      final int start = n.startMs;
      final int end = n.startMs + n.durationMs;
      return _playbackMs >= start && _playbackMs < end;
    }).toList(growable: false);
  }

  int? get _activePageIndex {
    final List<NoteEvent> active = _activeNotes;
    if (active.isEmpty) {
      return null;
    }
    return active.first.pageIndex;
  }

  List<NoteEvent> _notesForPage(int pageIndex) {
    return _notes
        .where((NoteEvent note) => note.pageIndex == pageIndex)
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final bool canAnalyze =
        _selectedPdfPath != null && _status != PipelineStatus.analyzing;
    final bool canPlay = _notes.isNotEmpty && _status != PipelineStatus.analyzing;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sheets Into Music (Android starter)'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Status: $_statusLabel',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              Text(
                _selectedPdfPath ?? 'No PDF selected yet.',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: <Widget>[
                  ElevatedButton.icon(
                    onPressed: _pickPdf,
                    icon: const Icon(Icons.picture_as_pdf),
                    label: const Text('Pick PDF'),
                  ),
                  ElevatedButton.icon(
                    onPressed: canAnalyze ? _analyze : null,
                    icon: const Icon(Icons.auto_graph),
                    label: const Text('Analyze'),
                  ),
                  ElevatedButton.icon(
                    onPressed: canPlay ? _play : null,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Play'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                _pageCount == null
                    ? 'PDF info: not available yet'
                    : 'PDF info: $_pageCount pages, first page ${_firstPageWidth ?? '-'} x ${_firstPageHeight ?? '-'} px',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 8),
              Text(
                'Detected notes: ${_notes.length}',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 10),
              Expanded(
                child: SingleChildScrollView(
                  controller: _scoreScrollController,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      if (_previews.isEmpty)
                        Text(
                          'Score preview appears here after Analyze.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        )
                      else
                        ..._previews.map((PagePreview page) {
                          final List<NoteEvent> pageNotes =
                              _notesForPage(page.pageIndex);
                          final List<NoteEvent> activePageNotes = _activeNotes
                              .where(
                                (NoteEvent note) =>
                                    note.pageIndex == page.pageIndex,
                              )
                              .toList(growable: false);

                          return Padding(
                            key: _pageKeys[page.pageIndex],
                            padding: const EdgeInsets.only(bottom: 14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  'Page ${page.pageIndex + 1}',
                                  style: Theme.of(context).textTheme.titleSmall,
                                ),
                                const SizedBox(height: 6),
                                AspectRatio(
                                  aspectRatio:
                                      page.imageWidth / page.imageHeight,
                                  child: Card(
                                    clipBehavior: Clip.antiAlias,
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: <Widget>[
                                        Image.memory(
                                          page.pngBytes,
                                          fit: BoxFit.contain,
                                        ),
                                        CustomPaint(
                                          painter: _ScoreOverlayPainter(
                                            notes: pageNotes,
                                            activeNotes: activePageNotes,
                                            playbackMs: _playbackMs,
                                            totalDurationMs: _totalDurationMs,
                                            imageWidth: page.imageWidth,
                                            imageHeight: page.imageHeight,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      const SizedBox(height: 8),
                      if (_warnings.isNotEmpty) ...<Widget>[
                        Text(
                          'Warnings',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        ..._warnings.map((String warning) => Text('• $warning')),
                      ],
                      if (_error != null) ...<Widget>[
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ],
                      const SizedBox(height: 12),
                      const Text(
                        'Playback auto-scrolls through all pages and follows active notes.',
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScoreOverlayPainter extends CustomPainter {
  const _ScoreOverlayPainter({
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
  bool shouldRepaint(covariant _ScoreOverlayPainter oldDelegate) {
    return oldDelegate.playbackMs != playbackMs ||
        oldDelegate.notes != notes ||
        oldDelegate.activeNotes != activeNotes ||
        oldDelegate.imageWidth != imageWidth ||
        oldDelegate.imageHeight != imageHeight;
  }
}
