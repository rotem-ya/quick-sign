import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// InteractiveViewer hard-codes plain mouse-wheel scroll as a zoom gesture
/// (see its `_receivedPointerSignal`) with no way to opt out without also
/// losing pinch-to-zoom — so a document reader built on it feels nothing
/// like a normal page/PDF viewer with a mouse. This intercepts the
/// browser's 'wheel' event in the capture phase, before Flutter's engine
/// turns it into a PointerScrollEvent, and repurposes a plain wheel as a
/// document pan. Ctrl/Cmd+wheel is left to reach InteractiveViewer as
/// usual, so it still zooms — only the browser's own page-zoom-level
/// change is suppressed so it doesn't fire alongside it.
///
/// [shouldIntercept] scopes this to when the document viewer is actually
/// the visible, topmost content — otherwise every other scrollable in the
/// app (Settings, History, sheets, dialogs) would stop scrolling too.
Object attachWheelPan({
  required bool Function() shouldIntercept,
  required void Function(double dx, double dy) onPan,
}) {
  void listener(web.Event event) {
    if (!shouldIntercept()) return;
    final wheel = event as web.WheelEvent;
    if (wheel.ctrlKey || wheel.metaKey) {
      wheel.preventDefault();
      return;
    }
    wheel.preventDefault();
    wheel.stopImmediatePropagation();
    onPan(
      _pixels(wheel.deltaX, wheel.deltaMode),
      _pixels(wheel.deltaY, wheel.deltaMode),
    );
  }

  final jsListener = listener.toJS;
  web.window.addEventListener('wheel', jsListener, true.toJS);
  return jsListener;
}

void detachWheelPan(Object? handle) {
  if (handle == null) return;
  web.window.removeEventListener('wheel', handle as JSFunction, true.toJS);
}

/// Normalizes to approximate CSS pixels — most mice/trackpads already report
/// deltaMode 0 (pixel), but line/page mode devices report tiny deltas that
/// would otherwise feel unresponsive.
double _pixels(double delta, int deltaMode) {
  return switch (deltaMode) {
    1 => delta * 18, // line
    2 => delta * 400, // page
    _ => delta, // pixel
  };
}
