import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/cloud_sync.dart';
import '../../core/prefs.dart';

/// Az eszköz naptárát olvasó és író natív csatorna (lásd `MainActivity.kt`).
const _channel = MethodChannel('mycalendar/device_calendar');

const _days = 14;

/// A natív oldal ezzel jelzi, hogy a felhasználó még nem adta meg a
/// naptár-engedélyt.
const permissionDeniedCode = 'PERMISSION_DENIED';

/// A vége sosem előzheti meg a kezdést — a naptár se fogadna el ilyet. A
/// visszafelé állított véget egyórás eseménnyé igazítjuk.
DateTime clampEnd(DateTime start, DateTime end) =>
    end.isAfter(start) ? end : start.add(const Duration(hours: 1));

/// A [day] naptári napjának UTC éjfele — ezt várja az Android egész napos
/// esemény kezdéseként.
///
/// `toUtc()` itt hibás lenne: az abszolút időpontot váltaná át, és pozitív
/// eltolású zónában (mint a magyar) az előző napra csúszna. A naptári nap
/// mezőit kell átvenni, az időpontot eldobva.
DateTime utcMidnight(DateTime day) =>
    DateTime.utc(day.year, day.month, day.day);

/// A natív oldal idő-argumentumai.
///
/// Egész naposnál a kezdés a választott nap UTC éjfele, a vége a következő nap
/// UTC éjfele — az Android félig nyílt intervallumot vár, és UTC-ben nincs
/// nyári időszámítás, tehát a nap pontosan 24 óra.
Map<String, Object?> _when(DateTime start, DateTime end, bool allDay) {
  final begin = allDay ? utcMidnight(start) : start;
  return {
    'begin': begin.millisecondsSinceEpoch,
    'end': (allDay ? begin.add(const Duration(days: 1)) : end)
        .millisecondsSinceEpoch,
    'allDay': allDay,
  };
}

/// A felkínált ismétlődések. Egyedi szabály (minden 2. hét, végdátum, N alkalom)
/// nincs — az esemény vagy ismétlődik így, vagy nem.
enum Recurrence { none, daily, weekly, yearly }

/// Az RFC 5545 napkódjai a [DateTime.weekday] sorrendjében (1 = hétfő).
const _byDay = ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU'];

/// A választott ismétlődés szabálya a naptárnak, vagy `null`, ha nem ismétlődik.
/// A heti szabály napja a kezdés napjából jön — „hetente ugyanezen a napon".
String? rruleFor(Recurrence recurrence, DateTime start) => switch (recurrence) {
  Recurrence.none => null,
  Recurrence.daily => 'FREQ=DAILY',
  Recurrence.weekly => 'FREQ=WEEKLY;BYDAY=${_byDay[start.weekday - 1]}',
  Recurrence.yearly => 'FREQ=YEARLY',
};

/// Új esemény beírása az eszköz naptárába. Több napon átnyúlhat. Az új esemény
/// azonosítójával tér vissza — erre kötjük pl. a kategória-hozzárendelést.
///
/// [rrule] megadva ismétlődő sorozat jön létre (lásd [rruleFor]).
///
/// A hívó dolga frissíteni a listát — az `upcomingEventsProvider`
/// érvénytelenítése az emlékeztetőket is újraütemezi.
Future<String?> createEvent({
  required String title,
  required DateTime start,
  required DateTime end,
  bool allDay = false,
  String? rrule,
}) => _channel.invokeMethod<String>('createEvent', {
  'title': title,
  // Null-aware kulcs: nem ismétlődőnél a kulcs is elmarad — a natív oldal ezt
  // veszi „nem sorozat"-nak.
  'rrule': ?rrule,
  ..._when(start, end, allDay),
});

/// Meglévő esemény címének, időpontjának és egész napos jellegének felülírása.
/// Csak ezeket írja — a leírást és a helyet a natív oldal érintetlenül hagyja.
///
/// Ismétlődő eseménynél a hívó adja vissza a meglévő [rrule]-t: a natív oldal
/// enélkül DTEND-et írna a sorozat DURATION-je helyett, és a mentés elhasalna.
/// A módosítás ilyenkor az **egész sorozatra** hat.
Future<void> updateEvent({
  required String id,
  required String title,
  required DateTime start,
  required DateTime end,
  bool allDay = false,
  String? rrule,
}) => _channel.invokeMethod<void>('updateEvent', {
  'id': id,
  'title': title,
  // Null-aware kulcs: nem ismétlődőnél a kulcs is elmarad — a natív oldal ezt
  // veszi „nem sorozat"-nak.
  'rrule': ?rrule,
  ..._when(start, end, allDay),
});

/// Esemény törlése az eszköz naptárából.
Future<void> deleteEvent(String id) =>
    _channel.invokeMethod<void>('deleteEvent', {'id': id});

/// Egy naptáresemény annyi mezővel, amennyit az app tényleg használ.
class CalendarEvent {
  const CalendarEvent({
    required this.id,
    required this.title,
    required this.at,
    required this.allDay,
    this.end,
    this.description,
    this.location,
    this.rrule,
  });

  /// Az esemény **sorának** azonosítója (`Instances.EVENT_ID`), nem az egyes
  /// előfordulásé — ismétlődőnél minden előfordulás ugyanezt viseli.
  final String id;
  final String title;
  final DateTime at;
  final bool allDay;

  /// A befejezés ideje. Egész napos eseménynél `null` — ott az Android a
  /// következő nap UTC éjfelét adja, ami nem megmutatható időpont.
  final DateTime? end;

  /// Üres helyett `null`: a részletek lapon így elég a létezésüket vizsgálni.
  final String? description;
  final String? location;

  /// A sorozat ismétlődési szabálya, ha ez egy ismétlődő esemény előfordulása.
  final String? rrule;

  /// Ismétlődő-e — a szerkesztés és a törlés ilyenkor az egész sorozatra hat,
  /// ezért a UI figyelmeztet.
  bool get recurring => rrule != null;
}

String? _text(Object? value) {
  final text = (value as String?)?.trim();
  return text == null || text.isEmpty ? null : text;
}

/// A natív oldalról érkező nyers map átalakítása.
///
/// Egész napos eseménynél az Android a kezdést **UTC éjfélként** adja meg, nem
/// helyi időként. Ezt tilos időzónát váltva értelmezni, mert átcsúszna a
/// szomszédos napra — ezért olvassuk ki a dátumot UTC-ben, és építünk belőle
/// helyi dátumot.
CalendarEvent parseEvent(Map<String, Object?> raw) {
  final allDay = raw['allDay'] == true;
  final begin = raw['begin']! as int;
  final end = raw['end'] as int?;
  final title = (raw['title'] as String?) ?? '';
  final utc = DateTime.fromMillisecondsSinceEpoch(begin, isUtc: true);

  return CalendarEvent(
    id: raw['id']! as String,
    title: title.isEmpty ? '(névtelen esemény)' : title,
    at: allDay
        ? DateTime(utc.year, utc.month, utc.day)
        : DateTime.fromMillisecondsSinceEpoch(begin),
    end: allDay || end == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(end),
    allDay: allDay,
    description: _text(raw['description']),
    location: _text(raw['location']),
    rrule: _text(raw['rrule']),
  );
}

String _pad(int n) => n.toString().padLeft(2, '0');

/// `14:30`.
String hhmm(DateTime time) => '${_pad(time.hour)}:${_pad(time.minute)}';

/// `14:30`. Egész napos eseményre `null` — ott nincs értelmes időpont.
String? formatTime(CalendarEvent event) => event.allDay ? null : hhmm(event.at);

/// `07. 23.` egész naposra, `07. 23. 14:30` időpontosra.
///
/// Az értesítés szövegéhez kell, ahol a dátum sem derül ki a környezetből. A
/// listában ehelyett a napfejléc adja a dátumot, és csak [formatTime] kell.
///
/// ponytail: kézi formázás, mert az app-ban nincs `intl` és nincsenek magyar
/// locale delegate-ek.
String formatStart(CalendarEvent event) {
  final date = '${_pad(event.at.month)}. ${_pad(event.at.day)}.';
  final time = formatTime(event);
  return time == null ? '$date egész nap' : '$date $time';
}

/// Egy eszköz-naptár: ennyit mutat belőle a beállítások szűrője.
class DeviceCalendar {
  const DeviceCalendar({
    required this.id,
    required this.name,
    required this.account,
    required this.color,
  });

  final int id;
  final String name;

  /// A fiók, amihez tartozik (jellemzően e-mail cím) — két azonos nevű naptárt
  /// ez különböztet meg.
  final String account;
  final Color color;

  /// Az elrejtés tárolási kulcsa: fiók + név, NEM az [id]. A két mező
  /// JSON-tömbként áll össze — így nem kell olyan elválasztó jelet keresni, ami
  /// biztosan nem szerepel egyik névben sem.
  ///
  /// Az id eszközspecifikus — ugyanaz a Google-naptár másik telefonon másik
  /// számot kap —, a beállítás viszont a felhőn át eszközök között utazik.
  /// A fiók+név páros ott is ugyanaz.
  String get key => jsonEncode([account, name]);
}

/// Az alapértelmezett naptárszín, ha a naptár nem ad meg sajátot.
const _defaultCalendarColor = Color(0xFF64748B);

/// Az eszközön lévő naptárak. Ritkán változik: a beállítások lapja kéri le,
/// és az esemény-lekérdezések használják a szűréshez.
final deviceCalendarsProvider = FutureProvider<List<DeviceCalendar>>((
  ref,
) async {
  final raw = await _channel.invokeMethod<List<Object?>>('calendars');
  return [
    for (final item in raw ?? const <Object?>[])
      _parseCalendar((item! as Map).cast<String, Object?>()),
  ];
});

DeviceCalendar _parseCalendar(Map<String, Object?> raw) => DeviceCalendar(
  // A naptár id-je `Long`-ként jön, a codec kicsi értéknél `int`-et ad — a
  // `num` mindkettőre illeszkedik.
  id: (raw['id']! as num).toInt(),
  name: (raw['name'] as String?) ?? '(névtelen naptár)',
  account: (raw['account'] as String?) ?? '',
  color: raw['color'] == null
      ? _defaultCalendarColor
      : Color(raw['color']! as int),
);

const _hiddenCalendarsKey = 'hiddenCalendars';

/// Az elrejtett naptárak kulcsai (lásd [DeviceCalendar.key]).
final hiddenCalendarsProvider =
    NotifierProvider<HiddenCalendarsController, Set<String>>(
      HiddenCalendarsController.new,
    );

class HiddenCalendarsController extends Notifier<Set<String>> {
  @override
  Set<String> build() => {
    for (final key
        in jsonDecode(prefs.getString(_hiddenCalendarsKey) ?? '[]') as List)
      key as String,
  };

  /// Egy naptár mutatása/elrejtése. Az esemény-providerek ezt a state-et
  /// figyelik, ezért magától frissül tőle a lista és a naptárnézet is.
  Future<void> setVisible(DeviceCalendar calendar, bool visible) async {
    final next = state.toSet();
    if (visible) {
      next.remove(calendar.key);
    } else {
      next.add(calendar.key);
    }
    state = next;
    await saveSetting(_hiddenCalendarsKey, jsonEncode(next.toList()));
  }
}

/// A látszó naptárak azonosítói: az elrejtetteken kívül minden.
///
/// Ismeretlen — másik eszközön elrejtett, itt nem létező — kulcs nem rejt el
/// semmit: az egyezéseket vesszük ki, nem a nem-egyezéseket tartjuk meg.
List<int> visibleCalendarIds(
  List<DeviceCalendar> calendars,
  Set<String> hidden,
) => [
  for (final calendar in calendars)
    if (!hidden.contains(calendar.key)) calendar.id,
];

/// A natív lekérdezésnek átadandó naptárszűrő.
///
/// `null`: nincs mit szűrni, jöhet minden naptár (ez a szűrő bevezetése előtti
/// viselkedés, és ilyenkor a naptárlistát le sem kell kérni). Üres lista: a
/// felhasználó mindent elrejtett — ilyenkor a hívó meg se kérdezi a naptárat.
Future<List<int>?> _calendarFilter(Ref ref) async {
  final hidden = ref.watch(hiddenCalendarsProvider);
  if (hidden.isEmpty) return null;
  return visibleCalendarIds(
    await ref.watch(deviceCalendarsProvider.future),
    hidden,
  );
}

/// A natív lekérdezés + a szűrő + a nyers map-ek átalakítása egy helyen.
Future<List<CalendarEvent>> _queryEvents(
  Ref ref,
  String method,
  Map<String, Object?> args,
) async {
  final ids = await _calendarFilter(ref);
  // Minden naptár el van rejtve: nincs mit lekérdezni. (Az üres listát a natív
  // oldal „nincs szűrő"-nek venné, és mindent visszaadna.)
  if (ids != null && ids.isEmpty) return const [];
  final raw = await _channel.invokeMethod<List<Object?>>(method, {
    ...args,
    'calendarIds': ?ids,
  });
  return [
    for (final event in raw ?? const <Object?>[])
      parseEvent((event! as Map).cast<String, Object?>()),
  ];
}

/// A következő 14 nap eseményei az eszköz naptárából, kezdés szerint rendezve.
///
/// Nincs OAuth scope és nincs hálózati hívás: a naptár már szinkronizálva van a
/// készüléken. A rendezést és az ismétlődő események előfordulásokra bontását
/// az Android `Instances` táblája végzi.
final upcomingEventsProvider = FutureProvider<List<CalendarEvent>>(
  (ref) => _queryEvents(ref, 'upcomingEvents', {'days': _days}),
);

/// A naptárrács hat sora bármely hónapot lefed.
const gridDays = 42;

/// A [month] rácsának első napja: a hónap 1-jét tartalmazó hét hétfője. A magyar
/// hét hétfővel kezdődik, ezért `weekday - 1` napot lépünk vissza.
DateTime gridStart(DateTime month) {
  final first = DateTime(month.year, month.month, 1);
  return DateTime(first.year, first.month, first.day - (first.weekday - 1));
}

/// Egy hónap rácsát (42 nap) lefedő események az eszköz naptárából.
///
/// A kulcs a hónap első napja `DateTime(év, hónap, 1)` — a [DateTime]
/// értékegyenlőségével a család példányonként cache-el.
final monthEventsProvider =
    FutureProvider.family<List<CalendarEvent>, DateTime>((ref, month) {
      final start = gridStart(month);
      final end = DateTime(start.year, start.month, start.day + gridDays);
      return _queryEvents(ref, 'eventsInRange', {
        'begin': start.millisecondsSinceEpoch,
        'end': end.millisecondsSinceEpoch,
      });
    });
