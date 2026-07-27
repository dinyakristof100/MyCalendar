import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ui.dart';
import 'calendar_service.dart';
import 'event_categories.dart';
import 'event_form.dart';
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
    // Betöltés vagy hiba (nincs engedély) alatt üres: a meghívottak listája
    // sosem lehet oka annak, hogy a részletek ne jelenjenek meg.
    final guests =
        ref.watch(eventGuestsProvider(event.id)).value ?? const <EventGuest>[];

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
              _CategoryChip(
                category: category,
                onTap: () => showCategoryPicker(
                  context,
                  selectedId: category?.id,
                  onPick: (id) => ref
                      .read(categoriesProvider.notifier)
                      .assign(event.id, id),
                ),
              ),
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
              if (event.recurring)
                const _Detail(
                  icon: Icons.repeat_rounded,
                  text:
                      'Ismétlődő esemény — a szerkesztés és a törlés a '
                      'sorozat minden előfordulására érvényes',
                ),
              if (event.location case final location?)
                _Detail(icon: Icons.place_outlined, text: location),
              if (event.description case final description?)
                _Detail(icon: Icons.notes_outlined, text: description),
              // Csak a szervező sorai = nincs kivel megosztva. Így nem kell
              // tudnunk, melyik cím a miénk.
              if (guests.any((guest) => !guest.organizer))
                _Detail(
                  icon: Icons.group_outlined,
                  text: guests.map(_guestLine).join('\n'),
                ),
              const SizedBox(height: 4),
              // Wrap, nem Row: a három akció egy 320 px széles kijelzőn (vagy
              // nagyobb rendszerbetűnél) nem fér egy sorba. Így a harmadik
              // szépen a következő sorba kerül ahelyett, hogy a feliratok
              // kifutnának vagy levágódnának.
              Wrap(
                spacing: 10,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _edit(context, ref),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Szerkesztés'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _invite(context, ref),
                    icon: const Icon(Icons.person_add_alt, size: 18),
                    label: const Text('Meghívás'),
                  ),
                  IconButton(
                    onPressed: () => _delete(context, ref),
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Törlés',
                    style: IconButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Szerkesztés: az űrlap ugyanennek az eseménynek az adataival nyílik.
  /// Mentés után frissítjük a listákat és bezárjuk a részletek lapot.
  Future<void> _edit(BuildContext context, WidgetRef ref) async {
    final changed = await showEventForm(context, editing: event);
    if (changed != true) return;
    _refresh(ref);
    if (context.mounted) Navigator.pop(context);
  }

  /// Meghívás: a bekért címek a naptár meghívott-táblájába kerülnek, a meghívót
  /// a Google szinkron küldi ki ([addGuests]).
  ///
  /// Sikernél a lap nyitva marad, és a provider érvénytelenítésétől azonnal
  /// megjelenik az új sor — ez a visszajelzés. Hibánál viszont bezárjuk: a
  /// felcsúszó lap a rendszer-üzenetsávot (SnackBar) eltakarná, és a felhasználó
  /// semmit sem látna a hibából.
  Future<void> _invite(BuildContext context, WidgetRef ref) async {
    // A lap bezárása után a context már nem jó a keresésre — előre elkapjuk.
    final messenger = ScaffoldMessenger.of(context);
    final guests = await _askGuests(context);
    if (guests == null || guests.isEmpty) return;
    try {
      await addGuests(event.id, guests);
      ref.invalidate(eventGuestsProvider(event.id));
    } on PlatformException catch (e) {
      if (context.mounted) Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            e.code == permissionDeniedCode
                ? 'Engedélyezd a naptár írását, majd próbáld újra.'
                : 'Nem sikerült meghívni: ${e.message}',
          ),
        ),
      );
    }
  }

  /// ponytail: ismétlődőnél csak a teljes sorozat törlése megy — az `id` a
  /// sorozat sora. Az „csak ez az előfordulás" ág egy EXDATE hozzáfűzése volna
  /// a sorhoz; addig a párbeszéd megmondja, mi fog történni.
  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(event.recurring ? 'Sorozat törlése' : 'Esemény törlése'),
        content: Text(
          event.recurring
              ? 'A(z) „${event.title}" minden előfordulása törlődik, nem csak '
                    'ez az egy. Biztosan törlöd?'
              : 'Biztosan törlöd? „${event.title}"',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Mégse'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            child: const Text('Törlés'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await deleteEvent(event.id);
      _refresh(ref);
      if (context.mounted) Navigator.pop(context);
    } on PlatformException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.code == permissionDeniedCode
                ? 'Engedélyezd a naptár írását, majd próbáld újra.'
                : 'Nem sikerült törölni: ${e.message}',
          ),
        ),
      );
    }
  }

  /// Mindkét nézet forrását érvénytelenítjük — a lista- és a naptárnézet is
  /// azonnal a friss állapotot mutatja (az emlékeztetők is újraütemeződnek).
  void _refresh(WidgetRef ref) {
    ref.invalidate(upcomingEventsProvider);
    ref.invalidate(monthEventsProvider);
  }
}

/// Meghívottak bekérése. A felismert címekkel tér vissza ([parseGuestEmails]),
/// elvetéskor `null`.
Future<List<String>?> _askGuests(BuildContext context) =>
    showDialog<List<String>>(
      context: context,
      builder: (_) => const _GuestDialog(),
    );

class _GuestDialog extends StatefulWidget {
  const _GuestDialog();

  @override
  State<_GuestDialog> createState() => _GuestDialogState();
}

class _GuestDialogState extends State<_GuestDialog> {
  final _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // A gomb csak akkor él, ha van felismerhető cím a mezőben.
    final guests = parseGuestEmails(_input.text);
    void submit() => Navigator.pop(context, guests);

    return AlertDialog(
      title: const Text('Meghívás'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _input,
            autofocus: true,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            textInputAction: TextInputAction.done,
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) {
              if (guests.isNotEmpty) submit();
            },
            decoration: const InputDecoration(
              labelText: 'E-mail cím',
              hintText: 'anna@pelda.hu, bela@pelda.hu',
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'A meghívót a Google küldi ki a fiókodból, amikor a naptár '
            'legközelebb szinkronizál. Aki elfogadja, ugyanezt az eseményt '
            'látja, és szerkesztheti is.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Mégse'),
        ),
        FilledButton(
          onPressed: guests.isEmpty ? null : submit,
          child: const Text('Meghívás'),
        ),
      ],
    );
  }
}

/// Egy meghívott sora: „Anna – elfogadta". A szervező nem válaszol a saját
/// eseményére, őt csak megjelöljük.
String _guestLine(EventGuest guest) => guest.organizer
    ? '${guest.label} (szervező)'
    : '${guest.label} – ${guestStatusLabel(guest.status)}';

/// A kategória kiválasztható „csipesze". Kategória nélkül felkínálja a
/// hozzáadást; kategóriával a színt és a nevet mutatja, koppintásra átállítható.
class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.category, required this.onTap});

  final EventCategory? category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = category?.color ?? scheme.onSurfaceVariant;

    return Material(
      color: color.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
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
              // Flexible + FitText: a `Row` a nem-flex gyerekének végtelen
              // szélességet ad, ezért egy hosszú kategórianév kifutna. Flexible
              // nélkül a zsugorításnak nincs mihez képest zsugorítania.
              Flexible(
                child: FitText(
                  category?.name ?? 'Kategória hozzáadása',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: category == null ? scheme.onSurfaceVariant : color,
                    fontWeight: FontWeight.w600,
                  ),
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
