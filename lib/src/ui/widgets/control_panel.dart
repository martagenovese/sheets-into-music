import 'package:flutter/material.dart';

/// Top controls and analysis summary.
class ControlPanel extends StatelessWidget {
  const ControlPanel({
    super.key,
    required this.statusLabel,
    required this.selectedPdfPath,
    required this.canAnalyze,
    required this.canPlay,
    required this.pageCount,
    required this.firstPageWidth,
    required this.firstPageHeight,
    required this.noteCount,
    required this.onPickPdf,
    required this.onAnalyze,
    required this.onPlay,
  });

  final String statusLabel;
  final String? selectedPdfPath;
  final bool canAnalyze;
  final bool canPlay;
  final int? pageCount;
  final int? firstPageWidth;
  final int? firstPageHeight;
  final int noteCount;
  final VoidCallback onPickPdf;
  final VoidCallback onAnalyze;
  final VoidCallback onPlay;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Status: $statusLabel',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        Text(
          selectedPdfPath ?? 'No PDF selected yet.',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            ElevatedButton.icon(
              onPressed: onPickPdf,
              icon: const Icon(Icons.picture_as_pdf),
              label: const Text('Pick PDF'),
            ),
            ElevatedButton.icon(
              onPressed: canAnalyze ? onAnalyze : null,
              icon: const Icon(Icons.auto_graph),
              label: const Text('Analyze'),
            ),
            ElevatedButton.icon(
              onPressed: canPlay ? onPlay : null,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Play'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          pageCount == null
              ? 'PDF info: not available yet'
              : 'PDF info: $pageCount pages, first page ${firstPageWidth ?? '-'} x ${firstPageHeight ?? '-'} px',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        Text(
          'Detected notes: $noteCount',
          style: Theme.of(context).textTheme.titleSmall,
        ),
      ],
    );
  }
}
