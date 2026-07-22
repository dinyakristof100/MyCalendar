import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_scaffold.dart';
import '../../core/prefs.dart';

const _key = 'themeMode';

/// Az app színkészlete. Alapértelmezés: a telefon beállítása.
final themeModeProvider = NotifierProvider<ThemeModeController, ThemeMode>(
  ThemeModeController.new,
);

class ThemeModeController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() =>
      // Ismeretlen (pl. régi vagy kézzel írt) érték esetén is a rendszer a
      // biztonságos alapértelmezés.
      ThemeMode.values.asNameMap()[prefs.getString(_key)] ?? ThemeMode.system;

  Future<void> set(ThemeMode mode) async {
    state = mode;
    await prefs.setString(_key, mode.name);
  }
}

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return AppScaffold(
      title: 'Beállítások',
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
            child: Text(
              'Színkészlet',
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          RadioGroup<ThemeMode>(
            groupValue: ref.watch(themeModeProvider),
            onChanged: (mode) {
              if (mode != null) {
                ref.read(themeModeProvider.notifier).set(mode);
              }
            },
            child: const Column(
              children: [
                RadioListTile(
                  value: ThemeMode.light,
                  title: Text('Világos'),
                  secondary: Icon(Icons.light_mode_outlined),
                ),
                RadioListTile(
                  value: ThemeMode.dark,
                  title: Text('Sötét'),
                  secondary: Icon(Icons.dark_mode_outlined),
                ),
                RadioListTile(
                  value: ThemeMode.system,
                  title: Text('Rendszer szerint'),
                  subtitle: Text('A telefon beállítását követi'),
                  secondary: Icon(Icons.brightness_auto_outlined),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
