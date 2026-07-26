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

  group('sávkiosztás a hónaprácshoz', () {
    DateTime day(int d) => DateTime(2026, 7, d);

    /// A naptárnézet `_byDay` térképe rövidebben: nap sorszáma -> események.
    Map<DateTime, List<CalendarEvent>> byDay(Map<int, List<CalendarEvent>> raw) =>
        {for (final entry in raw.entries) day(entry.key): entry.value};

    test('a több napos esemény minden napján ugyanabba a sávba kerül', () {
      // Ugyanaz az objektum kerül fel mindhárom napra — pont, ahogy a
      // naptárnézet is szétteríti a több napos eseményt.
      final hosszu = _event(day(1), title: 'hosszú');
      final lanes = assignEventLanes(
        byDay({
          1: [_event(day(1), title: 'a'), hosszu],
          2: [hosszu],
          3: [hosszu, _event(day(3), title: 'b')],
        }),
      );

      // A leghosszabb választ előbb: övé a felső sáv, végig.
      expect(lanes[day(1)]![0], same(hosszu));
      expect(lanes[day(2)]![0], same(hosszu));
      expect(lanes[day(3)]![0], same(hosszu));
      // Az egynaposak alá kerülnek, a köztes napon nem foglalnak semmit.
      expect(lanes[day(1)]![1]?.title, 'a');
      expect(lanes[day(3)]![1]?.title, 'b');
      expect(lanes[day(2)]![1], isNull);
    });

    test('naponta legfeljebb három sáv, a többi kimarad', () {
      final events = [
        for (var hour = 8; hour < 13; hour++)
          _event(DateTime(2026, 7, 1, hour), title: '$hour'),
      ];
      final lanes = assignEventLanes(byDay({1: events}));

      expect(lanes[day(1)], hasLength(maxDayLanes));
      // A nap első három eseménye látszik, a maradék kettő nem.
      expect(lanes[day(1)], events.take(maxDayLanes));
    });

    test('esemény nélküli nap nem kap sávot', () {
      final lanes = assignEventLanes(
        byDay({
          1: [_event(day(1))],
        }),
      );
      expect(lanes[day(2)], isNull);
    });
  });

  group('timeLeftLabel', () {
    String? left(DateTime at, {bool allDay = false}) =>
        timeLeftLabel(_event(at, allDay: allDay), _today);

    test('egy napon túl napokban', () {
      expect(left(DateTime(2026, 7, 25, 10)), '3 nap múlva');
      // Kerek napokra csonkít: 2 nap 23 óra még „2 nap múlva".
      expect(left(DateTime(2026, 7, 25, 9)), '2 nap múlva');
    });

    test('egy napon belül órákban', () {
      expect(left(DateTime(2026, 7, 22, 18)), '8 óra múlva');
      expect(left(DateTime(2026, 7, 23, 9, 59)), '23 óra múlva');
    });

    test('egy órán belül percekben, a kezdésnél szöveggel', () {
      expect(left(DateTime(2026, 7, 22, 10, 30)), '30 perc múlva');
      expect(left(_today), 'Most kezdődik');
    });

    test('a már elkezdődött eseményhez nincs mit visszaszámolni', () {
      expect(left(DateTime(2026, 7, 22, 9)), isNull);
    });

    test('az egész napos a naptári napok különbségét mutatja', () {
      // Nem a holnap éjfélig hátralévő 14 óra, hanem „1 nap múlva".
      expect(left(DateTime(2026, 7, 23), allDay: true), '1 nap múlva');
      expect(left(DateTime(2026, 7, 22), allDay: true), isNull);
    });
  });

  group('nowMarkerIndex', () {
    test('üres nap: a vonal a végén (nulladik) helyen áll', () {
      expect(nowMarkerIndex(const [], _today), 0);
    });

    test('minden esemény elmúlt: a nap végére kerül', () {
      final events = [
        _event(DateTime(2026, 7, 22, 8)),
        _event(DateTime(2026, 7, 22, 9)),
      ];
      expect(nowMarkerIndex(events, _today), 2);
    });

    test('minden esemény hátravan: a lista elejére kerül', () {
      final events = [
        _event(DateTime(2026, 7, 22, 14)),
        _event(DateTime(2026, 7, 22, 18)),
      ];
      expect(nowMarkerIndex(events, _today), 0);
    });

    test('az egész naposakat átlépi', () {
      final events = [
        _event(DateTime(2026, 7, 22), allDay: true),
        _event(DateTime(2026, 7, 22, 8)),
        _event(DateTime(2026, 7, 22, 14)),
      ];
      expect(nowMarkerIndex(events, _today), 2);
    });

    test('csak egész napos események: a végén', () {
      final events = [_event(DateTime(2026, 7, 22), allDay: true)];
      expect(nowMarkerIndex(events, _today), 1);
    });

    test('a pont most kezdődő esemény már mögötte van', () {
      final events = [_event(_today), _event(DateTime(2026, 7, 22, 11))];
      expect(nowMarkerIndex(events, _today), 1);
    });
  });
}
