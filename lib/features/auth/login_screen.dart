import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../core/ui.dart';
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
      SnackBar(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        content: Text('Bejelentkezés sikertelen: $message'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(flex: 3),
              Appear(
                index: 0,
                child: Center(
                  child: Container(
                    width: 96,
                    height: 96,
                    decoration: cardSurface(
                      theme,
                      radius: 28,
                      color: scheme.primaryContainer,
                    ),
                    child: Icon(
                      Icons.event_available_outlined,
                      size: 46,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              Appear(
                index: 1,
                child: Text(
                  'MyCalendar',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.displaySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.5,
                  ),
                ),
              ),
              const Spacer(flex: 4),
              Appear(
                index: 2,
                child: FilledButton(
                  onPressed: () => _signIn(context),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                    elevation: 3,
                    shadowColor: scheme.primary.withValues(alpha: 0.5),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                    textStyle: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  child: const Text('Bejelentkezés Google-fiókkal'),
                ),
              ),
              const SizedBox(height: 18),
              Appear(
                index: 3,
                child: Text(
                  'A naptáradat a készülékről olvassuk. Semmi nem kerül '
                  'szerverre.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ),
              const SizedBox(height: 28),
            ],
          ),
        ),
      ),
    );
  }
}
