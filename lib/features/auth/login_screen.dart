import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'auth_controller.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  Future<void> _signIn(BuildContext context) async {
    try {
      await signInWithGoogle();
    } on GoogleSignInException catch (e) {
      // A felhasználó maga zárta be az ablakot — ez nem hiba, ne szóljunk rá.
      if (e.code == GoogleSignInExceptionCode.canceled) return;
      if (context.mounted) _showError(context, e.description ?? e.code.name);
    } catch (e) {
      if (context.mounted) _showError(context, '$e');
    }
  }

  void _showError(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Bejelentkezés sikertelen: $message')),
    );
  }

  @override
  Widget build(BuildContext context) {
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
              onPressed: () => _signIn(context),
              icon: const Icon(Icons.login),
              label: const Text('Bejelentkezés Google-fiókkal'),
            ),
          ],
        ),
      ),
    );
  }
}
