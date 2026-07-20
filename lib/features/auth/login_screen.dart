import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_controller.dart';

class LoginScreen extends ConsumerWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.calendar_month, size: 96, color: scheme.primary),
            const SizedBox(height: 16),
            Text('MyCalendar',
                style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 48),
            FilledButton.icon(
              onPressed: () =>
                  ref.read(authControllerProvider.notifier).signIn(),
              icon: const Icon(Icons.login),
              label: const Text('Bejelentkezés Google-fiókkal'),
            ),
          ],
        ),
      ),
    );
  }
}
