import 'package:flutter/material.dart';
import 'package:sheets_into_music/src/models/note_event.dart';
import 'package:sheets_into_music/src/models/page_preview.dart';
import 'package:sheets_into_music/src/ui/score_overlay_painter.dart';

/// Scrollable page list that shows score images and playback overlays.
class ScorePagesView extends StatelessWidget {
  const ScorePagesView({
    super.key,
    required this.scrollController,
    required this.previews,
    required this.pageKeys,
    required this.playbackMs,
    required this.totalDurationMs,
    required this.notesForPage,
    required this.activeNotesForPage,
  });

  final ScrollController scrollController;
  final List<PagePreview> previews;
  final Map<int, GlobalKey> pageKeys;
  final int playbackMs;
  final int totalDurationMs;
  final List<NoteEvent> Function(int pageIndex) notesForPage;
  final List<NoteEvent> Function(int pageIndex) activeNotesForPage;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: scrollController,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (previews.isEmpty)
            Text(
              'Score preview appears here after Analyze.',
              style: Theme.of(context).textTheme.bodyMedium,
            )
          else
            ...previews.map((PagePreview page) {
              final List<NoteEvent> pageNotes = notesForPage(page.pageIndex);
              final List<NoteEvent> activePageNotes =
                  activeNotesForPage(page.pageIndex);

              return Padding(
                key: pageKeys[page.pageIndex],
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
                      aspectRatio: page.imageWidth / page.imageHeight,
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
                              painter: ScoreOverlayPainter(
                                notes: pageNotes,
                                activeNotes: activePageNotes,
                                playbackMs: playbackMs,
                                totalDurationMs: totalDurationMs,
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
        ],
      ),
    );
  }
}
