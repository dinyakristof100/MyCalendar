import 'package:flutter_test/flutter_test.dart';
import 'package:my_calendar/features/calendar/calendar_service.dart';
import 'package:my_calendar/features/calendar/reminders.dart';

CalendarEvent _event(DateTime at, {bool allDay = false}) =>
    CalendarEvent(id: '1', title: 'Teszt', at: at, allDay: allDay);

void main() {
  test('időpontos esemény: pontosan egy nappal korábban, azonos időben', () {
    final when = reminderTime(_event(DateTime(2026, 7, 23, 14, 30)));
    expect(when, DateTime(2026, 7, 22, 14, 30));
  });

  test('egész napos esemény: előző nap este, nem hajnali 0:00-kor', () {
    final when = reminderTime(_event(DateTime(2026, 7, 23), allDay: true));
    expect(when, DateTime(2026, 7, 22, 18));
  });

  test('hónap elején az előző hónap utolsó napjára esik', () {
    final when = reminderTime(_event(DateTime(2026, 8, 1, 9)));
    expect(when, DateTime(2026, 7, 31, 9));
  });
}
