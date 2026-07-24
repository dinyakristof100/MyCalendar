import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_calendar/app.dart';
import 'package:my_calendar/features/auth/auth_controller.dart';
import 'package:my_calendar/features/calendar/calendar_service.dart';
import 'package:my_calendar/features/calendar/event_groups.dart';
import 'package:my_calendar/features/workouts/motivation.dart';
import 'package:my_calendar/core/prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A providerek felülírásával az auth-guard Firebase és Google API nélkül
/// tesztelhető.
Widget _appWith(AsyncValue<AuthUser?> user) => ProviderScope(
  overrides: [
    currentUserProvider.overrideWithValue(user),
    upcomingEventsProvider.overrideWithValue(
      const AsyncValue.data(<CalendarEvent>[]),
    ),
  ],
  child: const MyCalendarApp(),
);

/// Átvált a megadott fülre az alsó navigációs sávon.
Future<void> _goTab(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label)),
  );
  await tester.pumpAndSettle();
}

void main() {
  // Az app a mentett beállításokat a main-ben tölti be — a teszt ugyanezt
  // csinálja, memóriában.
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await initPrefs();
    // Az értesítés-plugin natív oldala nincs a tesztben: a pipálás
    // újraütemezné az esti kérdéseket, ezt nyeljük el.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('dexterous.com/flutter/local_notifications'),
          (_) async => null,
        );
    // A naptárnézet a hónap eseményeit a natív csatornán kéri — üres naptárt
    // adunk vissza, hogy a rács adat nélkül is felépüljön.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('mycalendar/device_calendar'),
          (_) async => <Object?>[],
        );
  });

  testWidgets('kijelentkezve a login képernyőre terel', (tester) async {
    await tester.pumpWidget(_appWith(const AsyncValue.data(null)));
    await tester.pumpAndSettle();
    expect(find.text('Bejelentkezés Google-fiókkal'), findsOneWidget);
  });

  testWidgets('bejelentkezve a főképernyő és az alsó navigáció látszik', (
    tester,
  ) async {
    await tester.pumpWidget(_appWith(const AsyncValue.data(AuthUser('Teszt'))));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Események'), findsOneWidget);
    expect(find.text('Szabad a két hét'), findsOneWidget);
    for (final label in ['Események', 'Naptár', 'Edzésnapló', 'Beállítások']) {
      expect(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text(label),
        ),
        findsOneWidget,
      );
    }
  });

  testWidgets('a naptár fül a hónapos rácsot mutatja', (tester) async {
    await tester.pumpWidget(_appWith(const AsyncValue.data(AuthUser('Teszt'))));
    await tester.pumpAndSettle();
    await _goTab(tester, 'Naptár');
    expect(find.widgetWithText(AppBar, 'Naptár'), findsOneWidget);
    // A hét napjainak fejléce a naptárrács tetején — a valódi naptárnézet
    // felépült (nem placeholder).
    expect(find.text('Sze'), findsOneWidget);

    // A rendszer vissza gombja nem lép ki az appból, hanem a főképernyőre visz.
    final popped = await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(popped, isTrue);
    expect(find.widgetWithText(AppBar, 'Események'), findsOneWidget);
  });

  testWidgets('a naptár fejlécéből elérhető és megnyílik a kategória-kezelő', (
    tester,
  ) async {
    await tester.pumpWidget(_appWith(const AsyncValue.data(AuthUser('Teszt'))));
    await tester.pumpAndSettle();
    await _goTab(tester, 'Naptár');

    // A kategóriák önálló belépési pontja a fejlécben van — nem kell hozzá
    // előbb eseményt megnyitni.
    final action = find.byTooltip('Kategóriák');
    expect(action, findsOneWidget);

    await tester.tap(action);
    await tester.pumpAndSettle();
    // A kezelő lap (esemény nélkül) létrehozással.
    expect(find.text('Naptárkategóriák'), findsOneWidget);
    expect(find.text('Új kategória'), findsOneWidget);
  });

  testWidgets('oldalra húzva vált a naptár hónapja', (tester) async {
    await tester.pumpWidget(_appWith(const AsyncValue.data(AuthUser('Teszt'))));
    await tester.pumpAndSettle();
    await _goTab(tester, 'Naptár');

    final now = DateTime.now();
    final current = DateTime(now.year, now.month);
    String header(DateTime m) => '${m.year}. ${monthName(m.month)}';
    expect(find.text(header(current)), findsOneWidget);

    // Jobbról balra húzás: következő hónap. A húzás a lista látható felső
    // részéről indul — a rács alja a teszt-ablakban a hajtás alá lóg.
    await tester.fling(find.byType(ListView), const Offset(-400, 0), 1200);
    await tester.pumpAndSettle();
    final next = DateTime(current.year, current.month + 1);
    expect(find.text(header(next)), findsOneWidget);

    // Balról jobbra húzás: vissza az előzőre.
    await tester.fling(find.byType(ListView), const Offset(400, 0), 1200);
    await tester.pumpAndSettle();
    expect(find.text(header(current)), findsOneWidget);
  });

  testWidgets('a beállítások fülön a fiók és a kijelentkezés is ott van', (
    tester,
  ) async {
    await tester.pumpWidget(_appWith(const AsyncValue.data(AuthUser('Teszt'))));
    await tester.pumpAndSettle();
    await _goTab(tester, 'Beállítások');
    expect(find.text('Teszt'), findsOneWidget);
    expect(find.text('Kijelentkezés'), findsOneWidget);
  });

  testWidgets('a beállított színkészlet az appra is érvényes', (tester) async {
    await tester.pumpWidget(_appWith(const AsyncValue.data(AuthUser('Teszt'))));
    await tester.pumpAndSettle();
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.system,
    );

    await _goTab(tester, 'Beállítások');
    await tester.tap(find.text('Sötét'));
    await tester.pumpAndSettle();

    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.dark,
    );
  });

  testWidgets('edzésterv felvitele és megjelenítése', (tester) async {
    // Magas ablak, hogy a lista minden mezője megépüljön — így nem kell
    // görgetni a teszt közben.
    await tester.binding.setSurfaceSize(const Size(1080, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_appWith(const AsyncValue.data(AuthUser('Teszt'))));
    await tester.pumpAndSettle();
    await _goTab(tester, 'Edzésnapló');
    expect(find.text('Még nincs edzésterved'), findsOneWidget);

    await tester.tap(find.text('Edzésterv létrehozása'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'A terv neve'),
      'Erő',
    );
    // Alapból 3 nap, egyet levéve 2.
    await tester.tap(find.byTooltip('Kevesebb nap'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('0-0')), 'mell, tricepsz');
    await tester.enterText(find.byKey(const ValueKey('0-1')), 'hát, bicepsz');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Edzésterv mentése'));
    await tester.pumpAndSettle();

    expect(find.text('Erő'), findsOneWidget);
    expect(
      find.text('Sima heti terv · ezen a héten 0/2 megvan'),
      findsOneWidget,
    );
    expect(find.text('1. NAP'), findsOneWidget);
    expect(find.text('mell, tricepsz'), findsOneWidget);
  });

  testWidgets('a mai edzés csak megerősítés után kap pipát', (tester) async {
    await prefs.setString(
      'workoutPlans',
      '[{"id":"p1","name":"Erő","weeks":[["mell, tricepsz","hát, bicepsz"]]}]',
    );
    await prefs.setString('activeWorkoutPlan', 'p1');
    addTearDown(() async {
      await prefs.remove('workoutPlans');
      await prefs.remove('activeWorkoutPlan');
      await prefs.remove('workoutProgress');
    });

    await tester.pumpWidget(_appWith(const AsyncValue.data(AuthUser('Teszt'))));
    await tester.pumpAndSettle();
    await _goTab(tester, 'Edzésnapló');
    expect(
      find.text('Sima heti terv · ezen a héten 0/2 megvan'),
      findsOneWidget,
    );

    // Amíg a hét nincs meg, a gondolkodtató kártya látszik a napi párossal.
    final reflection = reflectionFor(DateTime.now());
    expect(find.text('MIÉRT ÉRI MEG MA?'), findsOneWidget);
    expect(find.text(reflection.gain), findsOneWidget);
    expect(find.text(reflection.cost), findsOneWidget);

    // Koppintásra nem történik semmi — csak hosszú nyomásra kérdez.
    await tester.tap(find.text('mell, tricepsz'));
    await tester.pumpAndSettle();
    expect(find.text('Mi lett ezzel a nappal?'), findsNothing);

    // Mégsem: marad pipa nélkül.
    await tester.longPress(find.text('mell, tricepsz'));
    await tester.pumpAndSettle();
    expect(find.text('Mi lett ezzel a nappal?'), findsOneWidget);
    await tester.tap(find.text('Mégsem'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.check_circle), findsNothing);

    // Megerősítve viszont kipipálódik, és dicséret jár érte.
    await tester.longPress(find.text('mell, tricepsz'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Megvolt'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    expect(
      find.text('Sima heti terv · ezen a héten 1/2 megvan'),
      findsOneWidget,
    );
    expect(
      find.text(praiseFor(done: 1, total: 2, day: DateTime.now())),
      findsOneWidget,
    );
    // A SnackBar magától eltűnik — a lejáratát is lepörgetjük, hogy ne
    // maradjon függő időzítő a teszt végén.
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();

    // A kipipált nap nem nyitja meg újra a kérdést.
    await tester.longPress(find.text('mell, tricepsz'));
    await tester.pumpAndSettle();
    expect(find.text('Mi lett ezzel a nappal?'), findsNothing);
  });

  testWidgets('töltés közben nem dob a loginra', (tester) async {
    await tester.pumpWidget(_appWith(const AsyncValue.loading()));
    await tester.pump();
    expect(find.text('Bejelentkezés Google-fiókkal'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
