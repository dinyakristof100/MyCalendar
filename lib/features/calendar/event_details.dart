import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'calendar_service.dart';
import 'event_categories.dart';
import 'event_groups.dart';

/// Az esemény részletei alulról felcsúszó lapon.
///
/// ponytail: bottom sheet, nem külön útvonal. Nincs mit mélylinkelni, a
/// rendszer vissza gombja pedig magától bezárja. Ha egyszer megosztható
/// esemény-link kell, jöhet a `/event/:id` route.
Future<void> showEventDetails(BuildContext context, CalendarEvent event) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => _EventDetails(event: event),
  );
}

class _EventDetails extends ConsumerWidget {
  const _EventDetails({required this.event});

  final CalendarEvent event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final time = formatTime(event);
    final end = event.end;
    final category = ref.watch(categoriesProvider).of(event.id);

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                event.title,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 14),
              _CategoryChip(category: category, event: event),
              const SizedBox(height: 20),
              _Detail(
                icon: Icons.event_outlined,
                text: dayLabel(event.at, today: DateTime.now()),
              ),
              _Detail(
                icon: time == null ? Icons.today_outlined : Icons.schedule,
                text: switch ((time, end)) {
                  (null, _) => 'Egész nap',
                  (final start, null) => start!,
                  (final start, final finish) => '$start – ${hhmm(finish!)}',
                },
              ),
              if (event.location case final location?)
                _Detail(icon: Icons.place_outlined, text: location),
              if (event.description case final description?)
                _Detail(icon: Icons.notes_outlined, text: description),
            ],
          ),
        ),
      ),
    );
  }
}

/// A kategória kiválasztható „csipesze". Kategória nélkül felkínálja a
/// hozzáadást; kategóriával a színt és a nevet mutatja, koppintásra átállítható.
class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.category, required this.event});

  final EventCategory? category;
  final CalendarEvent event;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = category?.color ?? scheme.onSurfaceVariant;

    return Material(
      color: color.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: () => showCategoryPicker(context, event.id),
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                category == null ? Icons.label_outline : Icons.label,
                size: 18,
                color: color,
              ),
              const SizedBox(width: 8),
              Text(
                category?.name ?? 'Kategória hozzáadása',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: category == null ? scheme.onSurfaceVariant : color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 14),
          Expanded(
            child: SelectableText(
              text,
              style: theme.textTheme.bodyLarge?.copyWith(height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}
