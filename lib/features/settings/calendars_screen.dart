import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_scaffold.dart';
import '../auth/auth_controller.dart';
import '../calendar/calendar_service.dart';
import '../calendar/event_categories.dart';

/// Melyik eszköz-naptár eseményei látszanak az appban.
///
/// Alapból a bejelentkezett Google-fiók saját naptára, az ünnepnapok, a
/// névjegyek fontos dátumai és a MyCalendar van bekapcsolva (lásd
/// [defaultVisible]) — a telefonon lévő többi fiók és feliratkozott naptár
/// (sportnaptárak, munkahelyi fiók) itt kapcsolható be egyesével.
///
/// A kikapcsolt naptárak a listából, a naptárnézetből és az emlékeztetőkből is
/// kiesnek — az esemény-providerek a szűrőt figyelik, ezért a kapcsoló azonnal
/// hat, külön frissítés nélkül.
class CalendarsScreen extends ConsumerWidget {
  const CalendarsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final email = ref.watch(currentUserProvider).value?.email;
    final chosen = ref.watch(visibleCalendarsProvider);

    return AppScaffold(
      title: 'Naptárak',
      body: switch (ref.watch(deviceCalendarsProvider)) {
        AsyncData(:final value) when value.isEmpty => const _Note(
          icon: Icons.event_busy_outlined,
          title: 'Nincs naptár a készüléken',
        ),
        AsyncData(:final value) => _CalendarList(
          calendars: value,
          visible: chosen ?? defaultVisible(value, email),
        ),
        // Engedély nélkül nincs mit felsorolni — az Események lap úgyis kéri.
        AsyncError() => _Note(
          icon: Icons.lock_outline,
          color: theme.colorScheme.error,
          title: 'Nem sikerült beolvasni a naptárakat',
          subtitle: 'Adj naptár-engedélyt, majd gyere vissza ide.',
        ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

/// A naptárak fiókonként csoportosítva: egy telefonon több Google-fiók és
/// jó pár feliratkozott naptár is lehet, egyben ez átláthatatlan lenne.
class _CalendarList extends ConsumerWidget {
  const _CalendarList({required this.calendars, required this.visible});

  final List<DeviceCalendar> calendars;
  final Set<String> visible;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final accounts = <String, List<DeviceCalendar>>{};
    for (final calendar in calendars) {
      accounts.putIfAbsent(calendar.account, () => []).add(calendar);
    }

    void toggle(DeviceCalendar calendar, bool on) {
      final next = visible.toSet();
      if (on) {
        next.add(calendar.key);
      } else {
        next.remove(calendar.key);
      }
      ref.read(visibleCalendarsProvider.notifier).set(next);
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
          child: Text(
            'Csak a bepipált naptárak eseményei jelennek meg az appban. '
            'Alapból a Google-fiókod saját naptára, az ünnepnapok és a '
            'névjegyek fontos dátumai vannak bekapcsolva — a többit itt '
            'kapcsolhatod be.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.4,
            ),
          ),
        ),
        if (visible.isEmpty)
          ListTile(
            leading: Icon(
              Icons.info_outline,
              color: theme.colorScheme.tertiary,
            ),
            title: const Text('Egy naptár sincs bekapcsolva'),
            subtitle: const Text('Így az app egyetlen eseményt sem mutat.'),
          ),
        for (final entry in accounts.entries) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 4),
            child: Text(
              entry.key.isEmpty ? 'Egyéb naptárak' : entry.key,
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          for (final calendar in entry.value)
            CheckboxListTile(
              secondary: CategoryDot(color: calendar.color, size: 18),
              title: Text(calendar.name),
              value: visible.contains(calendar.key),
              onChanged: (on) => toggle(calendar, on ?? false),
            ),
        ],
      ],
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({
    required this.icon,
    required this.title,
    this.subtitle,
    this.color,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Color? color;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon, color: color),
    title: Text(title),
    subtitle: subtitle == null ? null : Text(subtitle!),
  );
}
