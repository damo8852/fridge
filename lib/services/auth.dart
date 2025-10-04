import 'dart:io' show Platform;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

class AuthService {
  AuthService._();
  static final instance = AuthService._();

  final _auth = FirebaseAuth.instance;

  Stream<User?> get onAuthStateChanged => _auth.authStateChanges();
  User? get currentUser => _auth.currentUser;

  Future<UserCredential> signInAnonymously() async {
    try {
      return await _auth.signInAnonymously();
    } catch (e) {
      throw Exception('Anonymous sign-in failed: $e');
    }
  }

  Future<UserCredential> signInWithGoogle() async {
    try {
      if (Platform.isAndroid || Platform.isIOS) {
        final googleUser = await GoogleSignIn().signIn();
        if (googleUser == null) {
          throw Exception('Google sign-in aborted by user.');
        }

        final googleAuth = await googleUser.authentication;

        if (googleAuth.accessToken == null || googleAuth.idToken == null) {
          throw Exception('Missing Google authentication tokens.');
        }

        final credential = GoogleAuthProvider.credential(
          accessToken: googleAuth.accessToken,
          idToken: googleAuth.idToken,
        );

        return await _auth.signInWithCredential(credential);
      } else {
        final provider = GoogleAuthProvider();
        return await _auth.signInWithProvider(provider);
      }
    } catch (e) {
      throw Exception('Google sign-in failed: $e');
    }
  }

  Future<UserCredential> signInWithMicrosoft() async {
    try {
      final provider = OAuthProvider('microsoft.com');
      provider.addScope('User.Read');
      provider.setCustomParameters({
        'prompt': 'select_account',
      });

      return await _auth.signInWithProvider(provider);
    } catch (e) {
      throw Exception('Microsoft sign-in failed: $e');
    }
  }

  Future<void> reauthenticateWithGoogle() async {
    final googleUser = await GoogleSignIn().signIn();
    if (googleUser == null) throw Exception('Reauth aborted');

    final googleAuth = await googleUser.authentication;

    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    await _auth.currentUser?.reauthenticateWithCredential(credential);
  }

  Future<void> linkWithGoogle() async {
    final googleUser = await GoogleSignIn().signIn();
    final googleAuth = await googleUser?.authentication;
    
    if (googleAuth == null) throw Exception("Google auth failed");

    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );

    await _auth.currentUser?.linkWithCredential(credential);
  }

  Future<void> signOut() async {
    try {
      final user = _auth.currentUser;
      final isGoogleSignIn = user?.providerData.any((info) => info.providerId == 'google.com') ?? false;

      if (isGoogleSignIn) {
        try {
          await GoogleSignIn().signOut();
        } catch (_) {
          // Ignore Google sign-out error
        }
      }

      await _auth.signOut();
    } catch (e) {
      throw Exception('Sign-out failed: $e');
    }
  }

  Future<void> deleteAccount() async {
    await _auth.currentUser?.delete();
  }
}