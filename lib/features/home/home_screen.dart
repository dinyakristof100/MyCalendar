import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:googleapis/calendar/v3.dart';

import '../auth/auth_controller.dart';
import '../calendar/calendar_service.dart';
import '../calendar/reminders.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Amíg a Firebase visszatölti a mentett munkamenetet, még nem tudjuk, van-e
    // bejelentkezett felhasználó. A naptár-lekérés ilyenkor nem indulhat el:
    // scope-engedélyt kérne egy olyan fióktól, ami lehet, hogy nincs is.
    if (ref.watch(currentUserProvider).isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Minden friss lekérés után újraütemezzük az emlékeztetőket — ez a
    // "szinkron": a naptár a forrás, a helyi értesítések csak követik.
    ref.listen(upcomingEventsProvider, (_, next) {
      next.whenData(scheduleReminders);
    });

    final events = ref.watch(upcomingEventsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Következő 14 nap'),
        actions: [
          IconButton(
            tooltip: 'Kijelentkezés',
            onPressed: signOut,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(upcomingEventsProvider.future),
        child: switch (events) {
          AsyncLoading() => const Center(child: CircularProgressIndicator()),
          AsyncError(:final error) => _Message('Nem sikerült lekérni a '
              'naptárat.\n\n$error'),
          AsyncData(:final value) when value.isEmpty =>
            const _Message('Nincs esemény a következő két hétben.'),
          AsyncData(:final value) => ListView.separated(
              itemCount: value.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, i) => _EventTile(value[i]),
            ),
        },
      ),
    );
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile(this.event);
  final Event event;

  @override
  Widget build(BuildContext context) {
    final start = eventStart(event);
    return ListTile(
      leading: Icon(
        start?.allDay ?? false ? Icons.event_note : Icons.schedule,
        color: Theme.of(context).colorScheme.primary,
      ),
      title: Text(event.summary ?? '(névtelen esemény)'),
      subtitle: Text(start == null ? '—' : formatStart(start)),
    );
  }
}

/// Középre igazított üzenet, ami a RefreshIndicator miatt görgethető marad.
class _Message extends StatelessWidget {
  const _Message(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 96, 24, 24),
          child: Text(text, textAlign: TextAlign.center),
        ),
      ],
    );
  }
}
