import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/app_scaffold.dart';
import '../../core/cloud_sync.dart';
import '../../core/prefs.dart';
import '../auth/auth_controller.dart';
import '../workouts/workout_progress.dart';
import 'import_export.dart';
import 'wallpaper.dart';

const _key = 'themeMode';
const _timeKeyboardKey = 'timePickerKeyboard';

/// Billentyűzettel (számbeírás) induljon-e az esemény időválasztója a grafikus
/// óra helyett.
///
/// Alapból igen: egy időpont beírása két koppintás, a mutatók tekergetése
/// ennél mindig lassabb. A rendszer időválasztójában amúgy is ott a váltógomb —
/// ez csak azt dönti el, melyik móddal NYÍLIK.
final timeKeyboardProvider = NotifierProvider<TimeKeyboardController, bool>(
  TimeKeyboardController.new,
);

class TimeKeyboardController extends Notifier<bool> {
  @override
  // Hiányzó beállítás = az alapértelmezés; csak a kifejezett „false" kapcsol
  // vissza az órára.
  bool build() => prefs.getString(_timeKeyboardKey) != 'false';

  Future<void> set(bool on) async {
    state = on;
    await saveSetting(_timeKeyboardKey, on ? 'true' : 'false');
  }
}

/// A klasszikus három mód akcentje — ugyanez az indigó van az ikonban és a
/// webes oldalakon.
const _indigo = Color(0xFF3F51B5);

/// Egy választható megjelenés: fényerő + akcentszín egyben. Az [id] kerül az
/// adatbázisba, ezért a régi „system/light/dark” értékek szándékosan azonosak
/// maradnak — a korábban mentett választás így érvényben marad.
class AppStyle {
  const AppStyle({
    required this.id,
    required this.label,
    required this.icon,
    required this.mode,
    required this.seed,
    this.subtitle,
  });

  final String id;
  final String label;
  final String? subtitle;
  final IconData icon;
  final ThemeMode mode;
  final Color seed;
}

/// A választható stílusok. Az első három a régi rendszer/világos/sötét, utána a
/// saját paletták — mindegyik világos és sötét párban. Új stílushoz elég ide egy
/// sort felvenni. A sötét párokat a kitöltött ikon különbözteti meg.
const appStyles = <AppStyle>[
  AppStyle(
    id: 'system',
    label: 'Rendszer szerint',
    subtitle: 'A telefon beállítását követi',
    icon: Icons.brightness_auto_outlined,
    mode: ThemeMode.system,
    seed: _indigo,
  ),
  AppStyle(
    id: 'light',
    label: 'Világos',
    icon: Icons.light_mode_outlined,
    mode: ThemeMode.light,
    seed: _indigo,
  ),
  AppStyle(
    id: 'dark',
    label: 'Sötét',
    icon: Icons.dark_mode_outlined,
    mode: ThemeMode.dark,
    seed: _indigo,
  ),
  AppStyle(
    id: 'girly',
    label: 'Csajos',
    subtitle: 'Rózsaszín, világos',
    icon: Icons.favorite_outline,
    mode: ThemeMode.light,
    seed: Color(0xFFEC407A),
  ),
  AppStyle(
    id: 'girly_dark',
    label: 'Csajos sötét',
    subtitle: 'Rózsaszín, sötét',
    icon: Icons.favorite,
    mode: ThemeMode.dark,
    seed: Color(0xFFEC407A),
  ),
  AppStyle(
    id: 'manly_light',
    label: 'Pasis',
    subtitle: 'Acélos, világos',
    icon: Icons.fitness_center_outlined,
    mode: ThemeMode.light,
    seed: Color(0xFF00695C),
  ),
  // A régi „manly" végig sötét volt — az id és a fényerő marad, csak a címke
  // igazodik a párokhoz, hogy a korábbi választás ne váltson át világosra.
  AppStyle(
    id: 'manly',
    label: 'Pasis sötét',
    subtitle: 'Acélos, sötét',
    icon: Icons.fitness_center,
    mode: ThemeMode.dark,
    seed: Color(0xFF00695C),
  ),
  AppStyle(
    id: 'clean',
    label: 'Letisztult',
    subtitle: 'Visszafogott, semleges',
    icon: Icons.circle_outlined,
    mode: ThemeMode.light,
    seed: Color(0xFF546E7A),
  ),
  AppStyle(
    id: 'clean_dark',
    label: 'Letisztult sötét',
    subtitle: 'Visszafogott, sötét',
    icon: Icons.circle,
    mode: ThemeMode.dark,
    seed: Color(0xFF546E7A),
  ),
  AppStyle(
    id: 'kids',
    label: 'Gyerekbarát',
    subtitle: 'Vidám, élénk',
    icon: Icons.child_care_outlined,
    mode: ThemeMode.light,
    seed: Color(0xFFFF9800),
  ),
  AppStyle(
    id: 'kids_dark',
    label: 'Gyerekbarát sötét',
    subtitle: 'Vidám, sötét',
    icon: Icons.child_care,
    mode: ThemeMode.dark,
    seed: Color(0xFFFF9800),
  ),
];

/// Az app megjelenése. Alapértelmezés (ismeretlen vagy hiányzó érték esetén is)
/// az első stílus: a rendszer szerinti.
final appStyleProvider = NotifierProvider<AppStyleController, AppStyle>(
  AppStyleController.new,
);

class AppStyleController extends Notifier<AppStyle> {
  @override
  AppStyle build() => appStyles.firstWhere(
    (s) => s.id == prefs.getString(_key),
    orElse: () => appStyles.first,
  );

  Future<void> set(AppStyle style) async {
    state = style;
    await saveSetting(_key, style.id);
  }
}

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final name = ref.watch(currentUserProvider).value?.name;

    return AppScaffold(
      title: 'Beállítások',
      body: ListView(
        children: [
          const _SectionTitle('Fiók'),
          if (name != null)
            ListTile(
              leading: CircleAvatar(
                backgroundColor: theme.colorScheme.primaryContainer,
                foregroundColor: theme.colorScheme.onPrimaryContainer,
                child: Text(
                  name.characters.first.toUpperCase(),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              title: Text(name),
              subtitle: const Text('Google-fiók'),
            ),
          ListTile(
            leading: Icon(Icons.logout, color: theme.colorScheme.error),
            title: Text(
              'Kijelentkezés',
              style: TextStyle(color: theme.colorScheme.error),
            ),
            onTap: signOut,
          ),
          const Divider(height: 24),
          const _SectionTitle('Színkészlet'),
          RadioGroup<AppStyle>(
            groupValue: ref.watch(appStyleProvider),
            onChanged: (style) {
              if (style != null) {
                ref.read(appStyleProvider.notifier).set(style);
              }
            },
            child: Column(
              children: [
                for (final style in appStyles)
                  RadioListTile(
                    value: style,
                    title: Text(style.label),
                    subtitle: style.subtitle == null
                        ? null
                        : Text(style.subtitle!),
                    // A seed színnel festett ikon előnézetet ad a palettáról.
                    secondary: Icon(style.icon, color: style.seed),
                  ),
              ],
            ),
          ),
          const Divider(height: 24),
          const _SectionTitle('Háttérkép'),
          const _WallpaperTile(),
          const Divider(height: 24),
          const _SectionTitle('Események'),
          SwitchListTile(
            secondary: const Icon(Icons.keyboard_outlined),
            title: const Text('Időpont beírása billentyűzettel'),
            subtitle: const Text(
              'Az esemény óráját és percét gépelve add meg. Kikapcsolva a '
              'grafikus óra nyílik — a választón belül amúgy is válthatsz a '
              'kettő között.',
            ),
            value: ref.watch(timeKeyboardProvider),
            onChanged: (on) => ref.read(timeKeyboardProvider.notifier).set(on),
          ),
          const Divider(height: 24),
          const _SectionTitle('Naptárak'),
          ListTile(
            leading: const Icon(Icons.calendar_month_outlined),
            title: const Text('Megjelenő naptárak'),
            subtitle: const Text(
              'Alapból csak a saját Google-naptárad látszik — itt kapcsolhatod '
              'be a többit.',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/calendars'),
          ),
          const Divider(height: 24),
          const _SectionTitle('Adatok'),
          const ImportExportTiles(),
          const Divider(height: 24),
          const _SectionTitle('Edzés'),
          SwitchListTile(
            secondary: const Icon(Icons.event_repeat),
            title: const Text('Le nem edzett napok átcsúsztatása'),
            subtitle: const Text(
              'A hét végén nyitva maradt napokat áthozza a következő hétre. '
              'Egy napot a naplóban hosszan nyomva „Kihagyom"-mal zárhatsz le, '
              'ezt nem hozzuk át.',
            ),
            value: ref.watch(carryOverProvider),
            onChanged: (on) => ref.read(carryOverProvider.notifier).set(on),
          ),
          const Divider(height: 24),
          const _SectionTitle('Segítség'),
          ListTile(
            leading: const Icon(Icons.help_outline),
            title: const Text('Súgó és útmutató'),
            subtitle: const Text(
              'Mi hol van az appban — témánként, és a bemutató is újranézhető.',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/help'),
          ),
          const Divider(height: 24),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
            child: Text(
              'A naptáradat a készülékről olvassuk. A beállításaid, '
              'kategóriáid, edzésterveid és -haladásod (a sorozatoddal együtt) a '
              'Google-fiókodhoz kötve a felhőbe is mentődnek, hogy új telefonon '
              'visszaálljanak. Adataid törlését a fejlesztőnél kérheted.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Háttérkép választása a galériából, előnézettel és eltávolítással.
///
/// A kép a telefonon marad — a felhőbe nem megy (lásd [wallpaperProvider]).
class _WallpaperTile extends ConsumerWidget {
  const _WallpaperTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final path = ref.watch(wallpaperProvider);

    return ListTile(
      leading: path == null
          ? const Icon(Icons.image_outlined)
          : ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.file(
                File(path),
                width: 40,
                height: 40,
                fit: BoxFit.cover,
              ),
            ),
      title: Text(path == null ? 'Háttérkép választása' : 'Háttérkép cseréje'),
      subtitle: const Text(
        'A képet a telefonon tartjuk, nem szinkronizáljuk a felhőbe.',
      ),
      trailing: path == null
          ? null
          : IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Háttérkép eltávolítása',
              onPressed: () => ref.read(wallpaperProvider.notifier).clear(),
            ),
      onTap: () => ref.read(wallpaperProvider.notifier).pick(),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
      child: Text(
        text,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
