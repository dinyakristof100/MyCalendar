import 'calendar_service.dart';

/// Egy nap eseményei, a listában megjelenő fejléccel.
class EventDay {
  const EventDay({
    required this.date,
    required this.label,
    required this.events,
    required this.isToday,
  });

  final DateTime date;
  final String label;
  final List<CalendarEvent> events;
  final bool isToday;
}

const _weekdays = [
  'hétfő',
  'kedd',
  'szerda',
  'csütörtök',
  'péntek',
  'szombat',
  'vasárnap',
];

const _months = [
  'január',
  'február',
  'március',
  'április',
  'május',
  'június',
  'július',
  'augusztus',
  'szeptember',
  'október',
  'november',
  'december',
];

/// A hónap magyar neve (1 = január).
String monthName(int month) => _months[month - 1];

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// „Ma”, „Holnap”, egyébként „július 25., szombat”.
///
/// A közeli napokat nem dátumként nevezzük meg, mert senki nem így gondol
/// rájuk — a naptárt azért nézed meg, hogy megtudd, mi jön, nem azért, hogy
/// dátumot olvass.
String dayLabel(DateTime day, {required DateTime today}) {
  final days = _dateOnly(day).difference(_dateOnly(today)).inDays;
  if (days == 0) return 'Ma';
  if (days == 1) return 'Holnap';
  return '${_months[day.month - 1]} ${day.day}., ${_weekdays[day.weekday - 1]}';
}

/// Mennyi idő van hátra az eseményig: egy napon túl napokban ÉS órákban, egy
/// napon belül órákban, egy órán belül percekben.
///
/// A kerek egységet nem írjuk ki nullával („3 nap 0 óra" helyett „3 nap").
///
/// Az egész napos eseménynek nincs kezdési ideje — nála az éjfélig hátralévő
/// órák helyett a naptári napok különbsége a válasz. A már elkezdődött (vagy a
/// mai egész napos) eseménynél `null`: nincs mit visszaszámolni.
String? timeLeftLabel(CalendarEvent event, DateTime now) {
  if (event.allDay) {
    final days = _dateOnly(event.at).difference(_dateOnly(now)).inDays;
    return days > 0 ? '$days nap múlva' : null;
  }
  final left = event.at.difference(now);
  if (left.isNegative) return null;
  if (left.inDays > 0) {
    final hours = left.inHours % 24;
    final rest = hours == 0 ? '' : ' $hours óra';
    return '${left.inDays} nap$rest múlva';
  }
  if (left.inHours > 0) return '${left.inHours} óra múlva';
  if (left.inMinutes > 0) return '${left.inMinutes} perc múlva';
  return 'Most kezdődik';
}

/// Hányadik elem ELŐTT álljon a „most" vonal egy nap (rendezett) listájában.
///
/// Az első még hátralévő esemény indexe; ha már mind elmúlt, a lista hossza —
/// a vonal ilyenkor a nap végére kerül. Az egész naposak elöl állnak és nincs
/// értelmes idejük, ezért őket a vonal mindig maga mögött hagyja.
int nowMarkerIndex(List<CalendarEvent> dayEvents, DateTime now) {
  for (var i = 0; i < dayEvents.length; i++) {
    if (dayEvents[i].allDay) continue;
    if (dayEvents[i].at.isAfter(now)) return i;
  }
  return dayEvents.length;
}

/// Ennyi eseménysáv fér ki egy naptári nap csempéjén. A fölötte lévő
/// események a rácsban nem látszanak — a nap kiválasztásakor a lista alatta
/// viszont mindet felsorolja.
const maxDayLanes = 3;

/// Sávkiosztás a hónaprácshoz: melyik esemény a nap hányadik sávjába kerül.
///
/// A több napon átnyúló esemény MINDEN napján ugyanabba a sávba kerül — csak
/// így látszik a rácsban folytonos sávnak. Ezért nem naponként osztunk sávot,
/// hanem eseményenként: a hosszabbak választanak először, és mindegyik a
/// legfelső olyan sávot kapja, ami az összes napján szabad.
///
/// A visszaadott lista mindig [maxDayLanes] hosszú, a `null` elem üres sáv.
/// Sávok között lyuk nem keletkezik: mindenki a legfelső szabad sávot kapja.
Map<DateTime, List<CalendarEvent?>> assignEventLanes(
  Map<DateTime, List<CalendarEvent>> byDay,
) {
  // Esemény -> mely napokon szerepel. A kulcs maga az objektum, nem az id: az
  // ismétlődő esemény minden előfordulása ugyanazt az id-t viseli, de külön
  // eseményként kap sávot.
  final spans = <CalendarEvent, List<DateTime>>{};
  for (final entry in byDay.entries) {
    for (final event in entry.value) {
      spans.putIfAbsent(event, () => []).add(entry.key);
    }
  }

  final events = spans.keys.toList()
    ..sort((a, b) {
      // A hosszabb sáv választ előbb: a több napos esemény kerül felülre, így a
      // folytonosságát nem töri meg egy alá kerülő egynapos.
      final byLength = spans[b]!.length.compareTo(spans[a]!.length);
      if (byLength != 0) return byLength;
      if (a.allDay != b.allDay) return a.allDay ? -1 : 1;
      return a.at.compareTo(b.at);
    });

  final lanes = <DateTime, List<CalendarEvent?>>{};
  for (final event in events) {
    final days = spans[event]!;
    var lane = 0;
    while (lane < maxDayLanes && days.any((day) => lanes[day]?[lane] != null)) {
      lane++;
    }
    // Nem fér ki: valamelyik napján már mind a három sáv foglalt.
    if (lane == maxDayLanes) continue;
    for (final day in days) {
      lanes.putIfAbsent(
        day,
        () => List<CalendarEvent?>.filled(maxDayLanes, null),
      )[lane] = event;
    }
  }
  return lanes;
}

/// Napokra bontja az eseményeket, a napokat időrendben adja vissza.
///
/// Egy napon belül az egész naposak állnak elöl: az egész napra vonatkoznak,
/// nincs helyük az órarendben. Utánuk a többi kezdés szerint.
List<EventDay> groupByDay(
  List<CalendarEvent> events, {
  required DateTime today,
}) {
  final byDay = <DateTime, List<CalendarEvent>>{};
  for (final event in events) {
    byDay.putIfAbsent(_dateOnly(event.at), () => []).add(event);
  }

  final days = byDay.keys.toList()..sort();
  return [
    for (final day in days)
      EventDay(
        date: day,
        label: dayLabel(day, today: today),
        isToday: day == _dateOnly(today),
        events: byDay[day]!
          ..sort((a, b) {
            if (a.allDay != b.allDay) return a.allDay ? -1 : 1;
            return a.at.compareTo(b.at);
          }),
      ),
  ];
}
