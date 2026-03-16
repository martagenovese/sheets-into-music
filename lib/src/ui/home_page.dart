import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sheets_into_music/src/models/note_event.dart';
import 'package:sheets_into_music/src/models/ocr_omr_result.dart';
import 'package:sheets_into_music/src/models/page_preview.dart';
import 'package:sheets_into_music/src/models/pipeline_status.dart';
import 'package:sheets_into_music/src/services/local_omr_pipeline.dart';
import 'package:sheets_into_music/src/services/local_playback_engine.dart';
import 'package:sheets_into_music/src/ui/widgets/control_panel.dart';
import 'package:sheets_into_music/src/ui/widgets/diagnostics_panel.dart';
import 'package:sheets_into_music/src/ui/widgets/score_pages_view.dart';

/// Main feature screen for PDF picking, analysis, preview, and playback.
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final OmrPipeline _pipeline = OmrPipeline();
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
    } catch (e, st) {
      debugPrint('OMR analyze error: $e\n$st');
      setState(() {
        _status = PipelineStatus.error;
        _error = null;
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
    _playbackTicker =
        Timer.periodic(const Duration(milliseconds: 33), (Timer timer) {
      if (!mounted) {
        timer.cancel();
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
    } catch (e, st) {
      debugPrint('Playback error: $e\n$st');
      if (!mounted) {
        return;
      }
      setState(() {
        _status = PipelineStatus.error;
        _error = null;
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
        return 'Analyzing PDF pages with Hugging Face OMR...';
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

  List<NoteEvent> _activeNotesForPage(int pageIndex) {
    return _activeNotes
        .where((NoteEvent note) => note.pageIndex == pageIndex)
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final bool canAnalyze =
        _selectedPdfPath != null && _status != PipelineStatus.analyzing;
    final bool canPlay =
        _notes.isNotEmpty && _status != PipelineStatus.analyzing;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sheets Into Music'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              ControlPanel(
                statusLabel: _statusLabel,
                selectedPdfPath: _selectedPdfPath,
                canAnalyze: canAnalyze,
                canPlay: canPlay,
                pageCount: _pageCount,
                firstPageWidth: _firstPageWidth,
                firstPageHeight: _firstPageHeight,
                noteCount: _notes.length,
                onPickPdf: _pickPdf,
                onAnalyze: _analyze,
                onPlay: _play,
              ),
              const SizedBox(height: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(
                      child: ScorePagesView(
                        scrollController: _scoreScrollController,
                        previews: _previews,
                        pageKeys: _pageKeys,
                        playbackMs: _playbackMs,
                        totalDurationMs: _totalDurationMs,
                        notesForPage: _notesForPage,
                        activeNotesForPage: _activeNotesForPage,
                      ),
                    ),
                    DiagnosticsPanel(
                      warnings: _warnings,
                      error: _error,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
