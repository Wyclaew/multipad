import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:zxing2/qrcode.dart';

class QrScannerService {
  /// Decodes a QR code string from image file bytes (PNG/JPEG/WebP screenshot or photo).
  /// Works across Android, macOS, and Windows without camera hardware.
  static String? decodeQrFromImageBytes(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;

    // Limit extreme high-res screenshots to <=1400px so QR decoding stays fast and crisp
    final processed = (decoded.width > 1400 || decoded.height > 1400)
        ? img.copyResize(
            decoded,
            width: decoded.width >= decoded.height ? 1400 : null,
            height: decoded.height > decoded.width ? 1400 : null,
          )
        : decoded;

    final pixels = Int32List(processed.width * processed.height);
    int idx = 0;
    for (int y = 0; y < processed.height; y++) {
      for (int x = 0; x < processed.width; x++) {
        final pixel = processed.getPixel(x, y);
        final r = pixel.r.toInt();
        final g = pixel.g.toInt();
        final b = pixel.b.toInt();
        final a = pixel.a.toInt();
        pixels[idx++] = (a << 24) | (r << 16) | (g << 8) | b;
      }
    }

    try {
      final source = RGBLuminanceSource(processed.width, processed.height, pixels);
      final bitmap = BinaryBitmap(HybridBinarizer(source));
      final reader = QRCodeReader();
      final result = reader.decode(bitmap);
      return result.text;
    } catch (_) {
      return null;
    }
  }
}
