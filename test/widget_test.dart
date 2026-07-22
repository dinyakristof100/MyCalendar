import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_calendar/app.dart';
import 'package:my_calendar/features/auth/auth_controller.dart';
import 'package:my_calendar/features/calendar/calendar_service.dart';
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
  });

  testWidgets('kijelentkezve a login képernyőre terel', (tester) async {
    await tester.pumpWidget(_appWith(const AsyncValue.data(null)));
    await tester.pumpAndSettle();
    expect(find.text('Bejelentkezés Google-fiókkal'), findsOneWidget);
  });

  testWidgets('bejelentkezve a főképernyő látszik', (tester) async {
    await tester.pumpWidget(_appWith(const AsyncValue.data(AuthUser('Teszt'))));
    await tester.pumpAndSettle();
    expect(find.text('Események'), findsOneWidget);
    expect(find.text('Szabad a két hét'), findsOneWidget);
  });

  testWidgets('a fejléc hamburgermenüje nyitható', (tester) async {
    await tester.pumpWidget(_appWith(const AsyncValue.data(AuthUser('Teszt'))));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(EndDrawerButton));
    await tester.pumpAndSettle();
    expect(find.text('Teszt'), findsOneWidget);
    for (final item in ['Események', 'Naptár', 'Edzésnapló', 'Beállítások']) {
      expect(find.widgetWithText(ListTile, item), findsOneWidget);
    }
    expect(find.text('Kijelentkezés'), findsOneWidget);
  });

  testWidgets('a menüpont átvisz a másik oldalra', (tester) async {
    await tester.pumpWidget(_appWith(const AsyncValue.data(AuthUser('Teszt'))));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(EndDrawerButton));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Naptár'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Naptár'), findsOneWidget);
    expect(find.text('Hamarosan'), findsOneWidget);

    // A rendszer vissza gombja az előző oldalra visz, nem lép ki az appból.
    final popped = await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(popped, isTrue);
    expect(find.widgetWithText(AppBar, 'Események'), findsOneWidget);
  });

  testWidgets('a beállított színkészlet az appra is érvényes', (tester) async {
    await tester.pumpWidget(_appWith(const AsyncValue.data(AuthUser('Teszt'))));
    await tester.pumpAndSettle();
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.system,
    );

    await tester.tap(find.byType(EndDrawerButton));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Beállítások'));
    await tester.pumpAndSettle();
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
    await tester.tap(find.byType(EndDrawerButton));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Edzésnapló'));
    await tester.pumpAndSettle();
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
    await tester.tap(find.byType(EndDrawerButton));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Edzésnapló'));
    await tester.pumpAndSettle();
    expect(
      find.text('Sima heti terv · ezen a héten 0/2 megvan'),
      findsOneWidget,
    );

    // Mégsem: marad pipa nélkül.
    await tester.tap(find.text('mell, tricepsz'));
    await tester.pumpAndSettle();
    expect(
      find.text('Biztosan ezt az edzést teljesítetted ma?'),
      findsOneWidget,
    );
    await tester.tap(find.text('Mégsem'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.check_circle), findsNothing);

    // Megerősítve viszont kipipálódik.
    await tester.tap(find.text('mell, tricepsz'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Igen, megvolt'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    expect(
      find.text('Sima heti terv · ezen a héten 1/2 megvan'),
      findsOneWidget,
    );

    // A kipipált nap nem nyitja meg újra a kérdést.
    await tester.tap(find.text('mell, tricepsz'));
    await tester.pumpAndSettle();
    expect(find.text('Biztosan ezt az edzést teljesítetted ma?'), findsNothing);
  });

  testWidgets('töltés közben nem dob a loginra', (tester) async {
    await tester.pumpWidget(_appWith(const AsyncValue.loading()));
    await tester.pump();
    expect(find.text('Bejelentkezés Google-fiókkal'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
