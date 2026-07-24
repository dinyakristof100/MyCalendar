import 'package:flutter_test/flutter_test.dart';
import 'package:my_calendar/core/app_update.dart';

void main() {
  test('a kiadás-tagből kiolvassa a nevet és a versionCode-ot', () {
    final r = parseRelease('v1.2.1+1008');
    expect(r?.versionName, '1.2.1');
    expect(r?.versionCode, 1008);
  });

  test('v-prefix nélkül és rövidebb névvel is működik', () {
    expect(parseRelease('1.3+9')?.versionCode, 9);
    expect(parseRelease('v2.0+42')?.versionName, '2.0');
  });

  test('értelmezhetetlen tag null — sose ajánlunk ilyet', () {
    expect(parseRelease('kacsa'), isNull);
    expect(parseRelease('v1.2.1'), isNull); // nincs +versionCode
  });
}
