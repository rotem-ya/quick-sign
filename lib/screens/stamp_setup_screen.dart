import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../l10n/strings.dart';
import '../services/stamp_service.dart';

/// One-time stamp setup: photograph the stamp (or pick from gallery), the
/// white background is removed automatically, preview, save.
///
/// Pops with the processed PNG bytes when the user confirms.
class StampSetupScreen extends StatefulWidget {
  const StampSetupScreen({super.key});

  @override
  State<StampSetupScreen> createState() => _StampSetupScreenState();
}

class _StampSetupScreenState extends State<StampSetupScreen> {
  final StampService _service = StampService();
  Uint8List? _processed;
  bool _busy = false;

  Future<void> _capture({required bool fromCamera}) async {
    setState(() => _busy = true);
    try {
      final raw = await _service.captureImage(fromCamera: fromCamera);
      if (raw == null) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      final processed =
          await compute(StampService.removeWhiteBackground, raw);
      if (!mounted) return;
      setState(() {
        _processed = processed;
        _busy = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.of(context)['importError'])),
      );
    }
  }

  Future<void> _confirm() async {
    final bytes = _processed;
    if (bytes == null) return;
    setState(() => _busy = true);
    await _service.saveStamp(bytes);
    if (!mounted) return;
    Navigator.of(context).pop(bytes);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(s['stampSetupTitle'])),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  child: _busy
                      ? const Center(child: CircularProgressIndicator())
                      : _processed == null
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  s['stampHint'],
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 17,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            )
                          : Padding(
                              padding: const EdgeInsets.all(16),
                              child:
                                  Image.memory(_processed!, fit: BoxFit.contain),
                            ),
                ),
              ),
              const SizedBox(height: 16),
              if (_processed == null)
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy
                            ? null
                            : () => _capture(fromCamera: false),
                        icon: const Icon(Icons.photo_library_outlined),
                        label: Text(s['fromGallery']),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(48, 56),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        onPressed:
                            _busy ? null : () => _capture(fromCamera: true),
                        icon: const Icon(Icons.photo_camera_outlined),
                        label: Text(s['captureStamp']),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(48, 56),
                        ),
                      ),
                    ),
                  ],
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy
                            ? null
                            : () => setState(() => _processed = null),
                        icon: const Icon(Icons.replay),
                        label: Text(s['retake']),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(48, 56),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: FilledButton.icon(
                        onPressed: _busy ? null : _confirm,
                        icon: const Icon(Icons.check),
                        label: Text(s['useStamp']),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(48, 56),
                        ),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
