import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/files.dart';
import '../auth/auth_controller.dart';
import '../calendar/calendar_service.dart';
import '../calendar/event_csv.dart';

/// Az export időablaka: egy évvel vissza, öt évre előre. Ennyi az, aminek egy
/// mentésben értelme van — a naptár ismétlődő eseményeit a rendszer minden
/// előfordulásra kibontja, ezért a „mindent, mindörökre" itt nem ingyenes.
const _past = Duration(days: 365);
const _future = Duration(days: 5 * 365);

/// Események importálása és exportálása CSV-ben — a Beállítások „Adatok"
/// szakasza.
///
/// Import: a rendszer fájlválasztójából jövő mentés sorai bekerülnek a
/// bejelentkezett fiók naptárába (ugyanoda, ahova az app saját + gombja ír),
/// tehát a Google onnan a felhőbe is felviszi őket. Ami már szerepel a
/// naptárban, azt nem hozzuk létre újra (lásd [eventKey]).
///
/// Export: a bekapcsolt naptárak eseményeiből fájl készül, és a rendszer saját
/// megosztó-ablaka nyílik meg rá (e-mail, üzenet, Bluetooth, felhő).
class ImportExportTiles extends ConsumerWidget {
  const ImportExportTiles({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Column(
    children: [
      ListTile(
        leading: const Icon(Icons.file_download_outlined),
        title: const Text('Események importálása'),
        subtitle: const Text(
          'CSV-mentésből. A már meglévő eseményeket kihagyjuk, az újak a '
          'Google-naptáradba kerülnek — onnan a felhőbe is szinkronizálódnak.',
        ),
        onTap: () => _import(context, ref),
      ),
      ListTile(
        leading: const Icon(Icons.file_upload_outlined),
        title: const Text('Események exportálása'),
        subtitle: const Text(
          'A bekapcsolt naptárak eseményeiből CSV-fájl készül, amit rögtön '
          'küldhetsz is e-mailben, üzenetben vagy Bluetooth-on.',
        ),
        onTap: () => _export(context, ref),
      ),
    ],
  );
}

Future<void> _import(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  void toast(String text) =>
      messenger.showSnackBar(SnackBar(content: Text(text)));

  final String? text;
  try {
    text = await pickTextFile();
  } on PlatformException catch (e) {
    toast('Nem sikerült megnyitni a fájlt: ${e.message}');
    return;
  }
  if (text == null) return; // a felhasználó elvetette

  final rows = parseBackupCsv(text);
  if (rows.isEmpty) {
    toast('Ebben a fájlban nem találtunk eseményt.');
    return;
  }

  final List<CsvEvent> fresh;
  try {
    fresh = await _newOnes(rows);
  } on PlatformException catch (e) {
    toast(
      e.code == permissionDeniedCode
          ? 'Engedélyezd a naptár olvasását, majd próbáld újra.'
          : 'Nem sikerült beolvasni a naptárat: ${e.message}',
    );
    return;
  }
  if (fresh.isEmpty) {
    toast('Mind a ${rows.length} esemény már szerepel a naptáradban.');
    return;
  }
  if (!context.mounted) return;

  final go = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Események importálása'),
      content: Text(
        'A fájlban ${rows.length} esemény van, ebből ${fresh.length} új — '
        'a többi már szerepel a naptáradban.\n\n'
        'Az újak a Google-naptáradba kerülnek.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Mégsem'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text('${fresh.length} esemény'),
        ),
      ],
    ),
  );
  if (!(go ?? false) || !context.mounted) return;

  final result = await showDialog<_ImportResult>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ImportProgress(
      rows: fresh,
      // Ugyanaz a célnaptár, mint az app saját eseményfelvitelénél: a
      // bejelentkezett fiók naptára. Enélkül a natív oldal a készülék első
      // írható naptárát venné, ami több fióknál könnyen valaki másé.
      calendarId: writeTargetId(
        ref.read(deviceCalendarsProvider).value ?? const [],
        ref.read(currentUserProvider).value?.email,
      ),
    ),
  );
  if (result == null) return;

  ref.invalidate(upcomingEventsProvider);
  ref.invalidate(monthEventsProvider);
  toast(
    result.error == null
        ? '${result.created} esemény bekerült a naptáradba.'
        : '${result.created} esemény bekerült, aztán megakadtunk: '
              '${result.error}',
  );
}

/// A fájl sorai közül azok, amik még nincsenek benne a naptárban.
Future<List<CsvEvent>> _newOnes(List<CsvEvent> rows) async {
  var first = rows.first.at;
  var last = rows.first.at;
  for (final row in rows) {
    if (row.at.isBefore(first)) first = row.at;
    if (row.at.isAfter(last)) last = row.at;
  }
  // Naptárszűrő nélkül: a kikapcsolt naptárban lévő esemény is létezik, azt sem
  // akarjuk megduplázni.
  //
  // ponytail: egyetlen lekérdezés a fájl teljes időablakára. Évtizedes mentésnél
  // ez sok sort bont ki, de a felhasználó indítja, egyszer. Ha lassúnak
  // bizonyul, itt jön az évenkénti darabolás.
  final existing = await eventsBetween(
    first,
    last.add(const Duration(days: 1)),
  );
  final keys = {
    for (final event in existing) eventKey(event.title, event.at, event.allDay),
  };
  return [
    for (final row in rows)
      // A hozzáadás egyben a szűrés: a fájlon belüli ismétlődő sorok is csak
      // egyszer jönnek be.
      if (keys.add(row.key)) row,
  ];
}

Future<void> _export(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  void toast(String text) =>
      messenger.showSnackBar(SnackBar(content: Text(text)));

  try {
    final ids = await ref.read(visibleCalendarIdsProvider.future);
    if (ids.isEmpty) {
      toast('Egy naptár sincs bekapcsolva, így nincs mit exportálni.');
      return;
    }
    final now = DateTime.now();
    final events = await eventsBetween(
      now.subtract(_past),
      now.add(_future),
      calendarIds: ids,
    );
    if (events.isEmpty) {
      toast('Nincs exportálható esemény.');
      return;
    }
    await shareTextFile(_fileName(now), buildBackupCsv(events));
  } on PlatformException catch (e) {
    toast(
      e.code == permissionDeniedCode
          ? 'Engedélyezd a naptár olvasását, majd próbáld újra.'
          : 'Nem sikerült elkészíteni a mentést: ${e.message}',
    );
  }
}

/// `backup_mycalendar_2026_07_27_09_07_38.csv` — dátumos név, hogy a megosztott
/// fájlok ne mossák egymást össze.
String _fileName(DateTime now) {
  String two(int value) => value.toString().padLeft(2, '0');
  return 'backup_mycalendar_${now.year}_${two(now.month)}_${two(now.day)}_'
      '${two(now.hour)}_${two(now.minute)}_${two(now.second)}.csv';
}

class _ImportResult {
  const _ImportResult(this.created, this.error);

  final int created;

  /// Az első elakadás üzenete, vagy `null`, ha minden sor bement.
  final String? error;
}

/// A beírás párbeszédablakon belül fut, és magát zárja be az eredménnyel — így
/// nem kell a folyamat körül navigátort zsonglőrködni.
class _ImportProgress extends StatefulWidget {
  const _ImportProgress({required this.rows, required this.calendarId});

  final List<CsvEvent> rows;
  final int? calendarId;

  @override
  State<_ImportProgress> createState() => _ImportProgressState();
}

class _ImportProgressState extends State<_ImportProgress> {
  int _done = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  Future<void> _run() async {
    String? error;
    for (final row in widget.rows) {
      try {
        await createEvent(
          title: row.title,
          start: row.at,
          end: row.end,
          allDay: row.allDay,
          rrule: row.rrule,
          calendarId: widget.calendarId,
          description: row.description,
          location: row.location,
        );
      } on PlatformException catch (e) {
        // Az első elakadásnál megállunk: ami ilyenkor romlik el (engedély, tele
        // tár), az a következő sornál is elromlana. Az addig bekerültek
        // maradnak — az újrafuttatás pont onnan folytatja, ahol abbamaradt.
        error = e.code == permissionDeniedCode
            ? 'engedélyezd a naptár írását'
            : e.message;
        break;
      }
      if (!mounted) return;
      setState(() => _done++);
    }
    if (mounted) Navigator.pop(context, _ImportResult(_done, error));
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.rows.length;
    // A félbehagyott import fél naptárat hagyna: a vissza gomb nem zárhatja be.
    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: const Text('Importálás…'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LinearProgressIndicator(value: total == 0 ? null : _done / total),
            const SizedBox(height: 14),
            Text('$_done / $total esemény'),
          ],
        ),
      ),
    );
  }
}
