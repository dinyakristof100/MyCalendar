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

  test('csak a bekapcsolt naptár látszik', () {
    expect(visibleCalendarIds(calendars, {privat.key}), [2]);
  });

  test('az azonos nevű, másik fiókos naptárt nem viszi magával', () {
    expect(visibleCalendarIds(calendars, {munka.key}), [1]);
  });

  test('ismeretlen (másik eszközről mentett) kulcs nem hoz be semmit', () {
    final visible = {_calendar(99, 'Nincs ilyen', account: 'x@y.hu').key};
    expect(visibleCalendarIds(calendars, visible), isEmpty);
  });

  test('semmi sincs bekapcsolva: üres lista, nem "nincs szűrő"', () {
    expect(visibleCalendarIds(calendars, const {}), isEmpty);
  });

  group('alapértelmezés', () {
    // A Google-fiók saját naptárának neve maga az e-mail cím.
    final sajat = _calendar(10, 'en@pelda.hu');
    final unnepek = _calendar(11, 'Ünnepnapok Magyarországon');
    final maseAccount = _calendar(12, 'masik@pelda.hu', account: 'masik@pelda.hu');

    test('csak a bejelentkezett fiók saját naptára', () {
      final all = [sajat, unnepek, maseAccount, privat];
      expect(defaultVisible(all, 'en@pelda.hu'), {sajat.key});
    });

    test('saját naptár híján a fiók összes naptára', () {
      expect(defaultVisible([unnepek, privat, maseAccount], 'en@pelda.hu'), {
        unnepek.key,
        privat.key,
      });
    });

    test('ismeretlen (vagy még be nem töltött) fiók: semmi', () {
      expect(defaultVisible(calendars, null), isEmpty);
      expect(defaultVisible(calendars, 'senki@pelda.hu'), isEmpty);
    });
  });
}
