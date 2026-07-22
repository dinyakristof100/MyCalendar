import 'package:shared_preferences/shared_preferences.dart';

/// A helyben tárolt beállítások. A `main` tölti be indításkor, hogy a mentett
/// értékek már az első képnél érvényesek legyenek — utólagos beolvasásnál egy
/// pillanatra a rossz téma villanna fel.
late final SharedPreferences prefs;

Future<void> initPrefs() async => prefs = await SharedPreferences.getInstance();
