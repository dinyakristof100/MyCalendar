import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_calendar/app.dart';

void main() {
  testWidgets('kijelentkezve a login képernyőre terel', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: MyCalendarApp()));
    await tester.pumpAndSettle();
    expect(find.text('Bejelentkezés Google-fiókkal'), findsOneWidget);
  });

  testWidgets('bejelentkezés után a főképernyő látszik', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: MyCalendarApp()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bejelentkezés Google-fiókkal'));
    await tester.pumpAndSettle();
    expect(find.text('MyCalendar'), findsOneWidget); // AppBar cím
    expect(find.byIcon(Icons.logout), findsOneWidget);
  });
}
