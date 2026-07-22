import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:googleapis/calendar/v3.dart';
import 'package:my_calendar/app.dart';
import 'package:my_calendar/features/auth/auth_controller.dart';
import 'package:my_calendar/features/calendar/calendar_service.dart';

/// A providerek felülírásával az auth-guard Firebase és Google API nélkül
/// tesztelhető.
Widget _appWith(AsyncValue<AuthUser?> user) => ProviderScope(
      overrides: [
        currentUserProvider.overrideWithValue(user),
        upcomingEventsProvider.overrideWithValue(const AsyncValue.data(<Event>[])),
      ],
      child: const MyCalendarApp(),
    );

void main() {
  testWidgets('kijelentkezve a login képernyőre terel', (tester) async {
    await tester.pumpWidget(_appWith(const AsyncValue.data(null)));
    await tester.pumpAndSettle();
    expect(find.text('Bejelentkezés Google-fiókkal'), findsOneWidget);
  });

  testWidgets('bejelentkezve a főképernyő látszik', (tester) async {
    await tester.pumpWidget(_appWith(const AsyncValue.data(AuthUser('Teszt'))));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.logout), findsOneWidget);
    expect(find.text('Nincs esemény a következő két hétben.'), findsOneWidget);
  });

  testWidgets('töltés közben nem dob a loginra', (tester) async {
    await tester.pumpWidget(_appWith(const AsyncValue.loading()));
    await tester.pump();
    expect(find.text('Bejelentkezés Google-fiókkal'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
