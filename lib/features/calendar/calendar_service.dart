import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

/// Új esemény beírása az eszköz naptárába. Több napon átnyúlhat.
///
/// A hívó dolga frissíteni a listát — az `upcomingEventsProvider`
/// érvénytelenítése az emlékeztetőket is újraütemezi.
Future<void> createEvent({
  required String title,
  required DateTime start,
  required DateTime end,
}) => _channel.invokeMethod<String>('createEvent', {
  'title': title,
  'begin': start.millisecondsSinceEpoch,
  'end': end.millisecondsSinceEpoch,
});

/// Meglévő esemény címének és időpontjának felülírása. Csak ezt a három mezőt
/// írja — a leírást és a helyet a natív oldal érintetlenül hagyja.
Future<void> updateEvent({
  required String id,
  required String title,
  required DateTime start,
  required DateTime end,
}) => _channel.invokeMethod<void>('updateEvent', {
  'id': id,
  'title': title,
  'begin': start.millisecondsSinceEpoch,
  'end': end.millisecondsSinceEpoch,
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
  });

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

/// A következő 14 nap eseményei az eszköz naptárából, kezdés szerint rendezve.
///
/// Nincs OAuth scope és nincs hálózati hívás: a naptár már szinkronizálva van a
/// készüléken. A rendezést és az ismétlődő események előfordulásokra bontását
/// az Android `Instances` táblája végzi.
final upcomingEventsProvider = FutureProvider<List<CalendarEvent>>((ref) async {
  final raw = await _channel.invokeMethod<List<Object?>>('upcomingEvents', {
    'days': _days,
  });
  return [
    for (final event in raw ?? const <Object?>[])
      parseEvent((event! as Map).cast<String, Object?>()),
  ];
});

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
    FutureProvider.family<List<CalendarEvent>, DateTime>((ref, month) async {
      final start = gridStart(month);
      final end = DateTime(start.year, start.month, start.day + gridDays);
      final raw = await _channel.invokeMethod<List<Object?>>('eventsInRange', {
        'begin': start.millisecondsSinceEpoch,
        'end': end.millisecondsSinceEpoch,
      });
      return [
        for (final event in raw ?? const <Object?>[])
          parseEvent((event! as Map).cast<String, Object?>()),
      ];
    });
