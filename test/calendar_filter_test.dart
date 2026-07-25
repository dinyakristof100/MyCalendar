import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_calendar/features/calendar/calendar_service.dart';

DeviceCalendar _calendar(int id, String name, {String account = 'en@pelda.hu'}) =>
    DeviceCalendar(
      id: id,
      name: name,
      account: account,
      color: const Color(0xFF000000),
    );

void main() {
  final munka = _calendar(1, 'Munka');
  final privat = _calendar(2, 'Privát');
  // Ugyanaz a NÉV, másik fiók — a kulcs a kettő párosa, tehát külön naptár.
  final masikMunka = _calendar(3, 'Munka', account: 'masik@pelda.hu');
  final calendars = [munka, privat, masikMunka];

  test('elrejtés nélkül minden naptár látszik', () {
    expect(visibleCalendarIds(calendars, const {}), [1, 2, 3]);
  });

  test('az elrejtett naptár kiesik, a többi marad', () {
    expect(visibleCalendarIds(calendars, {privat.key}), [1, 3]);
  });

  test('az azonos nevű, másik fiókos naptárt nem viszi magával', () {
    expect(visibleCalendarIds(calendars, {munka.key}), [2, 3]);
  });

  test('ismeretlen (másik eszközről mentett) kulcs nem rejt el semmit', () {
    final hidden = {_calendar(99, 'Nincs ilyen', account: 'x@y.hu').key};
    expect(visibleCalendarIds(calendars, hidden), [1, 2, 3]);
  });

  test('minden naptár elrejtve: üres lista, nem "nincs szűrő"', () {
    final hidden = {for (final c in calendars) c.key};
    expect(visibleCalendarIds(calendars, hidden), isEmpty);
  });
}
