import 'package:flutter/services.dart';
import 'package:sheets_into_music/src/models/note_event.dart';

/// Bridges Flutter with native Android audio synthesis/playback.
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
