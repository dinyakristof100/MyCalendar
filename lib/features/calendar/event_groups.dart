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
