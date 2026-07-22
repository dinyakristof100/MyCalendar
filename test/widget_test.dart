import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_calendar/app.dart';
import 'package:my_calendar/features/auth/auth_controller.dart';
import 'package:my_calendar/features/calendar/calendar_service.dart';
import 'package:my_calendar/features/settings/settings_screen.dart';
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
    await initSettings();
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

  testWidgets('töltés közben nem dob a loginra', (tester) async {
    await tester.pumpWidget(_appWith(const AsyncValue.loading()));
    await tester.pump();
    expect(find.text('Bejelentkezés Google-fiókkal'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
