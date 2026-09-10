import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_calendar/core/prefs.dart';
import 'package:my_calendar/features/schedule/schedule.dart';
import 'package:shared_preferences/shared_preferences.dart';

ScheduleEntry _entry(
  String id, {
  int weekday = DateTime.monday,
  int start = 8 * 60,
  int end = 9 * 60 + 30,
  int? week,
}) => ScheduleEntry(
  id: id,
  weekday: weekday,
  start: start,
  end: end,
  title: 'Tétel $id',
  week: week,
);

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await initPrefs();
  });

  setUp(() => prefs.remove(scheduleKey));

  test('a beosztás oda-vissza alakítható JSON-be', () {
    final state = ScheduleState(
      abWeeks: true,
      groups: const [
        ScheduleGroup(id: 'g1', name: 'Előadás', color: Color(0xFF7392C9)),
      ],
      entries: [
        _entry('1', week: 1),
        ScheduleEntry(
          id: '2',
          weekday: DateTime.wednesday,
          start: 10 * 60,
          end: 11 * 60,
          title: 'Közgazdaságtan',
          note: 'B/2 terem',
          groupId: 'g1',
        ),
      ],
    );

    final back = ScheduleState.fromJson(state.toJson());
    expect(back.abWeeks, isTrue);
    expect(back.groups.single.name, 'Előadás');
    expect(back.entries.first.week, 1);
    expect(back.entries.last.note, 'B/2 terem');
    expect(back.entries.last.groupId, 'g1');
    expect(back.groupById('g1')?.color, const Color(0xFF7392C9));
  });

  test('a hét nélküli tétel mindkét héten ott van, a kötött csak a sajátján', () {
    final both = _entry('mind');
    final aWeek = _entry('a', week: 0);
    final bWeek = _entry('b', week: 1);

    expect(both.showsOn(DateTime.monday, 0), isTrue);
    expect(both.showsOn(DateTime.monday, 1), isTrue);
    expect(both.showsOn(DateTime.tuesday, 0), isFalse);
    expect(aWeek.showsOn(DateTime.monday, 0), isTrue);
    expect(aWeek.showsOn(DateTime.monday, 1), isFalse);
    expect(bWeek.showsOn(DateTime.monday, 1), isTrue);
  });

  test('a nap tételei kezdés szerint jönnek', () {
    final state = ScheduleState(
      abWeeks: false,
      groups: const [],
      entries: [
        _entry('kesoi', start: 14 * 60, end: 15 * 60),
        _entry('korai', start: 8 * 60, end: 9 * 60),
        _entry('mas nap', weekday: DateTime.friday),
      ],
    );

    final monday = state.dayEntries(DateTime.monday, 0);
    expect([for (final e in monday) e.id], ['korai', 'kesoi']);
  });

  test('sima beosztásnál minden hét a 0. — A/B-nél váltakoznak', () {
    const simple = ScheduleState(abWeeks: false, groups: [], entries: []);
    const ab = ScheduleState(abWeeks: true, groups: [], entries: []);
    final monday = DateTime(2026, 9, 7);
    final nextMonday = DateTime(2026, 9, 14);

    expect(simple.weekOf(monday), 0);
    expect(simple.weekOf(nextMonday), 0);
    // Egymás utáni hetek A/B-nél biztosan különböznek, és a hét minden napja
    // ugyanabba a hétbe esik.
    expect(ab.weekOf(monday), isNot(ab.weekOf(nextMonday)));
    expect(ab.weekOf(monday), ab.weekOf(DateTime(2026, 9, 13)));
  });

  group('sávkiosztás', () {
    test('átfedés nélkül minden tétel a teljes oszlopot kapja', () {
      final lanes = laneLayout([
        _entry('1', start: 8 * 60, end: 9 * 60),
        _entry('2', start: 9 * 60, end: 10 * 60),
      ]);
      expect(lanes, [(lane: 0, lanes: 1), (lane: 0, lanes: 1)]);
    });

    test('az átfedők egymás mellé kerülnek, és a lánc végig osztozik', () {
      // 8:00–9:00 és 8:30–9:30 átfed; 9:15–10:00 csak a másodikkal — a három
      // egy láncot alkot, de két sáv elég nekik.
      final lanes = laneLayout([
        _entry('a', start: 8 * 60, end: 9 * 60),
        _entry('b', start: 8 * 60 + 30, end: 9 * 60 + 30),
        _entry('c', start: 9 * 60 + 15, end: 10 * 60),
      ]);
      expect(lanes, [
        (lane: 0, lanes: 2),
        (lane: 1, lanes: 2),
        (lane: 0, lanes: 2),
      ]);
    });

    test('a lánc után induló tétel újra teljes szélességű', () {
      final lanes = laneLayout([
        _entry('a', start: 8 * 60, end: 9 * 60),
        _entry('b', start: 8 * 60 + 30, end: 9 * 60 + 30),
        _entry('kesobb', start: 11 * 60, end: 12 * 60),
      ]);
      expect(lanes.last, (lane: 0, lanes: 1));
    });
  });

  group('A/B váltás', () {
    ProviderContainer container() {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      return c;
    }

    test('A/B-re váltva minden tétel megmarad mindkét héten', () async {
      final c = container();
      await c.read(scheduleProvider.notifier).saveEntry(_entry('1'));
      await c.read(scheduleProvider.notifier).setAbWeeks(true);

      final state = c.read(scheduleProvider);
      expect(state.abWeeks, isTrue);
      expect(state.entries.single.week, isNull);
      expect(state.dayEntries(DateTime.monday, 1).length, 1);
    });

    test('sima hetire visszaváltva a csak B heti tételek tűnnek el', () async {
      final c = container();
      final controller = c.read(scheduleProvider.notifier);
      await controller.setAbWeeks(true);
      await controller.saveEntry(_entry('a', week: 0));
      await controller.saveEntry(_entry('b', weekday: DateTime.tuesday, week: 1));
      expect(controller.bOnlyCount, 1);

      await controller.setAbWeeks(false);
      final state = c.read(scheduleProvider);
      expect([for (final e in state.entries) e.id], ['a']);
      // A megmaradt tétel innentől minden héten ott van.
      expect(state.entries.single.week, isNull);
    });

    test('a mentett beosztást új munkamenet visszaolvassa', () async {
      await container().read(scheduleProvider.notifier).saveEntry(
        _entry('1', start: 10 * 60, end: 11 * 60),
      );

      final reopened = container();
      expect(reopened.read(scheduleProvider).entries.single.start, 10 * 60);
    });

    test('csoport törlésekor a tételek megmaradnak, csak a szín tűnik el',
        () async {
      final c = container();
      final controller = c.read(scheduleProvider.notifier);
      final group = await controller.saveGroup(
        const ScheduleGroup(id: 'g1', name: 'Előadás', color: Color(0xFF6FA97F)),
      );
      await controller.saveEntry(
        ScheduleEntry(
          id: '1',
          weekday: DateTime.monday,
          start: 8 * 60,
          end: 9 * 60,
          title: 'Közgazdaságtan',
          groupId: group.id,
        ),
      );

      await controller.removeGroup('g1');
      final state = c.read(scheduleProvider);
      expect(state.groups, isEmpty);
      expect(state.entries.single.title, 'Közgazdaságtan');
      expect(state.entries.single.groupId, isNull);
    });
  });

  test('időformázás: vezető nulla nélkül, kerek órák szó nélkül', () {
    expect(hhmm(8 * 60), '8:00');
    expect(hhmm(9 * 60 + 5), '9:05');
    expect(hhmm(0), '0:00');
    expect(spanLabel(45), '45 perc');
    expect(spanLabel(120), '2 óra');
    expect(spanLabel(90), '1 óra 30 perc');
  });
}
