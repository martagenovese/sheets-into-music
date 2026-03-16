import 'dart:math' as math;

import 'package:sheets_into_music/src/models/note_event.dart';
import 'package:xml/xml.dart';

class MusicXmlParseResult {
  const MusicXmlParseResult({
    required this.notes,
    required this.warnings,
    required this.pageDurationMs,
  });

  final List<NoteEvent> notes;
  final List<String> warnings;
  final int pageDurationMs;
}

class MusicXmlNoteParser {
  const MusicXmlNoteParser();

  static const int _defaultTempoBpm = 120;
  static const int _minimumDurationMs = 120;

  MusicXmlParseResult parsePage({
    required String musicXml,
    required int pageIndex,
    required int startOffsetMs,
  }) {
    try {
      final XmlDocument document = XmlDocument.parse(musicXml);
      final Iterable<XmlElement> parts = document.findAllElements('part');
      if (parts.isEmpty) {
        return const MusicXmlParseResult(
          notes: <NoteEvent>[],
          warnings: <String>['MusicXML response did not contain any parts.'],
          pageDurationMs: 0,
        );
      }

      int tempoBpm = _extractTempo(document) ?? _defaultTempoBpm;
      final List<_TimedNote> timedNotes = <_TimedNote>[];
      int maxEndDivisions = 0;
      int divisions = 1;

      for (final XmlElement part in parts) {
        final _PartParseResult partResult = _parsePart(part);
        timedNotes.addAll(partResult.notes);
        maxEndDivisions = math.max(maxEndDivisions, partResult.maxEndDivisions);
        divisions = math.max(divisions, partResult.lastDivisions);
        tempoBpm = partResult.tempoBpm ?? tempoBpm;
      }

      final List<NoteEvent> notes = timedNotes
          .map(
            (_TimedNote note) => NoteEvent(
              pitch: note.pitch,
              midi: note.midi,
              startMs: startOffsetMs +
                  _divisionsToMs(note.startDivisions, divisions, tempoBpm),
              durationMs: math.max(
                _minimumDurationMs,
                _divisionsToMs(note.durationDivisions, divisions, tempoBpm),
              ),
              pageIndex: pageIndex,
            ),
          )
          .toList(growable: false)
        ..sort((NoteEvent a, NoteEvent b) => a.startMs.compareTo(b.startMs));

      return MusicXmlParseResult(
        notes: notes,
        warnings: <String>[
          'Page ${pageIndex + 1}: parsed ${notes.length} note(s) from MusicXML at $tempoBpm BPM.',
        ],
        pageDurationMs: _divisionsToMs(maxEndDivisions, divisions, tempoBpm),
      );
    } on XmlParserException catch (e) {
      return MusicXmlParseResult(
        notes: const <NoteEvent>[],
        warnings: <String>['MusicXML parse failed: ${e.message}'],
        pageDurationMs: 0,
      );
    }
  }

  _PartParseResult _parsePart(XmlElement part) {
    final List<_TimedNote> notes = <_TimedNote>[];
    int cursorDivisions = 0;
    int maxEndDivisions = 0;
    int divisions = 1;
    int? tempoBpm;
    final Map<String, int> lastChordStartByVoice = <String, int>{};

    for (final XmlElement measure in part.findElements('measure')) {
      for (final XmlNode node in measure.children.whereType<XmlElement>()) {
        final XmlElement element = node as XmlElement;

        switch (element.name.local) {
          case 'attributes':
            final int? parsedDivisions = _parseInt(
              element.getElement('divisions')?.innerText,
            );
            if (parsedDivisions != null && parsedDivisions > 0) {
              divisions = parsedDivisions;
            }
          case 'direction':
            tempoBpm ??= _extractTempo(element);
          case 'backup':
            cursorDivisions = math.max(
              0,
              cursorDivisions -
                  (_parseInt(element.getElement('duration')?.innerText) ?? 0),
            );
          case 'forward':
            cursorDivisions +=
                _parseInt(element.getElement('duration')?.innerText) ?? 0;
          case 'note':
            final bool isRest = element.getElement('rest') != null;
            final bool isChord = element.getElement('chord') != null;
            final String voice =
                element.getElement('voice')?.innerText.trim().isNotEmpty == true
                    ? element.getElement('voice')!.innerText.trim()
                    : '1';
            final int durationDivisions =
                _parseInt(element.getElement('duration')?.innerText) ??
                    divisions;
            final int startDivisions = isChord
                ? (lastChordStartByVoice[voice] ?? cursorDivisions)
                : cursorDivisions;

            if (!isRest) {
              final _PitchInfo? pitch =
                  _parsePitch(element.getElement('pitch'));
              if (pitch != null) {
                notes.add(
                  _TimedNote(
                    pitch: pitch.label,
                    midi: pitch.midi,
                    startDivisions: startDivisions,
                    durationDivisions: durationDivisions,
                  ),
                );
                maxEndDivisions = math.max(
                  maxEndDivisions,
                  startDivisions + durationDivisions,
                );
              }
            }

            if (!isChord) {
              cursorDivisions += durationDivisions;
              lastChordStartByVoice[voice] = startDivisions;
            }
        }
      }
    }

    return _PartParseResult(
      notes: notes,
      maxEndDivisions: maxEndDivisions,
      lastDivisions: divisions,
      tempoBpm: tempoBpm,
    );
  }

  int? _extractTempo(XmlNode node) {
    for (final XmlElement sound in node.findAllElements('sound')) {
      final String? tempoValue = sound.getAttribute('tempo');
      final int? tempo = _parseNum(tempoValue)?.round();
      if (tempo != null && tempo > 0) {
        return tempo;
      }
    }

    for (final XmlElement perMinute in node.findAllElements('per-minute')) {
      final int? tempo = _parseNum(perMinute.innerText)?.round();
      if (tempo != null && tempo > 0) {
        return tempo;
      }
    }

    return null;
  }

  _PitchInfo? _parsePitch(XmlElement? pitchElement) {
    if (pitchElement == null) {
      return null;
    }

    final String? step = pitchElement.getElement('step')?.innerText.trim();
    final int? octave = _parseInt(pitchElement.getElement('octave')?.innerText);
    if (step == null || step.isEmpty || octave == null) {
      return null;
    }

    final int alter =
        _parseInt(pitchElement.getElement('alter')?.innerText) ?? 0;
    final int baseSemitone = switch (step) {
      'C' => 0,
      'D' => 2,
      'E' => 4,
      'F' => 5,
      'G' => 7,
      'A' => 9,
      'B' => 11,
      _ => 0,
    };
    final int midi = ((octave + 1) * 12) + baseSemitone + alter;
    final String accidental = switch (alter) {
      -2 => 'bb',
      -1 => 'b',
      1 => '#',
      2 => '##',
      _ => '',
    };

    return _PitchInfo(label: '$step$accidental$octave', midi: midi);
  }

  int _divisionsToMs(int divisionsValue, int divisions, int tempoBpm) {
    if (divisionsValue <= 0 || divisions <= 0 || tempoBpm <= 0) {
      return 0;
    }

    final double quarterNotes = divisionsValue / divisions;
    final double beatMs = 60000 / tempoBpm;
    return (quarterNotes * beatMs).round();
  }

  int? _parseInt(String? value) {
    if (value == null) {
      return null;
    }
    return int.tryParse(value.trim());
  }

  num? _parseNum(String? value) {
    if (value == null) {
      return null;
    }
    return num.tryParse(value.trim());
  }
}

class _PartParseResult {
  const _PartParseResult({
    required this.notes,
    required this.maxEndDivisions,
    required this.lastDivisions,
    required this.tempoBpm,
  });

  final List<_TimedNote> notes;
  final int maxEndDivisions;
  final int lastDivisions;
  final int? tempoBpm;
}

class _TimedNote {
  const _TimedNote({
    required this.pitch,
    required this.midi,
    required this.startDivisions,
    required this.durationDivisions,
  });

  final String pitch;
  final int midi;
  final int startDivisions;
  final int durationDivisions;
}

class _PitchInfo {
  const _PitchInfo({required this.label, required this.midi});

  final String label;
  final int midi;
}
