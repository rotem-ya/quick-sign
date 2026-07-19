import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

/// Wraps Firebase Auth (Google + Apple sign-in). Safe to use even before a
/// real Firebase project is configured — [isAvailable] is false until
/// `flutterfire configure` replaces the placeholder in firebase_options.dart
/// and [markAvailable] is called from main(). main() calls it from an
/// unawaited Future, so it can flip true well after the first frame — UI
/// that cares must watch [availableNotifier] rather than read [isAvailable]
/// only once at build time, or it can get stuck showing "not available yet"
/// forever even after Firebase finishes initializing.
class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  bool isAvailable = false;
  final ValueNotifier<bool> availableNotifier = ValueNotifier<bool>(false);
  FirebaseAuth? _auth;
  final GoogleSignIn _googleSignIn = GoogleSignIn();

  /// Rolling log of auth events, newest last — shown directly in Settings
  /// (see SettingsScreen's account section) so sign-in issues can be
  /// diagnosed on a real device without adb/DevTools access.
  final ValueNotifier<List<String>> debugLog = ValueNotifier<List<String>>([]);

  void _log(String line) {
    debugPrint('AuthService: $line');
    final stamp = DateTime.now().toIso8601String().substring(11, 19);
    debugLog.value = [...debugLog.value, '$stamp $line'];
  }

  void markAvailable(FirebaseAuth auth) {
    _auth = auth;
    isAvailable = true;
    availableNotifier.value = true;
    // Diagnostic: Firebase Auth persists sign-in natively, so currentUser
    // should already reflect a previous session right after init — logged
    // to help diagnose reports of sign-in not surviving an app restart.
    _log('available, currentUser=${auth.currentUser?.uid ?? "none"}');
    auth.authStateChanges().listen((user) {
      _log('authStateChanges -> ${user?.uid ?? "signed out"}');
    });
  }

  User? get currentUser => _auth?.currentUser;

  Stream<User?> get authStateChanges =>
      _auth?.authStateChanges() ?? const Stream<User?>.empty();

  // Android 14+ Credential Manager throws ApiException:10 (DEVELOPER_ERROR)
  // if a clientId/serverClientId is passed here — the classic API only
  // validates against the SHA-1 registered in google-services.json, which is
  // always correct. Do not add clientId/serverClientId.
  Future<User?> signInWithGoogle() async {
    final auth = _auth;
    if (auth == null) return null;

    if (kIsWeb) {
      // Firebase's own OAuth popup — needs zero extra configuration beyond
      // enabling Google in the console. The google_sign_in package's web
      // implementation requires a *separate* OAuth "Web client ID" that
      // isn't configured anywhere in this app (Android/iOS get theirs
      // automatically from google-services.json/GoogleService-Info.plist;
      // web has no equivalent file) and its imperative signIn() call has
      // been unreliable on top of Google Identity Services — both are
      // avoided entirely by going through FirebaseAuth directly on web.
      try {
        final userCredential = await auth.signInWithPopup(GoogleAuthProvider());
        return userCredential.user;
      } catch (e) {
        if (_isPigeonCastError(e)) return _recoverFromSignInError();
        rethrow;
      }
    }

    final googleUser = await _googleSignIn.signIn();
    if (googleUser == null) return null; // user dismissed the picker

    try {
      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
        accessToken: googleAuth.accessToken,
      );
      final userCredential = await auth.signInWithCredential(credential);
      return userCredential.user;
    } catch (e) {
      if (_isPigeonCastError(e)) return _recoverFromSignInError();
      rethrow;
    }
  }

  Future<User?> signInWithApple() async {
    final auth = _auth;
    if (auth == null) return null;
    final rawNonce = _generateNonce();
    final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();

    try {
      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: hashedNonce,
      );
      final oauthCredential = OAuthProvider('apple.com').credential(
        idToken: appleCredential.identityToken,
        rawNonce: rawNonce,
        accessToken: appleCredential.authorizationCode,
      );
      final userCredential = await auth.signInWithCredential(oauthCredential);
      return userCredential.user;
    } catch (e) {
      if (_isPigeonCastError(e)) return _recoverFromSignInError();
      rethrow;
    }
  }

  Future<void> signOut() async {
    _log('signOut() called explicitly');
    await _googleSignIn.signOut();
    await _auth?.signOut();
  }

  static String _generateNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._';
    final rnd = math.Random.secure();
    return List.generate(
      length,
      (_) => charset[rnd.nextInt(charset.length)],
    ).join();
  }

  // Known firebase_auth bug: native sign-in can succeed while the Dart side
  // throws a Pigeon codec cast error. Rather than surface a false failure,
  // wait briefly for authStateChanges() to report the real signed-in user.
  static bool _isPigeonCastError(Object e) {
    final s = e.toString();
    return s.contains('PigeonUserDetails') ||
        (s.contains('List<Object?>') && s.contains('is not a subtype'));
  }

  Future<User?> _recoverFromSignInError() async {
    final auth = _auth;
    if (auth == null) return null;
    try {
      return await auth
          .authStateChanges()
          .where((u) => u != null)
          .first
          .timeout(const Duration(seconds: 3));
    } catch (e) {
      _log('recovery failed: $e');
      return null;
    }
  }
}
