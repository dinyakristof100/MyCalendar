import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_scaffold.dart';
import '../../core/ui.dart';
import 'workout_plans.dart';
import 'workout_progress.dart';

/// A kipipált edzés jelzése. Fix zöld, nem a téma akcentszíne: a "kész" itt
/// nem díszítés, hanem állapot — ugyanazt kell jelentenie világos és sötét
/// témában is.
const _done = Color(0xFF2E7D32);

class WorkoutsScreen extends ConsumerWidget {
  const WorkoutsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(workoutPlansProvider);
    final plan = state.active;

    return AppScaffold(
      title: 'Edzésnapló',
      floatingActionButton: plan == null
          ? null
          : FloatingActionButton(
              tooltip: 'Új edzésterv',
              onPressed: () => context.push('/workouts/new'),
              child: const Icon(Icons.add),
            ),
      body: plan == null
          ? const _NoPlanYet()
          : _PlanView(plans: state.plans, plan: plan),
    );
  }
}

/// Az első indulás: terv nélkül az edzésnaplónak nincs miről beszélnie.
class _NoPlanYet extends StatelessWidget {
  const _NoPlanYet();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(40, 24, 40, 60),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.fitness_center,
                size: 40,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Még nincs edzésterved',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Add meg, hány napot edzel egy héten, és mi kerül az egyes '
              'napokra.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: () => context.push('/workouts/new'),
              icon: const Icon(Icons.add),
              label: const Text('Edzésterv létrehozása'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanView extends ConsumerWidget {
  const _PlanView({required this.plans, required this.plan});

  final List<WorkoutPlan> plans;
  final WorkoutPlan plan;

  /// Megerősítés után pipa. Hosszú nyomásra indul, nem koppintásra: görgetés
  /// közben könnyű véletlenül eltalálni egy kártyát. A kérdés a nap tartalmát
  /// is kimondja, mert egy téves pipa a heti tervből venne el egy edzést.
  Future<void> _confirm(
    BuildContext context,
    WidgetRef ref,
    int day,
    String content,
  ) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Biztosan ezt az edzést teljesítetted ma?'),
        content: Text('${day + 1}. nap — $content'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Mégsem'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Igen, megvolt'),
          ),
        ],
      ),
    );
    if (yes ?? false) {
      await ref.read(workoutProgressProvider.notifier).markDone(plan, day);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final thisWeek = weekIndexOf(now, weeks: plan.weeks.length);
    final done = ref.watch(workoutProgressProvider).doneFor(plan, now);
    final days = plan.daysOfWeekAt(now).length;
    var slot = 0;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 96),
      children: [
        // Tervválasztó csak akkor, ha van miből választani.
        if (plans.length > 1) ...[
          Wrap(
            spacing: 8,
            children: [
              for (final option in plans)
                ChoiceChip(
                  label: Text(option.name),
                  selected: option.id == plan.id,
                  onSelected: (_) => ref
                      .read(workoutPlansProvider.notifier)
                      .setActive(option.id),
                ),
            ],
          ),
          const SizedBox(height: 16),
        ],
        Appear(
          index: slot++,
          child: Text(
            plan.name,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${plan.hasBWeek ? 'A és B hét' : 'Sima heti terv'} · ezen a héten '
          '${done.length}/$days megvan',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: done.length >= days
                ? _done
                : theme.colorScheme.onSurfaceVariant,
          ),
        ),
        for (var week = 0; week < plan.weeks.length; week++) ...[
          if (plan.hasBWeek)
            _WeekHeader(
              label: '${week == 0 ? 'A' : 'B'} HÉT',
              isThisWeek: week == thisWeek,
            )
          else
            const SizedBox(height: 14),
          for (var day = 0; day < plan.weeks[week].length; day++)
            Appear(
              index: slot++,
              child: _DayCard(
                day: day + 1,
                content: plan.weeks[week][day],
                done: week == thisWeek && done.contains(day),
                // Csak az aktuális hét pipálható, és csak ami még nincs kész.
                onLongPress: week == thisWeek && !done.contains(day)
                    ? () => _confirm(context, ref, day, plan.weeks[week][day])
                    : null,
              ),
            ),
        ],
      ],
    );
  }
}

class _WeekHeader extends StatelessWidget {
  const _WeekHeader({required this.label, required this.isThisWeek});

  final String label;
  final bool isThisWeek;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 22, 0, 6),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: isThisWeek
                ? theme.colorScheme.primary
                : theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            isThisWeek ? '$label · EZ A HÉT' : label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: isThisWeek
                  ? theme.colorScheme.onPrimary
                  : theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
        ),
      ),
    );
  }
}

class _DayCard extends StatelessWidget {
  const _DayCard({
    required this.day,
    required this.content,
    required this.done,
    required this.onLongPress,
  });

  final int day;
  final String content;
  final bool done;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Ink(
        decoration: done
            ? BoxDecoration(
                color: _done.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: _done.withValues(alpha: 0.55)),
              )
            : cardSurface(theme),
        child: InkWell(
          onLongPress: onLongPress,
          borderRadius: BorderRadius.circular(22),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 15, 18, 17),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$day. NAP',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: done ? _done : theme.colorScheme.primary,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        content,
                        style: theme.textTheme.titleMedium?.copyWith(
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
                if (done) ...[
                  const SizedBox(width: 12),
                  const Icon(Icons.check_circle, color: _done),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
