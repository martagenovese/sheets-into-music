import 'package:flutter/material.dart';

/// Shows warnings, errors, and a short footer note.
class DiagnosticsPanel extends StatelessWidget {
  const DiagnosticsPanel({
    super.key,
    required this.warnings,
    required this.error,
  });

  final List<String> warnings;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SizedBox(height: 8),
        if (warnings.isNotEmpty) ...<Widget>[
          Text(
            'Warnings',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          ...warnings.map((String warning) => Text('• $warning')),
        ],
        if (error != null) ...<Widget>[
          const SizedBox(height: 12),
          Text(
            error!,
            style: const TextStyle(color: Colors.red),
          ),
        ],
        const SizedBox(height: 12),
        const Text(
          'Playback auto-scrolls through rendered PDF pages. Remote MusicXML results do not include note coordinates yet.',
        ),
      ],
    );
  }
}
