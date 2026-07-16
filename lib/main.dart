import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'app.dart';
import 'firebase_options.dart';
import 'services/auth_service.dart';
import 'widgets/ad_banner.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (AdBanner.supported) {
    // Fire-and-forget: the app must never wait on the ads SDK.
    unawaited(MobileAds.instance.initialize());
  }
  // firebase_options.dart is a placeholder until `flutterfire configure`
  // runs against a real project — this must never crash startup.
  unawaited(
    Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)
        .then((app) => AuthService.instance.markAvailable(FirebaseAuth.instance))
        .catchError((Object e) {
      if (kDebugMode) debugPrint('Firebase not configured yet: $e');
    }),
  );
  runApp(const QuickSignApp());
}
