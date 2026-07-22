import 'package:flutter_test/flutter_test.dart';
import 'package:my_calendar/core/prefs.dart';
import 'package:my_calendar/features/workouts/workout_plans.dart';
import 'package:my_calendar/features/workouts/workout_progress.dart';
import 'package:shared_preferences/shared_preferences.dart';

WorkoutPlan _plan(String id, List<List<String>> weeks) =>
    WorkoutPlan(id: id, name: 'Terv $id', weeks: weeks);

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await initPrefs();
  });

  test('a terv oda-vissza alakítható JSON-be', () {
    final plan = _plan('1', [
      ['mell, tricepsz', 'hát, bicepsz'],
      ['láb', 'váll'],
    ]);
    final back = WorkoutPlan.fromJson(plan.toJson());

    expect(back.id, plan.id);
    expect(back.name, plan.name);
    expect(back.weeks, plan.weeks);
    expect(back.hasBWeek, isTrue);
    expect(back.daysPerWeek, 2);
  });

  test('egy hét = sima heti terv', () {
    final plan = _plan('2', [
      ['mell', 'hát', 'láb'],
    ]);
    expect(plan.hasBWeek, isFalse);
    expect(plan.daysPerWeek, 3);
  });

  test('aktív terv: a kiválasztott, egyébként az első', () {
    final plans = [
      _plan('a', [
        ['mell'],
      ]),
      _plan('b', [
        ['hát'],
      ]),
    ];

    expect(WorkoutPlans(plans: plans, activeId: 'b').active?.id, 'b');
    // Eltűnt vagy még ki sem választott terv esetén nem marad üres a képernyő.
    expect(WorkoutPlans(plans: plans, activeId: 'nincs').active?.id, 'a');
    expect(const WorkoutPlans(plans: []).active, isNull);
  });

  test('a hét hétfőtől vasárnapig tart', () {
    // 2026. július 22. szerda.
    expect(weekStartOf(DateTime(2026, 7, 22, 23, 59)), DateTime(2026, 7, 20));
    expect(weekStartOf(DateTime(2026, 7, 20)), DateTime(2026, 7, 20));
    // Vasárnap még ugyanaz a hét, hétfőn már a következő.
    expect(weekStartOf(DateTime(2026, 7, 26)), DateTime(2026, 7, 20));
    expect(weekStartOf(DateTime(2026, 7, 27)), DateTime(2026, 7, 27));
  });

  test('A és B hét felváltva jön, sima tervnél mindig az első', () {
    final monday = DateTime(2026, 7, 20);
    final nextMonday = DateTime(2026, 7, 27);

    expect(weekIndexOf(monday, weeks: 1), 0);
    expect(weekIndexOf(nextMonday, weeks: 1), 0);
    // Egy héten belül nem vált, a következő héten igen.
    expect(
      weekIndexOf(monday, weeks: 2),
      weekIndexOf(monday.add(const Duration(days: 6)), weeks: 2),
    );
    expect(
      weekIndexOf(nextMonday, weeks: 2),
      isNot(weekIndexOf(monday, weeks: 2)),
    );
  });

  test('a pipák elévülnek új héten és tervváltáskor', () {
    final plan = _plan('a', [
      ['mell', 'hát'],
    ]);
    final now = DateTime(2026, 7, 22);
    final progress = WeekProgress(
      planId: 'a',
      weekStart: weekStartOf(now),
      done: const {0},
    );

    expect(progress.doneFor(plan, now), {0});
    expect(progress.weekDoneFor(plan, now), isFalse);
    // Következő hét: tiszta lap.
    expect(progress.doneFor(plan, now.add(const Duration(days: 7))), isEmpty);
    // Másik terv pipái sem számítanak.
    expect(
      progress.doneFor(
        _plan('b', [
          ['láb'],
        ]),
        now,
      ),
      isEmpty,
    );
  });

  test('a hét akkor kész, ha minden napja megvan', () {
    final plan = _plan('a', [
      ['mell', 'hát'],
    ]);
    final now = DateTime(2026, 7, 22);
    final progress = WeekProgress(
      planId: 'a',
      weekStart: weekStartOf(now),
      done: const {0, 1},
    );

    expect(progress.weekDoneFor(plan, now), isTrue);
    expect(const WeekProgress().weekDoneFor(plan, now), isFalse);
    expect(progress.weekDoneFor(null, now), isFalse);
  });
}
