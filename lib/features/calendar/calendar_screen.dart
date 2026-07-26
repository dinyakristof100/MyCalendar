import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_scaffold.dart';
import '../../core/ui.dart';
import '../auth/auth_controller.dart';
import 'calendar_days.dart';
import 'calendar_service.dart';
import 'event_categories.dart';
import 'event_details.dart';
import 'event_form.dart';
import 'event_groups.dart';

const _weekdayLabels = ['H', 'K', 'Sze', 'Cs', 'P', 'Szo', 'V'];

/// A naptár hónapnézete: minden nap egy csempe, a napok típusuk szerint
/// színezve, az események a csempe alján legfeljebb három színes sávval (a
/// több napos esemény sávja átér a szomszéd napra). Eseményt itt nem lehet
/// létrehozni — a naptár olvasónézet, mint egy telefonos naptár.
class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  late DateTime _month; // DateTime(év, hónap) — a látható hónap.
  late DateTime _selected; // csak dátum — a kijelölt nap.
  int _slideDir = 1; // az utolsó hónapváltás iránya, a csúszó animációhoz.
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
    _selected = DateTime(now.year, now.month, now.day);
    // Előtérbe kerüléskor a naptár változhatott — újralekérjük a látható hónapot.
    _lifecycle = AppLifecycleListener(
      onResume: () => ref.invalidate(monthEventsProvider(_month)),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  void _shiftMonth(int delta) => setState(() {
    _slideDir = delta.sign;
    _month = DateTime(_month.year, _month.month + delta);
  });

  void _goToday() {
    final now = DateTime.now();
    setState(() {
      _slideDir = _month.isAfter(DateTime(now.year, now.month)) ? -1 : 1;
      _month = DateTime(now.year, now.month);
      _selected = DateTime(now.year, now.month, now.day);
    });
  }

  /// Vízszintes húzás: jobbról balra a következő, balról jobbra az előző
  /// hónap — mint egy lapozás.
  void _onSwipe(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (velocity.abs() < 300) return;
    // Csak a tényleges lapozás rezeg — a küszöb alatti húzás nem.
    HapticFeedback.selectionClick();
    _shiftMonth(velocity < 0 ? 1 : -1);
  }

  /// Napra bontja az eseményeket. Az időpontos, több napon átnyúló esemény
  /// minden érintett napra felkerül — mint egy telefonos naptárban.
  ///
  /// ponytail: az egész napos eseménynek nincs záró dátuma a modellben (az
  /// Android UTC-éjfelet ad, lásd `parseEvent`), ezért az csak a kezdőnapján
  /// jelenik meg. Egy 60 napos felső korlát megvéd a hibás, extrém hosszú
  /// eseményektől.
  Map<DateTime, List<CalendarEvent>> _byDay(List<CalendarEvent> events) {
    final map = <DateTime, List<CalendarEvent>>{};
    for (final event in events) {
      final start = DateTime(event.at.year, event.at.month, event.at.day);
      final endAt = event.end;
      final end = endAt == null
          ? start
          : DateTime(endAt.year, endAt.month, endAt.day);
      var day = start;
      var guard = 0;
      while (!day.isAfter(end) && guard < 60) {
        map.putIfAbsent(day, () => []).add(event);
        day = DateTime(day.year, day.month, day.day + 1);
        guard++;
      }
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    // Amíg a mentett munkamenet töltődik, nem tudjuk, van-e bejelentkezett
    // felhasználó — a naptár-lekérés (és az engedélykérés) ilyenkor nem indulhat.
    if (ref.watch(currentUserProvider).isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final async = ref.watch(monthEventsProvider(_month));
    final categories = ref.watch(categoriesProvider);

    return AppScaffold(
      title: 'Naptár',
      actions: [
        IconButton(
          icon: const Icon(Icons.label_outline),
          tooltip: 'Kategóriák',
          onPressed: () => showCategoryManager(context),
        ),
      ],
      floatingActionButton: FloatingActionButton(
        tooltip: 'Új esemény',
        onPressed: () async {
          // A kijelölt napra nyílik az űrlap; mentés után a rács és az
          // eseménylista (emlékeztetőkkel együtt) is frissül.
          if (await showEventForm(context, initialDay: _selected) ?? false) {
            ref.invalidate(monthEventsProvider(_month));
            ref.invalidate(upcomingEventsProvider);
          }
        },
        child: const Icon(Icons.add),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(monthEventsProvider(_month).future),
        child: GestureDetector(
          onHorizontalDragEnd: _onSwipe,
          child: switch (async) {
            AsyncError(:final error)
                when error is PlatformException &&
                    error.code == permissionDeniedCode =>
              _fill(
                const _Placeholder(
                  icon: Icons.lock_outline,
                  title: 'Engedély kell a naptárhoz',
                  detail:
                      'Fogadd el a felugró kérdést, majd húzd le az ujjad a '
                      'frissítéshez.',
                ),
              ),
            AsyncError(:final error) => _fill(
              _Placeholder(
                icon: Icons.cloud_off_outlined,
                title: 'Nem sikerült elérni a naptárat',
                detail: '$error',
              ),
            ),
            // Töltés közben marad a rács a régi adattal — üres listával indul.
            _ => _CalendarBody(
              month: _month,
              selected: _selected,
              slideDir: _slideDir,
              byDay: _byDay(async.value ?? const []),
              categories: categories,
              onSelect: (day) => setState(() => _selected = day),
              onPrev: () => _shiftMonth(-1),
              onNext: () => _shiftMonth(1),
              onToday: _goToday,
            ),
          },
        ),
      ),
    );
  }

  Widget _fill(Widget child) => ListView(
    physics: const AlwaysScrollableScrollPhysics(),
    children: [SizedBox(height: 480, child: child)],
  );
}

class _CalendarBody extends StatelessWidget {
  const _CalendarBody({
    required this.month,
    required this.selected,
    required this.slideDir,
    required this.byDay,
    required this.categories,
    required this.onSelect,
    required this.onPrev,
    required this.onNext,
    required this.onToday,
  });

  final DateTime month;
  final DateTime selected;
  final int slideDir;
  final Map<DateTime, List<CalendarEvent>> byDay;
  final CategoryState categories;
  final ValueChanged<DateTime> onSelect;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onToday;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final start = gridStart(month);
    final isCurrentMonth = month.year == now.year && month.month == now.month;

    // A sávkiosztás az egész rácsra egyben készül: a több napos esemény csak
    // így kerül minden napján ugyanabba a sávba.
    final lanes = assignEventLanes(byDay);

    final tiles = List.generate(gridDays, (i) {
      final day = DateTime(start.year, start.month, start.day + i);
      return _DayTile(
        day: day,
        inMonth: day.month == month.month,
        isToday: day == today,
        isSelected: day == selected,
        lanes: lanes[day],
        // A hét szélén nincs mihez hozzáérni: a szomszéd nap másik sorba esik.
        lanesBefore: day.weekday == DateTime.monday
            ? null
            : lanes[DateTime(start.year, start.month, start.day + i - 1)],
        lanesAfter: day.weekday == DateTime.sunday
            ? null
            : lanes[DateTime(start.year, start.month, start.day + i + 1)],
        categories: categories,
        onTap: () => onSelect(day),
      );
    });

    final dayEvents = _sorted(byDay[selected] ?? const []);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: [
        _MonthHeader(
          month: month,
          showToday: !isCurrentMonth,
          onPrev: onPrev,
          onNext: onNext,
          onToday: onToday,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: Center(
                  child: Text(
                    _weekdayLabels[i],
                    style: theme.textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                      color: i >= 5
                          ? dayPalette(DayKind.weekend, theme).accent
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        // Hónapváltáskor az új rács a váltás irányából csúszik be, a régi
        // ellenkező irányba ki — a lapozás érzetét adja a swipe-hoz.
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) {
            final incoming = child.key == ValueKey(month);
            final from = (incoming ? slideDir : -slideDir) * 0.18;
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween(
                  begin: Offset(from, 0),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            );
          },
          child: GridView.count(
            key: ValueKey(month),
            crossAxisCount: 7,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 6,
            // Vízszintesen NINCS rés: a szomszédos napok cellái összeérnek,
            // különben a több napos esemény sávja megszakadna. A csempék közti
            // látszó térközt a csempén belüli behúzás adja (lásd [_DayTile]).
            crossAxisSpacing: 0,
            childAspectRatio: 0.82,
            children: tiles,
          ),
        ),
        const SizedBox(height: 20),
        const _Legend(),
        const SizedBox(height: 24),
        _SelectedDayHeader(
          day: selected,
          today: today,
          count: dayEvents.length,
        ),
        const SizedBox(height: 4),
        if (dayEvents.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                'Nincs esemény ezen a napon',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          )
        else
          for (final event in dayEvents) _DayEventTile(event: event),
      ],
    );
  }

  /// Egy napon belül az egész naposak elöl, utána kezdés szerint.
  List<CalendarEvent> _sorted(List<CalendarEvent> events) =>
      [...events]..sort((a, b) {
        if (a.allDay != b.allDay) return a.allDay ? -1 : 1;
        return a.at.compareTo(b.at);
      });
}

class _MonthHeader extends StatelessWidget {
  const _MonthHeader({
    required this.month,
    required this.showToday,
    required this.onPrev,
    required this.onNext,
    required this.onToday,
  });

  final DateTime month;
  final bool showToday;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onToday;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        IconButton(
          onPressed: onPrev,
          icon: const Icon(Icons.chevron_left),
          tooltip: 'Előző hónap',
        ),
        Expanded(
          child: Column(
            children: [
              Text(
                '${month.year}. ${monthName(month.month)}',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (showToday)
                TextButton(
                  onPressed: onToday,
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 28),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: const Text('Ugrás a mai napra'),
                ),
            ],
          ),
        ),
        IconButton(
          onPressed: onNext,
          icon: const Icon(Icons.chevron_right),
          tooltip: 'Következő hónap',
        ),
      ],
    );
  }
}

/// Egy eseménysáv magassága és a sávok közti rés. Három sáv fér ki, a helyüket
/// a csempe akkor is kihagyja, ha aznap nincs esemény — így az eltérő
/// eseményszám nem ugráltatja a rácsot.
const _barHeight = 4.0;
const _barGap = 2.0;
const _barsBottom = 4.0;
const _barsHeight = maxDayLanes * _barHeight + (maxDayLanes - 1) * _barGap;

/// A csempe háttere és a cella széle közti térköz. A rácsban nincs vízszintes
/// rés (különben a több napos sáv megszakadna), a csempék közti látszó
/// hézagot ez a behúzás adja — a folytatódó sáv pedig épp ezt tölti ki.
const _tileInset = 3.0;

class _DayTile extends StatelessWidget {
  const _DayTile({
    required this.day,
    required this.inMonth,
    required this.isToday,
    required this.isSelected,
    required this.lanes,
    required this.lanesBefore,
    required this.lanesAfter,
    required this.categories,
    required this.onTap,
  });

  final DateTime day;
  final bool inMonth;
  final bool isToday;
  final bool isSelected;

  /// A nap sávjai (lásd `assignEventLanes`), és ugyanez a szomszéd napokról —
  /// abból derül ki, hogy a sáv folytatódik-e balra vagy jobbra. `null`, ha
  /// azon a napon nincs esemény, vagy a szomszéd másik sorba esik.
  final List<CalendarEvent?>? lanes;
  final List<CalendarEvent?>? lanesBefore;
  final List<CalendarEvent?>? lanesAfter;

  final CategoryState categories;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final palette = dayPalette(dayKindOf(day), theme);

    final numberColor = isToday
        ? scheme.onPrimary
        : (inMonth ? palette.accent : palette.accent.withValues(alpha: 0.45));

    final tile = Stack(
      // A háttér a cella teljes méretét kitölti — nélküle a Stack csak a
      // napszám köré húzódna össze.
      fit: StackFit.expand,
      // A folytatódó sáv egy hajszálnyit átlóg a szomszéd cellába (lásd [_bar]).
      clipBehavior: Clip.none,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: _tileInset),
          child: Material(
            color: palette.fill,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                // Alul kihagyjuk a sávok helyét, hogy a szám fölöttük maradjon.
                padding: const EdgeInsets.fromLTRB(
                  2,
                  4,
                  2,
                  _barsBottom + _barsHeight,
                ),
                alignment: Alignment.center,
                // A FittedBox szükség esetén arányosan kicsinyíti a tartalmat,
                // így a csempe semmilyen képernyőn vagy betűméretnél nem tud
                // túlcsordulni.
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Container(
                    width: 26,
                    height: 26,
                    alignment: Alignment.center,
                    decoration: isToday
                        ? BoxDecoration(
                            color: scheme.primary,
                            shape: BoxShape.circle,
                          )
                        : null,
                    child: Text(
                      '${day.day}',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: numberColor,
                        fontWeight: isToday || isSelected
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        // A sávok a cella teljes szélességét használhatják — a szomszéd nap
        // sávja pontosan a cella határán folytatódik.
        for (var lane = 0; lane < maxDayLanes; lane++)
          if (lanes?[lane] != null) _bar(lane, scheme),
        // A kijelölés kerete a sávok FÖLÉ kerül: a nap sávjai így a kereten
        // belül maradnak, nem vágják át a vonalát.
        if (isSelected)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: _tileInset),
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: scheme.primary, width: 2),
                ),
              ),
            ),
          ),
      ],
    );

    return inMonth ? tile : Opacity(opacity: 0.55, child: tile);
  }

  /// Egy sáv: a kategóriás esemény a kategória színét kapja, a kategória
  /// nélküli semleges szürkét. A szomszéd nap felé, ha ott ugyanez az esemény
  /// áll ebben a sávban, a behúzás és a lekerekítés is elmarad — így ér össze
  /// a több napos esemény sávja.
  ///
  /// A folytatódó vég ráadásul egy logikai pixelt átlóg a szomszéd cellába:
  /// enélkül a két szakasz élsimított széle között halvány hajszálvonal
  /// maradna, épp ott, ahol folytonosnak kellene látszania.
  Widget _bar(int lane, ColorScheme scheme) {
    final event = lanes![lane]!;
    final joinLeft = lanesBefore?[lane] == event;
    final joinRight = lanesAfter?[lane] == event;

    return Positioned(
      left: joinLeft ? -1 : _tileInset,
      right: joinRight ? -1 : _tileInset,
      bottom: _barsBottom + (maxDayLanes - 1 - lane) * (_barHeight + _barGap),
      height: _barHeight,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: categories.of(event.id)?.color ?? scheme.onSurfaceVariant,
          borderRadius: BorderRadius.horizontal(
            left: Radius.circular(joinLeft ? 0 : 2),
            right: Radius.circular(joinRight ? 0 : 2),
          ),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: 16,
      runSpacing: 8,
      children: [
        for (final kind in DayKind.values)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: dayPalette(kind, theme).fill,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: dayPalette(
                      kind,
                      theme,
                    ).accent.withValues(alpha: 0.5),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(dayKindLabel(kind), style: theme.textTheme.labelSmall),
            ],
          ),
      ],
    );
  }
}

class _SelectedDayHeader extends StatelessWidget {
  const _SelectedDayHeader({
    required this.day,
    required this.today,
    required this.count,
  });

  final DateTime day;
  final DateTime today;
  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Text(
            dayLabel(day, today: today),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (count > 0)
          Text(
            count == 1 ? '1 esemény' : '$count esemény',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}

/// A kijelölt nap egy eseménye. A kategória színe bal oldali sávként és az
/// időpont színeként is megjelenik.
class _DayEventTile extends ConsumerWidget {
  const _DayEventTile({required this.event});

  final CalendarEvent event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final category = ref.watch(categoriesProvider).of(event.id);
    final accent = category?.color ?? scheme.primary;
    final time = formatTime(event);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: AppCard(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
        ),
        child: InkWell(
          onTap: () => showEventDetails(context, event),
          borderRadius: BorderRadius.circular(16),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 5,
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: const BorderRadius.horizontal(
                      left: Radius.circular(16),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              time ?? 'EGÉSZ NAP',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: accent,
                                fontWeight: FontWeight.w700,
                                letterSpacing: time == null ? 1.2 : 0.2,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                            if (category != null) ...[
                              const Spacer(),
                              Text(
                                category.name,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          event.title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            height: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Üres- és hibaállapotok közös váza (a naptárnézet saját, egyszerűbb változata).
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 24, 40, 24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
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
          const SizedBox(height: 24),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            detail,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}
