import 'package:flutter_test/flutter_test.dart';
import 'package:my_calendar/features/calendar/calendar_service.dart';
import 'package:my_calendar/features/calendar/reminders.dart';

CalendarEvent _event(DateTime at, {bool allDay = false}) =>
    CalendarEvent(id: '1', title: 'Teszt', at: at, allDay: allDay);

void main() {
  test('időpontos esemény: 24 órával és 1 órával korábbi emlékeztető', () {
    final rs = remindersFor(_event(DateTime(2026, 7, 23, 14, 30)));
    expect(rs.map((r) => r.when), [
      DateTime(2026, 7, 22, 14, 30), // fali óra szerint egy nappal korábban
      DateTime(2026, 7, 23, 13, 30), // egy órával a kezdés előtt
    ]);
    expect(rs[1].body, contains('Egy óra múlva'));
    expect(rs[0].slot, isNot(rs[1].slot)); // külön azonosító, nincs felülírás
  });

  test('egész napos esemény: csak az előző esti emlékeztető, 0:00 helyett', () {
    final rs = remindersFor(_event(DateTime(2026, 7, 23), allDay: true));
    expect(rs.map((r) => r.when), [DateTime(2026, 7, 22, 18)]);
  });

  test('hónap elején az előző hónap utolsó napjára esik', () {
    final rs = remindersFor(_event(DateTime(2026, 8, 1, 9)));
    expect(rs.first.when, DateTime(2026, 7, 31, 9));
  });

  test('az ujjlenyomat csak akkor változik, ha az ütemezés is', () {
    final events = [_event(DateTime(2026, 7, 23, 14, 30))];
    // Ugyanaz a lista újra lekérve: nincs mit újraütemezni.
    expect(
      remindersSignature(events),
      remindersSignature([_event(DateTime(2026, 7, 23, 14, 30))]),
    );
    // Áthelyezett esemény és új esemény viszont változást jelent.
    expect(
      remindersSignature([_event(DateTime(2026, 7, 23, 15, 30))]),
      isNot(remindersSignature(events)),
    );
    expect(
      remindersSignature([...events, _event(DateTime(2026, 7, 24, 9))]),
      isNot(remindersSignature(events)),
    );
  });
}
