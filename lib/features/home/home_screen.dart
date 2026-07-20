import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_controller.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('MyCalendar'),
        actions: [
          IconButton(
            tooltip: 'Kijelentkezés',
            onPressed: () =>
                ref.read(authControllerProvider.notifier).signOut(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Szia, ${user?.name ?? ''}! 👋\n\n'
            'Ide jön majd a naptár és az edzésterv.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
      ),
    );
  }
}
