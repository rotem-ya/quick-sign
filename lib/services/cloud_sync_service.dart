import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../models/saved_mark.dart';
import '../models/stamp_design.dart';
import 'auth_service.dart';
import 'marks_service.dart';
import 'settings_service.dart';

/// Syncs the user's signature/stamp library + profile to their Firestore
/// account, so signing in on a new device or after a reinstall restores
/// everything automatically. Works identically for Google, Apple, and web.
///
/// Each mark's image is stored as a [Blob] inside its own Firestore document
/// (a signature/stamp is tens of KB, well under the 1 MB per-document limit) —
/// no Firebase Storage / Blaze needed. The image field is exempt from indexing
/// (see firestore.indexes.json): Firestore refuses to index a value over
/// 1,500 bytes, so without the exemption the write would fail.
///
/// The documents being signed are NEVER stored — only the reusable
/// signatures/stamps + settings, exactly what the manual folder backup covers.
///
/// Best-effort: any failure is caught and never blocks the app. The on-demand
/// "Sync now" button in Settings surfaces the exact result.
class CloudSyncService {
  CloudSyncService._();
  static final CloudSyncService instance = CloudSyncService._();

  final MarksService _marksService = MarksService();
  final SettingsService _settingsService = SettingsService();

  VoidCallback? _revisionListener;
  Timer? _debounce;
  bool _started = false;

  /// Leave headroom under the 1 MB document limit for the other fields — a
  /// pathologically large image is skipped rather than failing the sync.
  static const int _maxImageBytes = 900 * 1024;

  void _log(String line) => AuthService.instance.log(line);

  /// Call once, after Firebase initializes. Safe to call repeatedly.
  void start() {
    if (_started) return;
    _started = true;
    _log('CloudSync: started');
    AuthService.instance.authStateChanges.listen((user) {
      _log('CloudSync: authStateChanges -> ${user?.uid ?? "signed out"}');
      if (user != null) unawaited(_onSignedIn(user));
    });
    // MarksService bumps this on any mark change; SettingsService.setName does
    // too — one "something personal changed" signal, debounced into one push.
    _revisionListener = () {
      if (AuthService.instance.currentUser == null) return;
      _debounce?.cancel();
      _debounce = Timer(const Duration(seconds: 2), () => unawaited(_push()));
    };
    MarksService.revision.addListener(_revisionListener!);
  }

  DocumentReference<Map<String, dynamic>> _userDoc(String uid) =>
      FirebaseFirestore.instance.collection('users').doc(uid);

  Future<void> _onSignedIn(User user) async {
    try {
      final exists = (await _userDoc(user.uid).get()).exists;
      _log('CloudSync: signed in, cloud doc exists=$exists');
      // Two-way union merge: pull what the account has that this device lacks,
      // then push, so marks made on this device are backed up too.
      if (exists) await _pull(user.uid);
      await _push();
    } catch (e) {
      _log('CloudSync: sign-in sync failed: $e');
    }
  }

  Future<void> _push() async {
    final user = AuthService.instance.currentUser;
    if (user == null) return;
    try {
      final n = await _pushFor(user);
      _log('CloudSync: pushed $n mark(s) + profile');
    } catch (e) {
      _log('CloudSync: push failed: $e');
    }
  }

  /// Writes profile + every local mark to Firestore. Throws on failure so
  /// [syncNow] can surface it. Returns the number of marks written.
  Future<int> _pushFor(User user) async {
    final marks = await _marksService.list();
    final name = await _settingsService.getName();
    final defaults = <String, String>{};
    for (final type in MarkType.values) {
      final id = (await _marksService.getDefault(type))?.id;
      if (id != null) defaults[type.name] = id;
    }

    final userDoc = _userDoc(user.uid);
    await userDoc.set({
      'name': name,
      'defaults': defaults,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));

    final marksCol = userDoc.collection('marks');
    var pushed = 0;
    for (final mark in marks) {
      if (mark.imageBytes.length > _maxImageBytes) {
        _log('CloudSync: skipping oversized mark ${mark.id} '
            '(${mark.imageBytes.length}B)');
        continue;
      }
      await marksCol.doc(mark.id).set({
        'type': mark.type.name,
        'name': mark.name,
        'design': mark.design?.toJson(),
        'image': Blob(mark.imageBytes),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      pushed++;
    }
    return pushed;
  }

  /// Restores cloud marks/profile not already on this device. Returns the
  /// number of marks restored.
  Future<int> _pull(String uid) async {
    final userSnap = await _userDoc(uid).get();
    final data = userSnap.data();
    if (data == null) return 0;

    // Fill a locally-empty name from the cloud; never clobber a local one.
    final localName = await _settingsService.getName();
    final cloudName = data['name'] as String?;
    if (localName == null && cloudName != null && cloudName.isNotEmpty) {
      await _settingsService.setName(cloudName);
    }

    final localIds = (await _marksService.list()).map((m) => m.id).toSet();
    final marksSnap = await _userDoc(uid).collection('marks').get();
    _log('CloudSync: pull found ${marksSnap.docs.length} cloud mark(s)');
    var restored = 0;
    for (final doc in marksSnap.docs) {
      if (localIds.contains(doc.id)) continue; // already on this device
      try {
        final m = doc.data();
        final blob = m['image'];
        if (blob is! Blob) continue;
        final designJson = m['design'] as Map<String, dynamic>?;
        await _marksService.restore(SavedMark(
          id: doc.id,
          type: MarkType.values.byName(m['type'] as String),
          name: m['name'] as String? ?? '',
          imageBytes: blob.bytes,
          design:
              designJson == null ? null : StampDesign.fromJson(designJson),
        ));
        restored++;
      } catch (e) {
        _log('CloudSync: skipping cloud mark ${doc.id}: $e');
      }
    }
    _log('CloudSync: restored $restored mark(s)');

    final cloudDefaults =
        (data['defaults'] as Map<String, dynamic>?) ?? const {};
    for (final entry in cloudDefaults.entries) {
      try {
        final type = MarkType.values.byName(entry.key);
        if (await _marksService.getDefault(type) == null) {
          await _marksService.setDefault(type, entry.value as String);
        }
      } catch (_) {
        // Unknown type from a newer/older build — skip.
      }
    }
    return restored;
  }

  /// User-triggered sync (the "Sync now" button). Pulls then pushes, and
  /// returns a human-readable result — success count or the exact error.
  Future<({bool ok, String message})> syncNow() async {
    final user = AuthService.instance.currentUser;
    if (user == null) return (ok: false, message: 'לא מחובר לחשבון.');
    try {
      var restored = 0;
      if ((await _userDoc(user.uid).get()).exists) {
        restored = await _pull(user.uid);
      }
      final pushed = await _pushFor(user);
      _log('CloudSync: manual sync ok (restored $restored, pushed $pushed)');
      final restoredPart =
          restored > 0 ? 'שוחזרו $restored מהחשבון · ' : '';
      return (
        ok: true,
        message: '$restoredPart$pushed חתימות/חותמות נשמרו לחשבון.',
      );
    } catch (e) {
      _log('CloudSync: manual sync failed: $e');
      return (ok: false, message: '$e');
    }
  }
}
