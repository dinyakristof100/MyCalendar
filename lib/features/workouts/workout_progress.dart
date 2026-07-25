import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/cloud_sync.dart';
import '../../core/prefs.dart';
import 'streak.dart';
import 'workout_plans.dart';

const _key = 'workoutProgress';
const _carryKey = 'carryOverWorkouts';

/// Egy edzésnap kimenetele a heten belul.
///
/// A [skipped] a felhasznalo szandekos dontese: ezt a napot nem edzi le, de nem
/// is hozza at a jovo hetre (pl. a labnapot direkt kihagyja). A se nem [done], se
/// nem [skipped] (nyitott) nap az, amit athuzunk a kovetkezo hetre.
enum WorkoutOutcome { done, skipped }

/// Egy elozo hetrol athozott edzesnap. A tartalmat mentjuk, nem a slot indexet:
/// igy A/B tervnel is a helyes edzes jon at, es a tobbszoros athuzodas sem fugg
/// a korabbi hetek terveitol.
class CarriedDay {
  const CarriedDay({required this.content, this.outcome});

  final String content;
  final WorkoutOutcome? outcome; // null = meg nyitott

  bool get done => outcome == WorkoutOutcome.done;
  bool get resolved => outcome != null;

  CarriedDay withOutcome(WorkoutOutcome? o) =>
      CarriedDay(content: content, outcome: o);

  Map<String, Object?> toJson() => {'content': content, 'outcome': outcome?.name};

  static CarriedDay fromJson(Map<String, Object?> json) => CarriedDay(
    content: json['content']! as String,
    outcome: switch (json['outcome']) {
      'done' => WorkoutOutcome.done,
      'skipped' => WorkoutOutcome.skipped,
      _ => null,
    },
  );
}

/// Az aktualis het edzesnapjai. Egyetlen hetet tartunk nyilvan: ha uj het jon
/// vagy masik terv lesz aktiv, a [settleWeek] tiszta lapot szamol — a regi
/// heteket ugysem mutatjuk sehol.
///
/// A [done]/[skipped] a terv sajat (base) napjainak slot-indexei; a [carried] az
/// elozo hetrol athozott plusz napok, sajat kimenetellel.
class WeekProgress {
  const WeekProgress({
    this.planId,
    this.weekStart,
    this.done = const {},
    this.skipped = const {},
    this.carried = const [],
  });

  final String? planId;
  final DateTime? weekStart;
  final Set<int> done;
  final Set<int> skipped;
  final List<CarriedDay> carried;

  /// A terv sajat napjainak szama ezen a heten (A/B tervnel a soron kovetkezoe).
  int _baseDays(WorkoutPlan plan) => plan.daysOfWeekAt(weekStart!).length;

  /// A het celja: a base napok + az athozottak.
  int targetCount(WorkoutPlan plan) => _baseDays(plan) + carried.length;

  /// Ahany napot tenylegesen leedzett (a skippelt nem szamit ide).
  int trainedCount(WorkoutPlan plan) =>
      done.length + carried.where((c) => c.done).length;

  /// Ahany napot szandekosan kihagyott.
  int skippedCount(WorkoutPlan plan) =>
      skipped.length + carried.where((c) => c.resolved && !c.done).length;

  /// Minden edzes leedzve — teljes, hibatlan het.
  bool fullyTrained(WorkoutPlan plan) => trainedCount(plan) >= targetCount(plan);

  /// A het le van zarva: minden nap vagy leedzve, vagy szandekosan kihagyva.
  /// Ilyenkor nincs mit athuzni es nincs mire tovabb kerdezni.
  bool resolvedAll(WorkoutPlan plan) =>
      done.length + skipped.length >= _baseDays(plan) &&
      carried.every((c) => c.resolved);

  Map<String, Object?> toJson() => {
    'planId': planId,
    'weekStart': weekStart?.toIso8601String(),
    'done': done.toList(),
    'skipped': skipped.toList(),
    'carried': [for (final c in carried) c.toJson()],
  };

  static WeekProgress fromJson(Map<String, Object?> json) => WeekProgress(
    planId: json['planId'] as String?,
    weekStart: DateTime.tryParse(json['weekStart'] as String? ?? ''),
    done: {for (final day in (json['done'] as List? ?? const [])) day as int},
    skipped: {
      for (final day in (json['skipped'] as List? ?? const [])) day as int,
    },
    carried: [
      for (final c in (json['carried'] as List? ?? const []))
        CarriedDay.fromJson((c as Map).cast<String, Object?>()),
    ],
  );
}

/// A tarolt haladasbol eloallitja az AKTUALIS het kepet.
///
/// Ha het valtott (vagy elso inditas / tervvaltas), tiszta lapot ad. Ha
/// [carryOn] be van kapcsolva ES a tarolt allapot pont a kozvetlen elozo hete
/// ugyanennek a tervnek, akkor annak a hetnek a se nem leedzett, se nem
/// skippelt napjait athozza. Csak szamol, nem ir: a mentes a pipalaskor tortenik.
///
/// ponytail: csak a kozvetlen elozo hetrol hozunk at. Ha valaki egy teljes hetig
/// ki sem nyitja az appot, annak a hetnek a napjai nem lancolodnak tovabb — a
/// tovabbgyuruzest a skip helyett a nem-hasznalat zarja le.
WeekProgress settleWeek(
  WeekProgress stored,
  WorkoutPlan plan,
  bool carryOn,
  DateTime now,
) {
  final cur = weekStartOf(now);
  if (stored.planId == plan.id && stored.weekStart == cur) return stored;

  final prev = cur.subtract(const Duration(days: 7));
  final carried = <CarriedDay>[];
  if (carryOn && stored.planId == plan.id && stored.weekStart == prev) {
    final lastDays = plan.daysOfWeekAt(prev);
    for (var i = 0; i < lastDays.length; i++) {
      if (!stored.done.contains(i) && !stored.skipped.contains(i)) {
        carried.add(CarriedDay(content: lastDays[i]));
      }
    }
    for (final c in stored.carried) {
      if (!c.resolved) carried.add(CarriedDay(content: c.content));
    }
  }
  return WeekProgress(planId: plan.id, weekStart: cur, carried: carried);
}

/// Be van-e kapcsolva a le nem edzett napok atcsusztatasa a kovetkezo hetre.
final carryOverProvider = NotifierProvider<CarryOverController, bool>(
  CarryOverController.new,
);

class CarryOverController extends Notifier<bool> {
  @override
  bool build() => prefs.getString(_carryKey) == 'true';

  Future<void> set(bool on) async {
    state = on;
    await saveSetting(_carryKey, on ? 'true' : 'false');
  }
}

final workoutProgressProvider =
    NotifierProvider<WorkoutProgressController, WeekProgress>(
      WorkoutProgressController.new,
    );

/// Az aktualis het, mar rendezve (hetvaltas + athuzas beszamitva). A kepernyo es
/// az esti kerdesek is ezt hasznaljak — egy helyen dol el, mi szamit a mai hetre.
final currentWeekProvider = Provider<WeekProgress>((ref) {
  final plan = ref.watch(workoutPlansProvider).active;
  final stored = ref.watch(workoutProgressProvider);
  if (plan == null) return stored;
  return settleWeek(stored, plan, ref.watch(carryOverProvider), DateTime.now());
});

class WorkoutProgressController extends Notifier<WeekProgress> {
  @override
  WeekProgress build() {
    final raw = prefs.getString(_key);
    return raw == null
        ? const WeekProgress()
        : WeekProgress.fromJson(jsonDecode(raw) as Map<String, Object?>);
  }

  WeekProgress _current(WorkoutPlan plan) =>
      settleWeek(state, plan, ref.read(carryOverProvider), DateTime.now());

  Future<void> _persist(WeekProgress week) async {
    state = week;
    // Az ertesitesek ujrautemezeset a workoutNudgeSyncProvider intezi: ez az
    // allapot az o fuggosege.
    await saveSetting(_key, jsonEncode(week.toJson()));
  }

  /// A terv [slot]. sajat napjat [outcome]-ra allitja a mai heten.
  Future<void> markBase(
    WorkoutPlan plan,
    int slot,
    WorkoutOutcome outcome,
  ) async {
    final cur = _current(plan);
    final done = {...cur.done}..remove(slot);
    final skipped = {...cur.skipped}..remove(slot);
    (outcome == WorkoutOutcome.done ? done : skipped).add(slot);
    final week = WeekProgress(
      planId: cur.planId,
      weekStart: cur.weekStart,
      done: done,
      skipped: skipped,
      carried: cur.carried,
    );
    await _persist(week);
    await _recordIfComplete(plan, week);
  }

  /// Az [index]. athozott napot [outcome]-ra allitja a mai heten.
  Future<void> markCarried(
    WorkoutPlan plan,
    int index,
    WorkoutOutcome outcome,
  ) async {
    final cur = _current(plan);
    final week = WeekProgress(
      planId: cur.planId,
      weekStart: cur.weekStart,
      done: cur.done,
      skipped: cur.skipped,
      carried: [
        for (var i = 0; i < cur.carried.length; i++)
          i == index ? cur.carried[i].withOutcome(outcome) : cur.carried[i],
      ],
    );
    await _persist(week);
    await _recordIfComplete(plan, week);
  }

  /// Ha ezzel a pipaval teljes lett a het (minden betervezett es athozott edzes
  /// leedzve), beszamitja a heti sorozatba. Skip nem szamit — csak a 100%.
  Future<void> _recordIfComplete(WorkoutPlan plan, WeekProgress week) async {
    if (week.fullyTrained(plan)) {
      await ref.read(streakProvider.notifier).recordCompletion(week.weekStart!);
    }
  }
}
