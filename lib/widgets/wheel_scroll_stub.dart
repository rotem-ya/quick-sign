/// Non-web platforms never call this — touch drag/pinch is native there,
/// and InteractiveViewer's mouse-wheel-only quirk doesn't apply.
Object attachWheelPan({
  required bool Function() shouldIntercept,
  required void Function(double dx, double dy) onPan,
}) =>
    Object();

void detachWheelPan(Object? handle) {}
