import 'dart:math' as math;

import 'package:flutter/material.dart' show Matrix4;

/// The 2D (X/Y) scale factor of an affine transform matrix.
///
/// [Matrix4.getMaxScaleOnAxis] takes the max over X, Y, *and* Z — for the
/// pure 2D pan/zoom matrices used by the document viewer (Z is always left
/// at scale 1), that means it silently floors at 1.0 for any real zoom
/// level below 1: the fixed Z-axis scale wins the max. This only looks at
/// the X axis, which for these uniform, unrotated 2D matrices always
/// matches Y.
extension Matrix4Scale on Matrix4 {
  double get scale2D {
    final x = this[0], y = this[1], z = this[2];
    return math.sqrt(x * x + y * y + z * z);
  }
}
