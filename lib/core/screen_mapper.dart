/// ===========================================================================
/// GazeNav - Screen Mapper v3
/// ===========================================================================
///
/// v1/v2 problem: sensitivityX=2.8 was WAY too low. The gaze signal from
/// ML Kit is tiny (±0.02 to ±0.1), so we need massive amplification.
///
/// v3 approach:
///   - Base sensitivity of 6-8x (applied AFTER GazeEngine's auto-gain)
///   - Minimal dead zone (0.01)
///   - Power curve instead of sigmoid for better edge reach
///   - The GazeEngine already does baseline subtraction and auto-ranging,
///     so the mapper can use simpler, more predictable transforms
///
/// ===========================================================================

import 'dart:math' as math;
import 'dart:ui';
import '../models/gaze_data.dart';

class ScreenMapper {
  CalibrationProfile? _profile;
  Size _screenSize = Size.zero;

  bool get isCalibrated => _profile != null && _profile!.isValid;
  void setScreenSize(Size s) => _screenSize = s;

  /// ═══════════════════════════════════════════════════════════════════
  /// CALIBRATED mapping
  /// ═══════════════════════════════════════════════════════════════════
  CalibrationProfile calibrate(List<CalibrationPoint> points) {
    if (points.length < 3) throw Exception('Need ≥3 calibration points');

    final p = CalibrationProfile(points: points);

    _solve(points, (c) => c.screenPosition.dx, (v) {
      p.ax = v[0]; p.bx = v[1]; p.cx = v[2];
    });
    _solve(points, (c) => c.screenPosition.dy, (v) {
      p.ay = v[0]; p.by = v[1]; p.cy = v[2];
    });

    _profile = p;
    return p;
  }

  void loadProfile(CalibrationProfile p) => _profile = p;

  Offset? mapToScreen(Offset gaze) {
    if (!isCalibrated || _screenSize == Size.zero) return null;
    final p = _profile!;
    return Offset(
      (p.ax * gaze.dx + p.bx * gaze.dy + p.cx).clamp(0.0, _screenSize.width),
      (p.ay * gaze.dx + p.by * gaze.dy + p.cy).clamp(0.0, _screenSize.height),
    );
  }

  /// ═══════════════════════════════════════════════════════════════════
  /// UNCALIBRATED mapping v3
  /// ═══════════════════════════════════════════════════════════════════
  ///
  /// The GazeEngine v3 already does:
  ///   - Baseline subtraction (center = 0,0)
  ///   - Auto-gain (maps observed range toward ±1)
  ///   - Head pose fusion
  ///   - EMA smoothing
  ///
  /// So the gaze values arriving here are roughly in [-1, 1] range
  /// (after auto-gain warms up). We just need to:
  ///   1. Apply additional sensitivity boost
  ///   2. Map [-1, 1] → screen coordinates
  ///   3. Mirror horizontal (front camera)
  ///
  Offset mapToScreenUncalibrated(Offset gaze) {
    if (_screenSize == Size.zero) return Offset.zero;

    // ── Additional sensitivity multiplier ──
    // The auto-gain in GazeEngine targets ±1 range,
    // but early on (before range is learned) values are smaller
    const boostX = 6.0;
    const boostY = 7.0;

    double gx = gaze.dx * boostX;
    double gy = gaze.dy * boostY;

    // ── Tiny dead zone (just for micro-jitter) ──
    gx = _deadZone(gx, 0.01);
    gy = _deadZone(gy, 0.01);

    // ── Power curve: amplify small movements, compress large ──
    // This makes the cursor more responsive to small eye shifts
    // while preventing it from flying off screen with larger movements
    gx = _powerMap(gx, 0.7); // exponent < 1 amplifies small values
    gy = _powerMap(gy, 0.7);

    // ── Clamp to [-1, 1] ──
    gx = gx.clamp(-1.0, 1.0);
    gy = gy.clamp(-1.0, 1.0);

    // ── Map to screen (mirrored horizontal for front camera) ──
    final sx = _screenSize.width / 2.0 - gx * _screenSize.width / 2.0;
    final sy = _screenSize.height / 2.0 + gy * _screenSize.height / 2.0;

    return Offset(
      sx.clamp(0.0, _screenSize.width),
      sy.clamp(0.0, _screenSize.height),
    );
  }

  /// Dead zone
  double _deadZone(double v, double zone) {
    if (v.abs() < zone) return 0.0;
    return v.sign * (v.abs() - zone) / (1.0 - zone);
  }

  /// Signed power mapping: preserves sign, applies power to magnitude
  /// exponent < 1 → amplifies small movements (what we want)
  /// exponent > 1 → dampens small movements
  double _powerMap(double x, double exponent) {
    return x.sign * math.pow(x.abs(), exponent);
  }

  /// ═══════════════════════════════════════════════════════════════════
  /// Least-squares solver
  /// ═══════════════════════════════════════════════════════════════════
  void _solve(
      List<CalibrationPoint> pts,
      double Function(CalibrationPoint) target,
      void Function(List<double>) out,
      ) {
    double a00 = 0, a01 = 0, a02 = 0;
    double a11 = 0, a12 = 0, a22 = 0;
    double b0 = 0, b1 = 0, b2 = 0;

    for (final p in pts) {
      final x = p.gazeDirection.dx, y = p.gazeDirection.dy, t = target(p);
      a00 += x * x; a01 += x * y; a02 += x;
      a11 += y * y; a12 += y; a22 += 1;
      b0 += x * t; b1 += y * t; b2 += t;
    }

    final det = a00 * (a11 * a22 - a12 * a12)
        - a01 * (a01 * a22 - a12 * a02)
        + a02 * (a01 * a12 - a11 * a02);

    if (det.abs() < 1e-10) {
      out([_screenSize.width, 0, _screenSize.width / 2]);
      return;
    }

    out([
      (b0 * (a11 * a22 - a12 * a12) - a01 * (b1 * a22 - a12 * b2) + a02 * (b1 * a12 - a11 * b2)) / det,
      (a00 * (b1 * a22 - a12 * b2) - b0 * (a01 * a22 - a12 * a02) + a02 * (a01 * b2 - b1 * a02)) / det,
      (a00 * (a11 * b2 - b1 * a12) - a01 * (a01 * b2 - b1 * a02) + b0 * (a01 * a12 - a11 * a02)) / det,
    ]);
  }

  void clearCalibration() => _profile = null;
}