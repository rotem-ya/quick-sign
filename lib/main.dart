import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'app.dart';
import 'widgets/ad_banner.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  if (AdBanner.supported) {
    // Fire-and-forget: the app must never wait on the ads SDK.
    unawaited(MobileAds.instance.initialize());
  }
  runApp(const QuickSignApp());
}
