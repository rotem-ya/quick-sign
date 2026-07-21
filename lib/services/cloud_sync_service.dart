import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'auth_service.dart';
import 'marks_service.dart';
import 'settings_service.dart';

/// Syncs only **lightweight account data** — the user's profile/settings — to
/// the signed-in user's Firestore document.
///
/// By design it does NOT store signatures, stamps, or documents. Those are the
/// user's own content and belong in the user's own storage — their Google
/// Drive / OneDrive / chosen folder (via the folder backup in Settings), never
/// in our Firebase. This keeps the cloud footprint tiny (Firestore free tier,
/// **no Firebase Storage / Blaze needed**) and matches the app's privacy
/// principle: the heavy, personal content stays with the user.
///
/// Best-effort: any Firestore failure (offline, not enabled yet, rules not
/// deployed) is caught and never blocks anything. The on-demand "Sync now"
/// button in Settings surfaces the exact result when the user asks.
class CloudSyncService {
  CloudSyncService._();
  static final CloudSyncService instance = CloudSyncService._();

  final SettingsService _settingsService = SettingsService();

  VoidCallback? _revisionListener;
  Timer? _debounce;
  bool _started = false;

  /// Logs to console + the on-device diagnostics the "Sync now" flow shares,
  /// so a failing sync is visible without adb.
  void _log(String line) => AuthService.instance.log(line);

  /// Call once, after Firebase initializes. Safe to call repeatedly.
  void start() {
    if (_started) return;
    _started = true;
    _log('CloudSync: started, watching sign-in + settings changes');
    AuthService.instance.authStateChanges.listen((user) {
      _log('CloudSync: authStateChanges -> ${user?.uid ?? "signed out"}');
      if (user != null) unawaited(_onSignedIn(user));
    });
    // Reuses MarksService's "something personal changed" signal — Settings
    // .setName bumps it too — to re-push the (tiny) profile, debounced.
    _revisionListener = () {
      if (AuthService.instance.currentUser == null) return;
      _debounce?.cancel();
      _debounce = Timer(const Duration(seconds: 2), () => unawaited(_push()));
    };
    MarksService.revision.addListener(_revisionListener!);
  }

  Future<void> _onSignedIn(User user) async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      _log('CloudSync: sign-in check ok, cloud doc exists=${snapshot.exists}');
      // Fill a locally-empty name from the cloud (never clobber a local one),
      // then push so a name set on this device reaches the account.
      final cloudName = snapshot.data()?['name'] as String?;
      final localName = await _settingsService.getName();
      if (localName == null && cloudName != null && cloudName.isNotEmpty) {
        await _settingsService.setName(cloudName);
      }
      await _push();
    } catch (e) {
      _log('CloudSync: sign-in check failed: $e');
    }
  }

  Future<void> _push() async {
    final user = AuthService.instance.currentUser;
    if (user == null) {
      _log('CloudSync: push skipped, not signed in');
      return;
    }
    try {
      await _pushFor(user);
      _log('CloudSync: profile pushed');
    } catch (e) {
      _log('CloudSync: push failed: $e');
    }
  }

  /// Writes the lightweight profile to Firestore. Throws on failure so
  /// [syncNow] can surface the exact error. `merge: true` never disturbs any
  /// other field on the user document.
  Future<void> _pushFor(User user) async {
    final name = await _settingsService.getName();
    await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
      'name': name,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// User-triggered sync (the "Sync now" button). Returns a human-readable
  /// result — success, or the exact Firestore error — for the Settings dialog.
  Future<({bool ok, String message})> syncNow() async {
    final user = AuthService.instance.currentUser;
    if (user == null) {
      return (ok: false, message: 'לא מחובר לחשבון.');
    }
    try {
      await _pushFor(user);
      _log('CloudSync: manual sync ok');
      return (ok: true, message: 'ההגדרות סונכרנו לחשבון.');
    } catch (e) {
      _log('CloudSync: manual sync failed: $e');
      return (ok: false, message: '$e');
    }
  }
}
