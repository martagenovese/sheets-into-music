/// A detected note with pitch/timing and optional visual coordinates.
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
