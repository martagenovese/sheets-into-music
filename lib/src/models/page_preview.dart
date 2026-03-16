import 'dart:typed_data';

/// Rasterized preview image data for a single PDF page.
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
