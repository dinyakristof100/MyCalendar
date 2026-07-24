import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/cloud_sync.dart';
import '../../core/prefs.dart';
import 'workout_plans.dart';

const _key = 'workoutProgress';

/// Az aktuális hét teljesített edzésnapjai.
///
/// Egyetlen hetet tartunk nyilván: ha új hét kezdődik vagy másik terv lesz az
/// aktív, a pipák maguktól elévülnek — nincs takarító feladat, és a régi
/// heteket úgysem mutatjuk sehol.
class WeekProgress {
  const WeekProgress({this.planId, this.weekStart, this.done = const {}});

  final String? planId;
  final DateTime? weekStart;
  final Set<int> done;

  /// A [plan] adott heti teljesített napjai. Más tervhez vagy más héthez
  /// tartozó pipa nem számít.
  Set<int> doneFor(WorkoutPlan plan, DateTime now) =>
      planId == plan.id && weekStart == weekStartOf(now) ? done : const {};

  /// Megvan-e a hét összes edzése.
  bool weekDoneFor(WorkoutPlan? plan, DateTime now) =>
      plan != null &&
      doneFor(plan, now).length >= plan.daysOfWeekAt(now).length;

  Map<String, Object?> toJson() => {
    'planId': planId,
    'weekStart': weekStart?.toIso8601String(),
    'done': done.toList(),
  };

  static WeekProgress fromJson(Map<String, Object?> json) => WeekProgress(
    planId: json['planId'] as String?,
    weekStart: DateTime.tryParse(json['weekStart'] as String? ?? ''),
    done: {for (final day in json['done']! as List) day as int},
  );
}

final workoutProgressProvider =
    NotifierProvider<WorkoutProgressController, WeekProgress>(
      WorkoutProgressController.new,
    );

class WorkoutProgressController extends Notifier<WeekProgress> {
  @override
  WeekProgress build() {
    final raw = prefs.getString(_key);
    return raw == null
        ? const WeekProgress()
        : WeekProgress.fromJson(jsonDecode(raw) as Map<String, Object?>);
  }

  /// A [day]. napot (0-tól) teljesítettnek jelöli a mai héten.
  Future<void> markDone(WorkoutPlan plan, int day) async {
    final now = DateTime.now();
    state = WeekProgress(
      planId: plan.id,
      weekStart: weekStartOf(now),
      done: {...state.doneFor(plan, now), day},
    );
    // Az értesítések újraütemezését a workoutNudgeSyncProvider intézi: ez az
    // állapot az ő függősége.
    await saveSetting(_key, jsonEncode(state.toJson()));
  }
}
