import 'package:flutter_test/flutter_test.dart';
import 'package:my_calendar/features/workouts/workout_plans.dart';
import 'package:my_calendar/features/workouts/workout_progress.dart';

WorkoutPlan _plan(List<List<String>> weeks) =>
    WorkoutPlan(id: 'a', name: 'Terv', weeks: weeks);

void main() {
  // Hétfők, hogy a hétváltás egyértelmű legyen.
  final w1 = DateTime(2026, 7, 20); // hétfő
  final w2 = DateTime(2026, 7, 27); // következő hétfő
  final w3 = DateTime(2026, 8, 3); // két héttel később

  test('a nyitva maradt nap átjön a következő hétre, tartalmastul', () {
    final plan = _plan([
      ['mell', 'hát', 'láb'],
    ]);
    // 3 napból 2 leedzve (0,1), a 3. (láb) érintetlen marad.
    final stored = WeekProgress(planId: 'a', weekStart: w1, done: const {0, 1});

    final week = settleWeek(stored, plan, true, w2);
    expect(week.carried.length, 1);
    expect(week.carried.single.content, 'láb');
    // A hét célja: 3 alap + 1 áthozott = 4. A user példája.
    expect(week.targetCount(plan), 4);
    expect(week.trainedCount(plan), 0);
  });

  test('a szándékosan kihagyott (skip) nap NEM jön át', () {
    final plan = _plan([
      ['mell', 'hát', 'láb'],
    ]);
    // Láb kihagyva, a másik kettő leedzve → a hét lezárva, semmi sem húzódik át.
    final stored = WeekProgress(
      planId: 'a',
      weekStart: w1,
      done: const {0, 1},
      skipped: const {2},
    );
    expect(stored.resolvedAll(plan), isTrue);
    expect(stored.skippedCount(plan), 1);

    expect(settleWeek(stored, plan, true, w2).carried, isEmpty);
  });

  test('kikapcsolt átcsúsztatásnál nincs áthozott nap', () {
    final plan = _plan([
      ['mell', 'hát', 'láb'],
    ]);
    final stored = WeekProgress(planId: 'a', weekStart: w1, done: const {0});
    expect(settleWeek(stored, plan, false, w2).carried, isEmpty);
  });

  test('csak a közvetlen előző hétről hozunk át', () {
    final plan = _plan([
      ['mell'],
    ]);
    final stored = WeekProgress(planId: 'a', weekStart: w1);
    // Két héttel később a w1 már nem a közvetlen előző hét.
    expect(settleWeek(stored, plan, true, w3).carried, isEmpty);
  });

  test('a nyitva maradt áthozott nap tovább gyűrűzik, a lezárt nem', () {
    final plan = _plan([
      ['mell'],
    ]);
    // A w1 hét: az alap napot leedzték, de van egy korábbról áthozott, még
    // nyitott nap ('régi láb') és egy már kihagyott ('régi váll').
    final stored = WeekProgress(
      planId: 'a',
      weekStart: w1,
      done: const {0},
      carried: const [
        CarriedDay(content: 'régi láb'),
        CarriedDay(content: 'régi váll', outcome: WorkoutOutcome.skipped),
      ],
    );

    final week = settleWeek(stored, plan, true, w2);
    // Csak a nyitva maradt áthozott gyűrűzik tovább; a leedzett alap és a
    // kihagyott áthozott nem.
    expect([for (final c in week.carried) c.content], ['régi láb']);
  });

  test('a tervet rövidebbre szerkesztve a megszűnt napok pipái eltűnnek', () {
    // A hét közben 3 napról 2-re szerkesztették a tervet: a 3. nap (index 2)
    // pipája már nem tartozik sehova.
    final stored = WeekProgress(
      planId: 'a',
      weekStart: w1,
      done: const {0, 2},
      skipped: const {1},
    );
    final shorter = _plan([
      ['mell', 'hát'],
    ]);

    final week = settleWeek(stored, shorter, true, w1);
    expect(week.done, {0});
    expect(week.skipped, {1});
    // A hét így 2 napos, és nem látszik túlteljesítettnek.
    expect(week.targetCount(shorter), 2);
    expect(week.trainedCount(shorter), 1);
    expect(week.fullyTrained(shorter), isFalse);
  });

  test('A/B tervnél az előző hét saját variánsa jön át', () {
    final plan = _plan([
      ['A-mell', 'A-hát'],
      ['B-láb', 'B-váll'],
    ]);
    // w1 melyik variáns? A carry ennek a hétnek a napjait hozza.
    final variant = plan.daysOfWeekAt(w1);
    final stored = WeekProgress(planId: 'a', weekStart: w1); // semmi leedzve

    final week = settleWeek(stored, plan, true, w2);
    expect([for (final c in week.carried) c.content], variant);
  });
}
