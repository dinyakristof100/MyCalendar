import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Bejelentkezett felhasználó. Egyelőre csak a név; a 3b lépésben Firebase
/// User-ből töltjük (uid, email, fotó).
class AuthUser {
  const AuthUser(this.name);
  final String name;
}

/// Az auth "seam": a UI mindig ezt a signIn/signOut felületet hívja.
class AuthController extends Notifier<AuthUser?> {
  @override
  AuthUser? build() => null; // induláskor kijelentkezve

  // ponytail: stub sign-in a 3b Firebase-bekötésig — a törzset cseréljük
  //           google_sign_in + FirebaseAuth-ra, a signIn/signOut felület marad.
  Future<void> signIn() async => state = const AuthUser('Teszt Felhasználó');

  Future<void> signOut() async => state = null;
}

final authControllerProvider =
    NotifierProvider<AuthController, AuthUser?>(AuthController.new);
