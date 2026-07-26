import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

/// A UI-nak ennyi kell a bejelentkezett felhasználóból. Így sem a router, sem a
/// képernyők nem függenek a Firebase típusaitól — és tesztben felülírható.
class AuthUser {
  const AuthUser(this.name, {this.email});
  final String name;

  /// A bejelentkezett Google-fiók e-mail címe. Ez köti össze a fiókot az eszköz
  /// naptáraival (lásd `defaultVisible`) — a naptárak fiókneve ugyanez a cím.
  final String? email;
}

final _firebaseUserProvider = StreamProvider<User?>(
  (ref) => FirebaseAuth.instance.authStateChanges(),
);

/// Az app auth állapota. `loading`, amíg a Firebase visszatölti a lemezre
/// mentett munkamenetet — ilyenkor még nem szabad a login képernyőre dobni.
final currentUserProvider = Provider<AsyncValue<AuthUser?>>((ref) {
  return ref
      .watch(_firebaseUserProvider)
      .whenData(
        (user) => user == null
            ? null
            : AuthUser(
                user.displayName ?? user.email ?? 'Felhasználó',
                email: user.email,
              ),
      );
});

/// Google bejelentkezés, majd a kapott idToken beváltása Firebase munkamenetre.
Future<void> signInWithGoogle() async {
  final account = await GoogleSignIn.instance.authenticate();
  final idToken = account.authentication.idToken;
  if (idToken == null) {
    throw StateError('A Google nem adott vissza idToken-t.');
  }
  await FirebaseAuth.instance.signInWithCredential(
    GoogleAuthProvider.credential(idToken: idToken),
  );
}

Future<void> signOut() async {
  await GoogleSignIn.instance.signOut();
  await FirebaseAuth.instance.signOut();
}
