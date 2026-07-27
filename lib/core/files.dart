import 'package:flutter/services.dart';

/// Fájl beolvasása és kiküldése a rendszer saját ablakain át — a naptáréval
/// azonos natív csatornán (lásd `MainActivity.kt`). Egy app, egy csatorna: a
/// metódusnév különbözteti meg a hívásokat.
///
/// ponytail: nincs `file_picker`/`share_plus` függőség. Mindkét művelet egyetlen
/// Android-intent, amit az app amúgy is meglévő csatornája elvisz — a csomagok
/// ennél többet nem tudnának, cserébe hoznának egy csomó Gradle-függőséget.
const _channel = MethodChannel('mycalendar/device_calendar');

/// A rendszer fájlválasztójával megnyitott szövegfájl teljes tartalma, vagy
/// `null`, ha a felhasználó elvetette a választást.
Future<String?> pickTextFile() => _channel.invokeMethod<String>('pickTextFile');

/// A [content] kiírása [name] néven, majd a rendszer megosztó-ablakának
/// megnyitása: e-mail, üzenet, Bluetooth, felhő — amit a telefon épp kínál.
///
/// A fájl az app gyorsítótárába kerül, a fogadó app ideiglenes olvasási jogot
/// kap rá (FileProvider). Takarítani nem kell: a gyorsítótárat a rendszer üríti.
Future<void> shareTextFile(String name, String content) => _channel
    .invokeMethod<void>('shareTextFile', {'name': name, 'content': content});
