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
      ..set(
        HttpHeaders.userAgentHeader,
        'MyCalendar-updater',
      ) // GitHub kötelező
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

/// Fut-e már egy frissítés — letöltés, vagy a rendszer telepítője.
///
/// A telepítő és a Play Protect ellenőrzése alatt az app `resume`-ot kap, az
/// pedig újra felajánlaná ugyanazt a verziót (telepítve még nincs) — a
/// türelmetlen felhasználó így indítana egy második letöltést. Amíg ez igaz,
/// nem ajánlunk semmit.
///
/// Sikeres telepítéskor a folyamat úgyis lecserélődik; ha a felhasználó
/// elutasítja a rendszer telepítőjét, a következő appindítás megint felajánlja.
bool _updateInFlight = false;

/// Megnyitáskor: ha van újabb kiadás, felajánlja, és elfogadásra le is futtatja a
/// frissítést. Bárhol hiba/nincs újdonság → csendben nem történik semmi.
Future<void> maybePromptUpdate(BuildContext context) async {
  if (_updateInFlight) return;
  final info = await checkForUpdate();
  if (info == null || !context.mounted || _updateInFlight) return;

  final accepted = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Új verzió elérhető'),
      content: const Text(
        'Elérhető egy frissebb verzió, ajánlott telepíteni. '
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
    _updateInFlight = true;
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
/// telepítője veszi át — a párbeszéd ilyenkor is nyitva marad (csak a „Bezárás"
/// gomb viszi el), mert a rendszer ablaka pár másodperc késéssel jön. Hibánál
/// bezárjuk, egy visszajelzéssel: a felhasználó a régi verzión marad, semmi sem
/// törik.
class _UpdateProgressDialog extends StatefulWidget {
  const _UpdateProgressDialog();

  @override
  State<_UpdateProgressDialog> createState() => _UpdateProgressDialogState();
}

class _UpdateProgressDialogState extends State<_UpdateProgressDialog> {
  double? _progress;
  String _label = 'Letöltés előkészítése…';

  /// A rendszer telepítője átvette. Ilyenkor a párbeszéd bezárható — de csak
  /// gombbal, és a következő felajánlás így is elmarad ([_updateInFlight]).
  bool _handedOff = false;

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
        // appot). NEM zárjuk be a párbeszédet: a telepítő ablaka csak pár
        // másodperc múlva ugrik fel — a Play Protect addig ellenőriz —, és a
        // felszabaduló felületen a türelmetlen felhasználó újrakezdené az
        // egészet.
        setState(() {
          _handedOff = true;
          _progress = 1;
          _label =
              'Letöltve. A telepítést a rendszer végzi — ha nem ugrik fel '
              'azonnal, még tart a Play Protect ellenőrzése.';
        });
      default:
        _fail(); // engedélyhiány, letöltési hiba, checksum stb.
    }
  }

  void _fail() {
    // Nem sikerült: szabad az út egy újabb próbálkozásnak.
    _updateInFlight = false;
    if (!mounted) return;
    Navigator.of(context).maybePop();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('A frissítés nem sikerült. Próbáld később.'),
      ),
    );
  }

  // A vissza gomb sem zárja be: a letöltés natívan futna tovább, a felhasználó
  // pedig a szabaddá vált felületről indíthatna egy másodikat.
  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    child: AlertDialog(
      title: const Text('Frissítés'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LinearProgressIndicator(value: _progress),
          const SizedBox(height: 14),
          Text(_label),
        ],
      ),
      actions: [
        if (_handedOff)
          TextButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: const Text('Bezárás'),
          ),
      ],
    ),
  );
}
