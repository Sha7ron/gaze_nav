/// ===========================================================================
/// GazeNav - Screen Mapper
/// ===========================================================================
/// Maps raw gaze direction vectors to screen pixel coordinates using
/// calibration data. Uses affine transformation (least-squares fit)
/// computed from calibration points.
///
/// The mapping is:
///   screen_x = ax * gaze_x + bx * gaze_y + cx
///   screen_y = ay * gaze_x + by * gaze_y + cy
///
/// Where (ax, bx, cx, ay, by, cy) are computed during calibration.
/// ===========================================================================

import 'dart:ui';
import '../models/gaze_data.dart';

class ScreenMapper {
  CalibrationProfile? _profile;
  Size _screenSize = Size.zero;

  /// Whether calibration has been performed
  bool get isCalibrated => _profile != null && _profile!.isValid;

  /// Set screen dimensions for mapping
  void setScreenSize(Size size) {
    _screenSize = size;
  }

  /// ─────────────────────────────────────────────────────────────────────
  /// Compute calibration from collected points
  /// ─────────────────────────────────────────────────────────────────────
  ///
  /// Uses least-squares to fit an affine mapping from gaze direction
  /// to screen coordinates. This requires at least 3 points for a
  /// unique solution, but 9 points (standard calibration) gives
  /// a much better fit.
  ///
  /// The math:
  ///   For N calibration points, solve:
  ///   [gx1  gy1  1] [ax]   [sx1]
  ///   [gx2  gy2  1] [bx] = [sx2]
  ///   [...  ...  .] [cx]   [...]
  ///
  ///   Using normal equations: (A^T A) x = A^T b
  ///
  CalibrationProfile calibrate(List<CalibrationPoint> points) {
    if (points.length < 3) {
      throw Exception('Need at least 3 calibration points');
    }

    final profile = CalibrationProfile(points: points);

    // Build matrices for least-squares
    final n = points.length;

    // Solve for X mapping
    _solveLeastSquares(
      points,
      (p) => p.gazeDirection.dx,
      (p) => p.gazeDirection.dy,
      (p) => p.screenPosition.dx,
      (coeffs) {
        profile.ax = coeffs[0];
        profile.bx = coeffs[1];
        profile.cx = coeffs[2];
      },
    );

    // Solve for Y mapping
    _solveLeastSquares(
      points,
      (p) => p.gazeDirection.dx,
      (p) => p.gazeDirection.dy,
      (p) => p.screenPosition.dy,
      (coeffs) {
        profile.ay = coeffs[0];
        profile.by = coeffs[1];
        profile.cy = coeffs[2];
      },
    );

    _profile = profile;
    return profile;
  }

  /// Load a previously saved calibration profile
  void loadProfile(CalibrationProfile profile) {
    _profile = profile;
  }

  /// ─────────────────────────────────────────────────────────────────────
  /// Map a raw gaze direction to screen coordinates
  /// ─────────────────────────────────────────────────────────────────────
  Offset? mapToScreen(Offset gazeDirection) {
    if (!isCalibrated || _screenSize == Size.zero) return null;

    final p = _profile!;
    final gx = gazeDirection.dx;
    final gy = gazeDirection.dy;

    double sx = p.ax * gx + p.bx * gy + p.cx;
    double sy = p.ay * gx + p.by * gy + p.cy;

    // Clamp to screen bounds
    sx = sx.clamp(0.0, _screenSize.width);
    sy = sy.clamp(0.0, _screenSize.height);

    return Offset(sx, sy);
  }

  /// ─────────────────────────────────────────────────────────────────────
  /// Quick mapping without calibration (for testing / pre-calibration)
  /// Maps gaze direction directly to screen using simple linear scaling
  /// ─────────────────────────────────────────────────────────────────────
  Offset mapToScreenUncalibrated(Offset gazeDirection) {
    if (_screenSize == Size.zero) return Offset.zero;

    // Map gaze range [-1, 1] to screen [0, width/height]
    // Note: horizontal is mirrored because camera is mirrored
    final sx = _screenSize.width / 2.0 - gazeDirection.dx * _screenSize.width;
    final sy = _screenSize.height / 2.0 + gazeDirection.dy * _screenSize.height;

    return Offset(
      sx.clamp(0.0, _screenSize.width),
      sy.clamp(0.0, _screenSize.height),
    );
  }

  /// ─────────────────────────────────────────────────────────────────────
  /// Solve least-squares for affine mapping
  /// ─────────────────────────────────────────────────────────────────────
  void _solveLeastSquares(
    List<CalibrationPoint> points,
    double Function(CalibrationPoint) getX,
    double Function(CalibrationPoint) getY,
    double Function(CalibrationPoint) getTarget,
    void Function(List<double>) setCoeffs,
  ) {
    // Build A^T*A and A^T*b for normal equations
    // A = [x, y, 1] for each point
    double ata00 = 0, ata01 = 0, ata02 = 0;
    double ata11 = 0, ata12 = 0;
    double ata22 = 0;
    double atb0 = 0, atb1 = 0, atb2 = 0;

    for (final p in points) {
      final x = getX(p);
      final y = getY(p);
      final t = getTarget(p);

      ata00 += x * x;
      ata01 += x * y;
      ata02 += x;
      ata11 += y * y;
      ata12 += y;
      ata22 += 1.0;

      atb0 += x * t;
      atb1 += y * t;
      atb2 += t;
    }

    // Solve 3x3 system using Cramer's rule
    // [ata00 ata01 ata02] [a]   [atb0]
    // [ata01 ata11 ata12] [b] = [atb1]
    // [ata02 ata12 ata22] [c]   [atb2]

    final det = ata00 * (ata11 * ata22 - ata12 * ata12) -
        ata01 * (ata01 * ata22 - ata12 * ata02) +
        ata02 * (ata01 * ata12 - ata11 * ata02);

    if (det.abs() < 1e-10) {
      // Degenerate case — use simple linear mapping
      setCoeffs([
        _screenSize.width,
        0.0,
        _screenSize.width / 2.0,
      ]);
      return;
    }

    final a = (atb0 * (ata11 * ata22 - ata12 * ata12) -
            ata01 * (atb1 * ata22 - ata12 * atb2) +
            ata02 * (atb1 * ata12 - ata11 * atb2)) /
        det;

    final b = (ata00 * (atb1 * ata22 - ata12 * atb2) -
            atb0 * (ata01 * ata22 - ata12 * ata02) +
            ata02 * (ata01 * atb2 - atb1 * ata02)) /
        det;

    final c = (ata00 * (ata11 * atb2 - atb1 * ata12) -
            ata01 * (ata01 * atb2 - atb1 * ata02) +
            atb0 * (ata01 * ata12 - ata11 * ata02)) /
        det;

    setCoeffs([a, b, c]);
  }

  /// Clear calibration
  void clearCalibration() {
    _profile = null;
  }
}
