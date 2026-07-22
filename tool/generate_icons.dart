// Ikon PNG-k generálása a vektoros mesterpéldányból.
//
// Futtatás a projekt gyökeréből:
//   flutter test tool/generate_icons.dart
//
// Miért teszt? A raszterizáláshoz élő `dart:ui` kell (PictureRecorder +
// Image.toByteData), és ezt a flutter_test környezet adja a legkevesebb
// ceremóniával — se új csomag, se külső program (ImageMagick, Inkscape) nem
// kell hozzá. A `tool/` mappában van, nem a `test/`-ben, hogy a sima
// `flutter test` ne futtassa és ne írjon fájlokat minden teszteléskor.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 1024: App Store / Play Store mester. 512: Play Store listing.
/// 192: Android xxxhdpi. 120: iOS iPhone @2x.
const _sizes = [1024, 512, 192, 120];

const _indigo = Color(0xFF3F51B5);

/// Ugyanaz a geometria, mint az `assets/icon/icon.svg`-ben és az Android
/// vector drawable-ben, 108x108-as vásznon. Ha az ikon változik, mind a
/// hármat követni kell — az Android nem tud SVG-t olvasni, ezért nincs egy
/// közös forrás, amiből mindhárom generálódhatna.
void _paintIcon(Canvas canvas) {
  final white = Paint()..color = Colors.white;
  final indigo = Paint()..color = _indigo;

  // háttér
  canvas.drawRRect(
    RRect.fromRectAndRadius(
      const Rect.fromLTWH(0, 0, 108, 108),
      const Radius.circular(24),
    ),
    indigo,
  );
  // Naptár teste. A fejléc sáv szándékosan nincs megrajzolva: ugyanolyan
  // indigó lenne, mint a háttér, tehát láthatatlan — viszont a két egymásra
  // rajzolt, azonos ívű alakzat élsimítása halvány szegélyt hagyott 1024-en.
  canvas.drawRRect(
    RRect.fromRectAndCorners(
      const Rect.fromLTWH(30, 51, 48, 29),
      bottomLeft: const Radius.circular(6),
      bottomRight: const Radius.circular(6),
    ),
    white,
  );
  // gyűrűk
  for (final x in [40.0, 63.0]) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(x, 32, 5, 12),
        const Radius.circular(2.5),
      ),
      white,
    );
  }
  // pipa
  canvas.drawPath(
    Path()
      ..moveTo(41, 65)
      ..lineTo(50, 73)
      ..lineTo(68, 56),
    Paint()
      ..color = _indigo
      ..style = PaintingStyle.stroke
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round,
  );
}

Future<void> _writePng(int size) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.scale(size / 108);
  _paintIcon(canvas);

  final image = await recorder.endRecording().toImage(size, size);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  final file = File('assets/icon/icon_$size.png');
  await file.writeAsBytes(data!.buffer.asUint8List());

  // A PNG fejléc 16..23. bájtja a szélesség és a magasság (big-endian) — ha a
  // méret nem stimmel, itt bukik el, nem a store feltöltésnél.
  final bytes = await file.readAsBytes();
  int be32(int o) =>
      (bytes[o] << 24) | (bytes[o + 1] << 16) | (bytes[o + 2] << 8) | bytes[o + 3];
  expect(be32(16), size, reason: 'szélesség');
  expect(be32(20), size, reason: 'magasság');
}

void main() {
  test('ikon PNG-k generálása', () async {
    for (final size in _sizes) {
      await _writePng(size);
    }
  });
}
