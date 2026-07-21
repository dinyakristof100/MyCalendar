import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_controller.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('MyCalendar'),
        actions: [
          IconButton(
            tooltip: 'Kijelentkezés',
            onPressed: signOut,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: switch (user) {
        AsyncLoading() => const Center(child: CircularProgressIndicator()),
        AsyncError(:final error) => Center(child: Text('Hiba: $error')),
        _ => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Szia, ${user.value?.name ?? ''}! 👋\n\n'
                'Ide jön majd a naptár és az edzésterv.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ),
      },
    );
  }
}
