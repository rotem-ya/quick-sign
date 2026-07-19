import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import '../models/saved_mark.dart';
import '../models/stamp_design.dart';
import 'auth_service.dart';
import 'marks_service.dart';
import 'settings_service.dart';

/// Mirrors the signature/stamp library + profile name to the signed-in
/// user's Firebase account — Firestore for metadata, Storage for the mark
/// images (Firestore's 1MB document limit doesn't fit many base64 images).
///
/// Never touches the documents being signed — those stay device-only, per
/// the app's core privacy principle. Only what [SettingsService.exportBundle]
/// already covers (the same data the manual "backup to a file" feature
/// exports) gets mirrored, just automatically and to the account instead of
/// a chosen file.
///
/// Every call is best-effort: a Firestore/Storage failure (offline, not yet
/// enabled in the Firebase console, security rules not deployed, etc.) never
/// surfaces to the user or blocks anything — same defensive posture the rest
/// of the Firebase integration has had since before a real project existed.
class CloudSyncService {
  CloudSyncService._();
  static final CloudSyncService instance = CloudSyncService._();

  final MarksService _marksService = MarksService();
  final SettingsService _settingsService = SettingsService();

  VoidCallback? _revisionListener;
  Timer? _debounce;
  bool _started = false;

  /// Call once, after Firebase finishes initializing. Safe to call more than
  /// once — only the first call does anything. Runs for the app's whole
  /// lifetime (this is a singleton), so the auth subscription is never
  /// cancelled on purpose — there's no natural teardown point.
  void start() {
    if (_started) return;
    _started = true;
    debugPrint('CloudSync: started, watching sign-in + mark changes');
    AuthService.instance.authStateChanges.listen((user) {
      debugPrint('CloudSync: authStateChanges -> ${user?.uid ?? "signed out"}');
      if (user != null) unawaited(_onSignedIn(user));
    });
    _revisionListener = () {
      if (AuthService.instance.currentUser == null) return;
      // Debounced: a burst of local edits (e.g. importing a backup) pushes
      // once, not once per mark.
      _debounce?.cancel();
      _debounce = Timer(const Duration(seconds: 2), () => unawaited(_push()));
    };
    MarksService.revision.addListener(_revisionListener!);
  }

  Future<void> _onSignedIn(User user) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      debugPrint('CloudSync: sign-in check ok, cloud doc exists=${doc.exists}');
      // A cloud backup already exists for this account — pull what's not
      // already on this device. Otherwise this is either a brand new
      // account or the first device to ever sign in — push what's here.
      if (doc.exists) {
        await _pull(user.uid);
      } else {
        await _push();
      }
    } catch (e) {
      // Always logged (not just kDebugMode) — this is exactly the kind of
      // failure (rules not deployed, Firestore/Storage not enabled yet)
      // that needs to be visible to diagnose remotely, since it otherwise
      // fails completely silently by design.
      debugPrint('CloudSync: sign-in check failed: $e');
    }
  }

  Future<void> _push() async {
    final user = AuthService.instance.currentUser;
    if (user == null) {
      debugPrint('CloudSync: push skipped, not signed in');
      return;
    }
    try {
      final marks = await _marksService.list();
      final name = await _settingsService.getName();
      final defaults = <String, String>{};
      for (final type in MarkType.values) {
        final id = (await _marksService.getDefault(type))?.id;
        if (id != null) defaults[type.name] = id;
      }

      final userDoc = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid);
      await userDoc.set({
        'name': name,
        'defaults': defaults,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      final marksCollection = userDoc.collection('marks');
      final storage = FirebaseStorage.instance;
      for (final mark in marks) {
        await marksCollection.doc(mark.id).set({
          'type': mark.type.name,
          'name': mark.name,
          'design': mark.design?.toJson(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        await storage
            .ref('users/${user.uid}/marks/${mark.id}.png')
            .putData(mark.imageBytes);
      }
      debugPrint('CloudSync: pushed ${marks.length} mark(s) + profile');
    } catch (e) {
      debugPrint('CloudSync: push failed: $e');
    }
  }

  Future<void> _pull(String uid) async {
    try {
      final firestore = FirebaseFirestore.instance;
      final userDoc = await firestore.collection('users').doc(uid).get();
      final data = userDoc.data();
      if (data == null) return;

      // Never overwrite a name/default already set locally — cloud data
      // only fills in gaps, it doesn't clobber what's already on this
      // device.
      final localName = await _settingsService.getName();
      final cloudName = data['name'] as String?;
      if (localName == null && cloudName != null && cloudName.isNotEmpty) {
        await _settingsService.setName(cloudName);
      }

      final localMarks = await _marksService.list();
      final localIds = localMarks.map((m) => m.id).toSet();

      final marksSnapshot = await firestore
          .collection('users')
          .doc(uid)
          .collection('marks')
          .get();
      debugPrint(
        'CloudSync: pull found ${marksSnapshot.docs.length} cloud mark(s), '
        '${localIds.length} already local',
      );
      final storage = FirebaseStorage.instance;
      var restored = 0;
      for (final doc in marksSnapshot.docs) {
        if (localIds.contains(doc.id)) continue; // already on this device
        try {
          final markData = doc.data();
          final type = MarkType.values.byName(markData['type'] as String);
          final designJson = markData['design'] as Map<String, dynamic>?;
          final imageBytes = await storage
              .ref('users/$uid/marks/${doc.id}.png')
              .getData();
          if (imageBytes == null) continue;
          await _marksService.restore(
            SavedMark(
              id: doc.id,
              type: type,
              name: markData['name'] as String? ?? '',
              imageBytes: imageBytes,
              design: designJson == null
                  ? null
                  : StampDesign.fromJson(designJson),
            ),
          );
          restored++;
        } catch (e) {
          // One malformed cloud mark shouldn't stop the rest from restoring.
          debugPrint('CloudSync: skipping cloud mark ${doc.id}: $e');
        }
      }
      debugPrint('CloudSync: pull restored $restored mark(s)');

      final cloudDefaults =
          (data['defaults'] as Map<String, dynamic>?) ?? const {};
      for (final entry in cloudDefaults.entries) {
        try {
          final type = MarkType.values.byName(entry.key);
          if (await _marksService.getDefault(type) == null) {
            await _marksService.setDefault(type, entry.value as String);
          }
        } catch (e) {
          debugPrint('CloudSync: skipping cloud default $entry: $e');
        }
      }
    } catch (e) {
      debugPrint('CloudSync: pull failed: $e');
    }
  }
}
