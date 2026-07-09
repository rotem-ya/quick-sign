import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Anchored adaptive banner ad pinned above the toolbar.
///
/// Uses Google's official TEST ad units — replace with production unit IDs
/// (and the app IDs in AndroidManifest.xml / Info.plist) before release.
class AdBanner extends StatefulWidget {
  const AdBanner({super.key});

  // TODO: replace with production banner ad unit IDs before release.
  static const String _androidAdUnitId =
      'ca-app-pub-3940256099942544/6300978111';
  static const String _iosAdUnitId = 'ca-app-pub-3940256099942544/2934735716';

  static bool get supported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  @override
  State<AdBanner> createState() => _AdBannerState();
}

class _AdBannerState extends State<AdBanner> {
  BannerAd? _ad;
  bool _loaded = false;
  double? _loadedForWidth;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!AdBanner.supported) return;
    final width = MediaQuery.sizeOf(context).width;
    if (_loadedForWidth != width) {
      _loadedForWidth = width;
      _loadAd(width);
    }
  }

  Future<void> _loadAd(double width) async {
    _ad?.dispose();
    _ad = null;
    _loaded = false;

    final size =
        await AdSize.getCurrentOrientationAnchoredAdaptiveBannerAdSize(
      width.truncate(),
    );
    if (!mounted || size == null) return;

    final ad = BannerAd(
      adUnitId: Platform.isAndroid
          ? AdBanner._androidAdUnitId
          : AdBanner._iosAdUnitId,
      size: size,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (ad) {
          if (!mounted) {
            ad.dispose();
            return;
          }
          setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          ad.dispose();
          if (mounted && _ad == ad) {
            setState(() {
              _ad = null;
              _loaded = false;
            });
          }
        },
      ),
    );
    _ad = ad;
    await ad.load();
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _ad;
    if (!_loaded || ad == null) return const SizedBox.shrink();
    return SizedBox(
      width: ad.size.width.toDouble(),
      height: ad.size.height.toDouble(),
      child: AdWidget(ad: ad),
    );
  }
}
