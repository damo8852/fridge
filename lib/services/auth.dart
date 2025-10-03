import 'dart:io' show Platform;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  AuthService._();
  static final instance = AuthService._();

  final _auth = FirebaseAuth.instance;

  Stream<User?> get onAuthStateChanged => _auth.authStateChanges();

  Future<UserCredential> signInAnonymously() async {
    return _auth.signInAnonymously();
  }

  Future<UserCredential> signInWithGoogle() async {
    if (Platform.isAndroid || Platform.isIOS) {
      // Native Google Sign-In
      final googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) {
        throw Exception('Sign-in aborted');
      }
      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      return _auth.signInWithCredential(credential);
    } else {
      // Desktop/Web fallback: Firebase-only provider (popup/redirect)
      final provider = GoogleAuthProvider();
      return _auth.signInWithProvider(provider);
    }
  }

  Future<UserCredential> signInWithMicrosoft() async {
    // Enable "Microsoft" provider in Firebase Console first.
    final provider = OAuthProvider('microsoft.com');
    // Optionally request scopes:
    provider.addScope('User.Read'); // basic profile
    provider.setCustomParameters({
      'prompt': 'select_account',
    });
    // Works on Android/iOS/macOS (uses native browser) and Web (popup/redirect)
    return _auth.signInWithProvider(provider);
  }

  Future<void> signOut() async {
    // Also disconnect GoogleSignIn if used
    try { await GoogleSignIn().signOut(); } catch (_) {}
    await _auth.signOut();
  }
}
