/// Represents the high-level state of the PDF-to-audio pipeline.
enum PipelineStatus {
  idle,
  fileReady,
  analyzing,
  analyzed,
  playing,
  error,
}
