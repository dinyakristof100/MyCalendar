import 'package:flutter_test/flutter_test.dart';
import 'package:my_calendar/features/calendar/calendar_service.dart';
import 'package:my_calendar/features/calendar/event_groups.dart';

final _today = DateTime(2026, 7, 22, 10);

CalendarEvent _event(DateTime at, {bool allDay = false, String title = 'x'}) =>
    CalendarEvent(id: '$at$title', title: title, at: at, allDay: allDay);

void main() {
  test('a közeli napok nevet kapnak, a távoliak dátumot', () {
    expect(dayLabel(DateTime(2026, 7, 22, 23), today: _today), 'Ma');
    expect(dayLabel(DateTime(2026, 7, 23), today: _today), 'Holnap');
    expect(
      dayLabel(DateTime(2026, 7, 25), today: _today),
      'július 25., szombat',
    );
  });

  test('napokra bont és időrendbe rakja a napokat', () {
    final days = groupByDay([
      _event(DateTime(2026, 7, 25, 9)),
      _event(DateTime(2026, 7, 22, 14)),
      _event(DateTime(2026, 7, 22, 8)),
    ], today: _today);

    expect(days.map((d) => d.label), ['Ma', 'július 25., szombat']);
    expect(days.first.events.length, 2);
    expect(days.first.isToday, isTrue);
    expect(days.last.isToday, isFalse);
  });

  test('egy napon belül az egész naposak állnak elöl', () {
    final days = groupByDay([
      _event(DateTime(2026, 7, 22, 14), title: 'délután'),
      _event(DateTime(2026, 7, 22), allDay: true, title: 'egész nap'),
      _event(DateTime(2026, 7, 22, 8), title: 'reggel'),
    ], today: _today);

    expect(days.single.events.map((e) => e.title), [
      'egész nap',
      'reggel',
      'délután',
    ]);
  });
}
