import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ota_update/ota_update.dart';

/// Appon belüli frissítés sideloadolt (nem Play Store-os) APK-hoz.
///
/// A telepített `versionCode`-ot (natív csatornán át) a GitHub legfrissebb
/// kiadásához hasonlítjuk; ha van újabb, megnyitáskor felajánljuk. Elfogadásra
/// letöltjük a stabil `releases/latest/download/mycalendar.apk`-t, és elindítjuk
/// a rendszer telepítőjét. A záró „Telepítés" gomb az Androidé — sideloadnál ezt
/// nem lehet (és nem is szabad) megkerülni. iOS-en a funkció nem létezik.
const _repoApi = 'https://api.github.com/repos/dinyakristof100/MyCalendar';
const _apkUrl =
    'https://github.com/dinyakristof100/MyCalendar/releases/latest/download/mycalendar.apk';

// Ugyanaz a csatorna, amit a MainActivity regisztrál (a `versionCode` metódussal).
const _channel = MethodChannel('mycalendar/device_calendar');

/// A GitHub kiadás-tagjének alakja: `v{versionName}+{versionCode}`, pl.
/// `v1.2.1+1008`. A `versionCode` a monoton növő szám — ez dönt a frissítésről.
/// Ismeretlen alaknál `null`, hogy sose ajánljunk fel értelmezhetetlen kiadást.
({String versionName, int versionCode})? parseRelease(String tag) {
  final code = int.tryParse(tag.split('+').last);
  if (code == null) return null;
  final name = tag.replaceFirst(RegExp(r'^v'), '').split('+').first;
  return (versionName: name, versionCode: code);
}

/// Van-e a telepítettnél újabb kiadás? `null`, ha nincs, vagy ha bármi hiba
/// (offline, rate limit, nem Android) — a frissítés-ellenőrzés sose zavarhat be.
Future<({String versionName, int versionCode})?> checkForUpdate() async {
  if (!Platform.isAndroid) return null; // iOS: csak App Store, nincs sideload
  final client = HttpClient();
  try {
    final current = await _channel.invokeMethod<int>('versionCode') ?? 0;
    final req = await client.getUrl(Uri.parse('$_repoApi/releases/latest'));
    req.headers
      ..set(HttpHeaders.userAgentHeader, 'MyCalendar-updater') // GitHub kötelező
      ..set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
    final resp = await req.close();
    if (resp.statusCode != 200) return null;
    final body =
        jsonDecode(await resp.transform(utf8.decoder).join())
            as Map<String, dynamic>;
    final tag = body['tag_name'] as String?;
    final release = tag == null ? null : parseRelease(tag);
    if (release == null || release.versionCode <= current) return null;
    return release;
  } catch (_) {
    return null;
  } finally {
    client.close();
  }
}

/// Megnyitáskor: ha van újabb kiadás, felajánlja, és elfogadásra le is futtatja a
/// frissítést. Bárhol hiba/nincs újdonság → csendben nem történik semmi.
Future<void> maybePromptUpdate(BuildContext context) async {
  final info = await checkForUpdate();
  if (info == null || !context.mounted) return;

  final accepted = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Új verzió elérhető'),
      content: Text(
        'A(z) ${info.versionName} verzió letölthető. Frissíted most? '
        'A letöltés után a rendszer telepítője kér majd megerősítést.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Később'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Frissítés'),
        ),
      ],
    ),
  );
  if ((accepted ?? false) && context.mounted) {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _UpdateProgressDialog(),
    );
  }
}

/// Letöltés-folyamat, majd átadás a rendszer telepítőjének.
///
/// A haladást az [OtaUpdate] eseményfolyamából olvassuk. `INSTALLING`-nál az OS
/// telepítője veszi át, ezért bezárjuk a párbeszédet; hibánál is bezárjuk, egy
/// visszajelzéssel — a felhasználó a régi verzión marad, semmi sem törik.
class _UpdateProgressDialog extends StatefulWidget {
  const _UpdateProgressDialog();

  @override
  State<_UpdateProgressDialog> createState() => _UpdateProgressDialogState();
}

class _UpdateProgressDialogState extends State<_UpdateProgressDialog> {
  double? _progress;
  String _label = 'Letöltés előkészítése…';

  @override
  void initState() {
    super.initState();
    try {
      // usePackageInstaller: a modern PackageInstaller session API — ez kell
      // Android 14+-on (a régi ACTION_INSTALL_PACKAGE út deprecated, és a hozzá
      // tartozó FileProvidert sem deklaráljuk). Ehhez a manifestben regisztrálni
      // kell az ota_update InstallResultReceiver-ét — lásd AndroidManifest.xml.
      OtaUpdate()
          .execute(
            _apkUrl,
            destinationFilename: 'mycalendar.apk',
            usePackageInstaller: true,
          )
          .listen(_onEvent, onError: (_) => _fail());
    } catch (_) {
      _fail();
    }
  }

  void _onEvent(OtaEvent event) {
    if (!mounted) return;
    switch (event.status) {
      case OtaStatus.DOWNLOADING:
        setState(() {
          _progress = (int.tryParse(event.value ?? '') ?? 0) / 100;
          _label = 'Letöltés…';
        });
      case OtaStatus.INSTALLING:
      case OtaStatus.INSTALLATION_DONE:
        // A rendszer telepítője átveszi (és sikeres telepítéskor lecseréli az
        // appot) — a saját párbeszédünkre innen már nincs szükség.
        Navigator.of(context).maybePop();
      default:
        _fail(); // engedélyhiány, letöltési hiba, checksum stb.
    }
  }

  void _fail() {
    if (!mounted) return;
    Navigator.of(context).maybePop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('A frissítés nem sikerült. Próbáld később.')),
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Frissítés'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        LinearProgressIndicator(value: _progress),
        const SizedBox(height: 14),
        Text(_label),
      ],
    ),
  );
}
