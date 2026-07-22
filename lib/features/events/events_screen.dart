import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_scaffold.dart';
import '../../core/ui.dart';
import '../auth/auth_controller.dart';
import '../calendar/calendar_service.dart';
import '../calendar/event_details.dart';
import '../calendar/event_form.dart';
import '../calendar/event_groups.dart';
import '../calendar/reminders.dart';

const _gutter = 20.0;

class EventsScreen extends ConsumerStatefulWidget {
  const EventsScreen({super.key});

  @override
  ConsumerState<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends ConsumerState<EventsScreen> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    // Előtérbe kerüléskor újralekérünk: a naptár közben változhatott, és az
    // engedély megadása után is ide térünk vissza. Hidegindításkor nincs
    // állapotváltás, tehát ez nem duplázza az induló lekérést.
    _lifecycle = AppLifecycleListener(
      onResume: () => ref.invalidate(upcomingEventsProvider),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Amíg a Firebase visszatölti a mentett munkamenetet, még nem tudjuk, van-e
    // bejelentkezett felhasználó. A naptár-lekérés ilyenkor nem indulhat el:
    // engedélyt kérne egy olyan fióktól, ami lehet, hogy nincs is.
    if (ref.watch(currentUserProvider).isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Minden friss lekérés után újraütemezzük az emlékeztetőket — ez a
    // "szinkron": a naptár a forrás, a helyi értesítések csak követik.
    ref.listen(upcomingEventsProvider, (_, next) {
      next.whenData(scheduleReminders);
    });

    final events = ref.watch(upcomingEventsProvider);
    return AppScaffold(
      title: 'Események',
      floatingActionButton: FloatingActionButton(
        tooltip: 'Új esemény',
        onPressed: () async {
          // A friss lekérés az emlékeztetőket is újraütemezi (lásd a listent).
          if (await showEventForm(context) ?? false) {
            ref.invalidate(upcomingEventsProvider);
          }
        },
        child: const Icon(Icons.add),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(upcomingEventsProvider.future),
        child: CustomScrollView(
          slivers: [
            switch (events) {
              // Frissítéskor marad a régi lista — a töltőképernyő csak akkor
              // jön, amikor tényleg nincs mit mutatni.
              AsyncLoading(:final value?) when value.isNotEmpty => _EventList(
                events: value,
              ),
              AsyncLoading() => const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator()),
              ),
              // A hiányzó naptár-engedély nem hiba, hanem egy lépés, amit a
              // felhasználónak kell megtennie — ezért kap saját üzenetet.
              AsyncError(:final error)
                  when error is PlatformException &&
                      error.code == permissionDeniedCode =>
                const _Placeholder(
                  icon: Icons.lock_outline,
                  title: 'Engedély kell a naptárhoz',
                  detail:
                      'Fogadd el a felugró kérdést, majd húzd le az ujjad '
                      'a lista frissítéséhez.',
                ),
              AsyncError(:final error) => _Placeholder(
                icon: Icons.cloud_off_outlined,
                title: 'Nem sikerült elérni a naptárat',
                detail: '$error',
              ),
              AsyncData(:final value) when value.isEmpty => const _Placeholder(
                icon: Icons.event_available_outlined,
                title: 'Szabad a két hét',
                detail: 'Nincs egyetlen esemény sem a következő 14 napban.',
              ),
              AsyncData(:final value) => _EventList(events: value),
            },
          ],
        ),
      ),
    );
  }
}

class _EventList extends StatelessWidget {
  const _EventList({required this.events});

  final List<CalendarEvent> events;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final days = groupByDay(events, today: today);

    // A beúszás sorrendjéhez folyamatos sorszám kell a szakaszokon át.
    var slot = 0;
    final children = <Widget>[
      Appear(
        index: slot++,
        child: _NextUpCard(event: events.first, today: today),
      ),
    ];
    for (final day in days) {
      children.add(
        Appear(
          index: slot++,
          child: _DayHeader(day: day),
        ),
      );
      for (final event in day.events) {
        children.add(
          Appear(
            index: slot++,
            child: _EventCard(event: event),
          ),
        );
      }
    }
    // A lebegő gomb alatt is legyen olvasható az utolsó kártya.
    children.add(const SizedBox(height: 96));

    // ponytail: a lista egyben épül fel, nem lustán. 14 nap eseményei néhány
    // tucat sor — ha egyszer hosszabb időszakot mutatunk, jöhet a builder.
    return SliverList(delegate: SliverChildListDelegate(children));
  }
}

/// A képernyő tézise: mi jön legközelebb. Ezért nyitja meg az app valaki —
/// nem azért, hogy listát olvasson.
class _NextUpCard extends StatelessWidget {
  const _NextUpCard({required this.event, required this.today});

  final CalendarEvent event;
  final DateTime today;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final time = formatTime(event);
    final when = dayLabel(event.at, today: today);

    return Padding(
      padding: const EdgeInsets.fromLTRB(_gutter, 4, _gutter, 8),
      // Ink és nem Container: így a koppintás hulláma a kártya felülete fölött
      // látszik, nem alatta.
      child: Ink(
        decoration: cardSurface(
          theme,
          radius: 30,
          color: scheme.primaryContainer,
        ),
        child: InkWell(
          onTap: () => showEventDetails(context, event),
          borderRadius: BorderRadius.circular(30),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 22, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'KÖVETKEZŐ',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: scheme.onPrimaryContainer.withValues(alpha: 0.7),
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.6,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  event.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    color: scheme.onPrimaryContainer,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Icon(
                      time == null ? Icons.today_outlined : Icons.schedule,
                      size: 18,
                      color: scheme.onPrimaryContainer.withValues(alpha: 0.8),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      time == null ? '$when · egész nap' : '$when · $time',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: scheme.onPrimaryContainer.withValues(alpha: 0.9),
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.day});

  final EventDay day;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(_gutter, 22, _gutter, 10),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: day.isToday
                ? scheme.primary
                : scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            day.label.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: day.isToday ? scheme.onPrimary : scheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
        ),
      ),
    );
  }
}

class _EventCard extends StatelessWidget {
  const _EventCard({required this.event});

  final CalendarEvent event;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final time = formatTime(event);

    return Padding(
      padding: const EdgeInsets.fromLTRB(_gutter, 5, _gutter, 5),
      child: Ink(
        decoration: cardSurface(theme),
        child: InkWell(
          onTap: () => showEventDetails(context, event),
          borderRadius: BorderRadius.circular(22),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 15, 18, 17),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  time ?? 'EGÉSZ NAP',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w700,
                    letterSpacing: time == null ? 1.2 : 0.2,
                    // Egyforma szélességű számjegyek, hogy az órák a kártyák
                    // között is egy vonalba essenek.
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  event.title,
                  style: theme.textTheme.titleMedium?.copyWith(height: 1.25),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Üres és hibaállapotok közös váza.
class _Placeholder extends StatelessWidget {
  const _Placeholder({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(40, 24, 40, 80),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Appear(
              index: 0,
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: 40,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 24),
            Appear(
              index: 1,
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Appear(
              index: 2,
              child: Text(
                detail,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.45,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
