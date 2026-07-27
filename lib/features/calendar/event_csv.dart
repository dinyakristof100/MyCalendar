import 'calendar_service.dart';

/// A naptármentés CSV-formátuma — ugyanaz az oszlopszerkezet, amit az nCalendar
/// biztonsági mentése ír, hogy az onnan hozott fájl közvetlenül importálható
/// legyen:
///
/// ```
/// Title,Color,AllDay,StartTime,EndTime,RRule,XDate,Alert,Place,UrlEvent,Note
/// ```
///
/// Az időpontok epoch-milliszekundumok. Egész napos eseménynél a mentés a nap
/// **UTC éjfelét** tárolja — ugyanaz a szabály, mint amit az Android ad
/// (lásd [parseEvent]), és tilos időzónát váltva értelmezni.
///
/// Az oszlopok közül a Color (az nCalendar saját palettájának indexe), az XDate,
/// az Alert és az UrlEvent nem fordítható át az app fogalmaira — ezeket az
/// import átugorja, az export üresen hagyja.
const _columns = [
  'Title',
  'Color',
  'AllDay',
  'StartTime',
  'EndTime',
  'RRule',
  'XDate',
  'Alert',
  'Place',
  'UrlEvent',
  'Note',
];

/// Egy sor a mentésfájlból, már az app időkezelése szerint.
class CsvEvent {
  const CsvEvent({
    required this.title,
    required this.at,
    required this.end,
    required this.allDay,
    this.rrule,
    this.description,
    this.location,
  });

  final String title;

  /// Helyi kezdés. Egész naposnál a nap helyi éjfele — pont az az érték, amit
  /// [parseEvent] is előállít, így a kettő összehasonlítható ([eventKey]).
  final DateTime at;
  final DateTime end;
  final bool allDay;
  final String? rrule;
  final String? description;
  final String? location;

  String get key => eventKey(title, at, allDay);
}

/// Az „ez ugyanaz az esemény" kulcs: cím + kezdés + egész napos jelleg. Az
/// import ezzel dönti el, hogy a fájl egy sora már benne van-e a naptárban.
///
/// A cím kis-nagybetűre és a széli szóközökre érzéketlen: ugyanazt az eseményt
/// ne hozzuk be másodszor csak azért, mert máshogy van írva. A hely és a jegyzet
/// szándékosan nincs benne — ugyanaz az esemény két forrásból eltérő leírással
/// is jöhet, attól még nem két esemény.
String eventKey(String title, DateTime at, bool allDay) =>
    '${title.trim().toLowerCase()}|${at.millisecondsSinceEpoch}|$allDay';

/// A mentésfájl eseménysorai.
///
/// A fejléc ELŐTTI sorokat átugorja (az nCalendar egy azonosítót ír a fájl
/// elejére), az oszlopokat név szerint keresi (nem sorszám szerint), a hibás
/// vagy cím nélküli sorokat pedig csendben kihagyja — egy elrontott sor miatt
/// ne bukjon el az egész import.
List<CsvEvent> parseBackupCsv(String text) {
  // A fájl elején álló BOM-mal nem kell külön foglalkozni: a `trim()` az
  // U+FEFF-et is whitespace-nek veszi, tehát az első oszlopnévről lejön.
  final rows = parseCsvRows(text);
  final headerIndex = rows.indexWhere(
    (row) => row.any((cell) => cell.trim().toLowerCase() == 'starttime'),
  );
  if (headerIndex < 0) return const [];

  final header = [
    for (final cell in rows[headerIndex]) cell.trim().toLowerCase(),
  ];
  // Null-aware elem: a feldolgozhatatlan sor egyszerűen kimarad.
  return [
    for (final row in rows.skip(headerIndex + 1)) ?_rowToEvent(header, row),
  ];
}

CsvEvent? _rowToEvent(List<String> header, List<String> row) {
  String? value(String column) {
    final index = header.indexOf(column);
    if (index < 0 || index >= row.length) return null;
    final text = row[index].trim();
    return text.isEmpty ? null : text;
  }

  final title = value('title');
  final startMs = int.tryParse(value('starttime') ?? '');
  // Cím vagy kezdés nélkül nincs mit létrehozni.
  if (title == null || startMs == null) return null;

  final allDay = (value('allday') ?? '').toLowerCase() == 'true';
  // Egész naposnál a naptári nap MEZŐIT vesszük át az UTC értékből, nem az
  // abszolút időpontot váltjuk át: pozitív eltolású zónában (mint a magyar) az
  // átváltás az előző napra csúsztatna.
  final utc = DateTime.fromMillisecondsSinceEpoch(startMs, isUtc: true);
  final at = allDay
      ? DateTime(utc.year, utc.month, utc.day)
      : DateTime.fromMillisecondsSinceEpoch(startMs);
  final endMs = int.tryParse(value('endtime') ?? '') ?? startMs;

  return CsvEvent(
    title: title,
    at: at,
    // Egész naposnál a vég úgyis a napból számolódik (lásd `_when`), a mentés is
    // csak megismétli ott a kezdést.
    end: allDay ? at : clampEnd(at, DateTime.fromMillisecondsSinceEpoch(endMs)),
    allDay: allDay,
    rrule: value('rrule'),
    description: value('note'),
    location: value('place'),
  );
}

/// A megadott eseményekből mentésfájl, ugyanabban az oszlopszerkezetben, amit
/// [parseBackupCsv] olvas.
///
/// Ismétlődő eseménynél minden ELŐFORDULÁS ugyanazt a sort viseli (az `id` a
/// sorozaté), ezért azonosítónként csak egy sor kerül ki — különben a
/// visszaimportálás előfordulásonként egy-egy új sorozatot hozna létre.
String buildBackupCsv(List<CalendarEvent> events) {
  final seen = <String>{};
  final csv = StringBuffer()..writeln(_columns.join(','));
  for (final event in events) {
    if (!seen.add(event.id)) continue;
    // Egész naposnál a mentés UTC éjfelet tárol, és a véget a kezdéssel
    // azonosnak — ezt várja vissza az import is.
    final begin = event.allDay ? utcMidnight(event.at) : event.at;
    final end = event.allDay ? begin : (event.end ?? event.at);
    csv.writeln(
      [
        _field(event.title),
        '0', // Color: a kategóriaszín nem fér bele ebbe a formátumba.
        '${event.allDay}',
        '${begin.millisecondsSinceEpoch}',
        '${end.millisecondsSinceEpoch}',
        _field(event.rrule),
        '', // XDate
        '', // Alert: az emlékeztetőket az app maga ütemezi.
        _field(event.location),
        '', // UrlEvent
        _field(event.description),
      ].join(','),
    );
  }
  return csv.toString();
}

/// Idézőjelet, vesszőt vagy sortörést tartalmazó mezőt idézni kell.
final _needsQuotes = RegExp('[",\r\n]');

String _field(String? value) {
  final text = value ?? '';
  return _needsQuotes.hasMatch(text) ? '"${text.replaceAll('"', '""')}"' : text;
}

/// CSV-bontás az RFC 4180 szerint: idézőjeles mezők, bennük vesszővel,
/// sortöréssel és `""`-ként írt idézőjellel.
///
/// Kézzel, mert a mentés jegyzet-oszlopa többsoros (az ünnepnapoknál például
/// három sor), tehát a „soronként vesszőre vágom" nem működik — és egy CSV-
/// csomag ennél nem tudna többet. A csupa üres sorokat (fájl végi sortörés)
/// eldobja.
List<List<String>> parseCsvRows(String text) {
  final rows = <List<String>>[];
  final field = StringBuffer();
  var row = <String>[];
  var quoted = false;

  void endField() {
    row.add(field.toString());
    field.clear();
  }

  void endRow() {
    endField();
    if (row.any((cell) => cell.isNotEmpty)) rows.add(row);
    row = [];
  }

  for (var i = 0; i < text.length; i++) {
    final char = text[i];
    if (quoted) {
      if (char != '"') {
        field.write(char);
      } else if (i + 1 < text.length && text[i + 1] == '"') {
        field.write('"'); // `""` a mezőn belüli idézőjel
        i++;
      } else {
        quoted = false;
      }
    } else if (char == '"') {
      quoted = true;
    } else if (char == ',') {
      endField();
    } else if (char == '\n' || char == '\r') {
      if (char == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
      endRow();
    } else {
      field.write(char);
    }
  }
  // Sortörés nélkül végződő fájl utolsó sora.
  if (field.isNotEmpty || row.isNotEmpty) endRow();
  return rows;
}
