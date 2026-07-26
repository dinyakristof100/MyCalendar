import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../core/prefs.dart';

/// A háttérkép elérési útja a telefonon.
///
/// Szándékosan NEM `saveSetting` és nincs a `syncedKeys` között: a kép a
/// készüléken marad, nem megy a felhőbe. Egy fénykép nem is férne bele egy
/// Firestore-dokumentumba, és az elérési út a másik telefonon úgysem érne semmit.
const _wallpaperKey = 'wallpaper';

final wallpaperProvider = NotifierProvider<WallpaperController, String?>(
  WallpaperController.new,
);

class WallpaperController extends Notifier<String?> {
  @override
  String? build() {
    final path = prefs.getString(_wallpaperKey);
    // Elveszett fájl (kézzel törölt kép, visszaállított mentés): inkább ne
    // legyen háttérkép, mint egy üres, fekete felület.
    return path != null && File(path).existsSync() ? path : null;
  }

  /// Kép választása a galériából. `false`, ha a felhasználó mégsem választott.
  ///
  /// A képet átmásoljuk az app saját mappájába: az image_picker a
  /// gyorsítótárba tesz, amit a rendszer bármikor kitakaríthat.
  Future<bool> pick() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return false;
    final dir = await getApplicationDocumentsDirectory();
    // Új név minden választásnál: a Flutter a képeket elérési út szerint
    // gyorsítótárazza, azonos néven a régi kép maradna a képernyőn.
    final copy = await File(picked.path).copy(
      '${dir.path}/wallpaper_${DateTime.now().millisecondsSinceEpoch}',
    );
    await _set(copy.path);
    return true;
  }

  Future<void> clear() => _set(null);

  Future<void> _set(String? path) async {
    final previous = state;
    state = path;
    if (path == null) {
      await prefs.remove(_wallpaperKey);
    } else {
      await prefs.setString(_wallpaperKey, path);
    }
    // A korábbi kép már senkinek nem kell, csak a helyet foglalná.
    if (previous != null) {
      try {
        await File(previous).delete();
      } on FileSystemException {
        // Már nincs meg — pont ezt akartuk.
      }
    }
  }
}

/// A háttérkép a teljes app mögé, olvashatóságot segítő fátyollal.
///
/// A `MaterialApp.builder`-ből jön, tehát a Navigator alatt fest: a lapok
/// (áttetsző `scaffoldBackgroundColor`) mind ezt mutatják, oldalváltáskor is
/// egyben marad a kép.
class Wallpaper extends StatelessWidget {
  const Wallpaper({required this.path, required this.child, super.key});

  final String path;
  final Widget child;

  /// A kép fölé kerülő fátyol erőssége. ponytail: fix érték — enélkül egy
  /// világos képen olvashatatlan a szöveg. Ha valakinek sok vagy kevés, egy
  /// csúszka lenne a következő lépcső.
  static const _scrim = 0.72;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      image: DecorationImage(
        image: FileImage(File(path)),
        fit: BoxFit.cover,
        colorFilter: ColorFilter.mode(
          Theme.of(context).colorScheme.surface.withValues(alpha: _scrim),
          BlendMode.srcOver,
        ),
      ),
    ),
    child: child,
  );
}
