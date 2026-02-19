/// ===========================================================================
/// GazeNav - Data Models
/// ===========================================================================
/// All data classes used across the gaze tracking pipeline.
/// ===========================================================================

import 'dart:ui';

/// Represents a single gaze data point computed from eye analysis.
class GazeData {
  /// Raw gaze direction vector (normalized, range roughly -1 to 1)
  final Offset gazeDirection;

  /// Mapped screen position (in logical pixels) — null before calibration
  final Offset? screenPoint;

  /// Individual eye data
  final EyeData? leftEye;
  final EyeData? rightEye;

  /// Head pose angles (degrees): pitch (up/down), yaw (left/right), roll (tilt)
  final double? headPitch;
  final double? headYaw;
  final double? headRoll;

  /// Confidence score 0.0 - 1.0
  final double confidence;

  /// Timestamp
  final DateTime timestamp;

  GazeData({
    required this.gazeDirection,
    this.screenPoint,
    this.leftEye,
    this.rightEye,
    this.headPitch,
    this.headYaw,
    this.headRoll,
    this.confidence = 0.0,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  /// Combined gaze direction (average of both eyes)
  static Offset combineEyes(EyeData? left, EyeData? right) {
    if (left != null && right != null) {
      return Offset(
        (left.gazeX + right.gazeX) / 2.0,
        (left.gazeY + right.gazeY) / 2.0,
      );
    }
    return left?.gazeOffset ?? right?.gazeOffset ?? Offset.zero;
  }
}

/// Data for a single eye — captures the relationship between
/// eye center and iris/pupil center to determine gaze direction.
class EyeData {
  /// Center of the eye socket (midpoint of eye contour)
  final Offset eyeCenter;

  /// Center of the iris/pupil
  final Offset irisCenter;

  /// Eye region bounding box
  final Rect eyeBounds;

  /// Iris radius in pixels
  final double irisRadius;

  EyeData({
    required this.eyeCenter,
    required this.irisCenter,
    required this.eyeBounds,
    this.irisRadius = 0.0,
  });

  /// Gaze direction: iris offset from eye center, normalized by eye width.
  /// Range: roughly -0.5 (looking left/up) to +0.5 (looking right/down)
  ///
  /// This is the core principle from our gaze ray algorithm:
  ///   gaze_direction = normalize(iris_center - eye_center)
  double get gazeX {
    if (eyeBounds.width < 1) return 0.0;
    return (irisCenter.dx - eyeCenter.dx) / (eyeBounds.width / 2.0);
  }

  double get gazeY {
    if (eyeBounds.height < 1) return 0.0;
    return (irisCenter.dy - eyeCenter.dy) / (eyeBounds.height / 2.0);
  }

  Offset get gazeOffset => Offset(gazeX, gazeY);

  /// The gaze ray: from eye center through iris center, extended
  GazeRay get gazeRay => GazeRay(
        origin: eyeCenter,
        direction: Offset(gazeX, gazeY),
      );
}

/// Represents a gaze ray projected from eye center through pupil center.
/// This matches the concept from our Python gaze_ray_tracker.
class GazeRay {
  final Offset origin;
  final Offset direction; // Normalized direction

  GazeRay({required this.origin, required this.direction});

  /// Get a point along the ray at distance t
  Offset pointAt(double t) => origin + direction * t;

  /// Find closest point (approximate intersection) between two 2D rays.
  /// Uses Cramer's rule — same algorithm as our Python implementation.
  static Offset? intersection(GazeRay ray1, GazeRay ray2) {
    final d1 = ray1.direction;
    final d2 = ray2.direction;
    final dp = ray2.origin - ray1.origin;

    final det = d1.dx * (-d2.dy) - d1.dy * (-d2.dx);
    if (det.abs() < 1e-10) return null; // Parallel rays

    final t = (dp.dx * (-d2.dy) - dp.dy * (-d2.dx)) / det;
    final s = (d1.dx * dp.dy - d1.dy * dp.dx) / det;

    final pt1 = ray1.pointAt(t);
    final pt2 = ray2.pointAt(s);

    // Midpoint of closest approach = approximate intersection
    return Offset((pt1.dx + pt2.dx) / 2, (pt1.dy + pt2.dy) / 2);
  }
}

/// A single calibration point: where the user looked + their gaze data.
class CalibrationPoint {
  /// Known screen position (the target dot)
  final Offset screenPosition;

  /// Measured raw gaze direction when looking at this point
  final Offset gazeDirection;

  CalibrationPoint({
    required this.screenPosition,
    required this.gazeDirection,
  });

  Map<String, dynamic> toJson() => {
        'sx': screenPosition.dx,
        'sy': screenPosition.dy,
        'gx': gazeDirection.dx,
        'gy': gazeDirection.dy,
      };

  factory CalibrationPoint.fromJson(Map<String, dynamic> json) =>
      CalibrationPoint(
        screenPosition: Offset(json['sx'], json['sy']),
        gazeDirection: Offset(json['gx'], json['gy']),
      );
}

/// Calibration profile containing all calibration points and
/// the computed mapping coefficients.
class CalibrationProfile {
  final List<CalibrationPoint> points;
  final DateTime calibratedAt;

  /// Polynomial mapping coefficients: screen_x = ax*gx + bx*gy + cx
  /// Computed via least-squares fit during calibration.
  double ax, bx, cx; // For X mapping
  double ay, by, cy; // For Y mapping

  CalibrationProfile({
    required this.points,
    DateTime? calibratedAt,
    this.ax = 0,
    this.bx = 0,
    this.cx = 0,
    this.ay = 0,
    this.by = 0,
    this.cy = 0,
  }) : calibratedAt = calibratedAt ?? DateTime.now();

  bool get isValid => points.length >= 5;
}

/// App info for the launcher grid
class AppInfo {
  final String name;
  final String packageName;
  final dynamic icon; // Uint8List from device_apps

  AppInfo({
    required this.name,
    required this.packageName,
    this.icon,
  });
}

/// Dwell selection state
enum DwellState {
  idle,       // Not dwelling on anything
  dwelling,   // Currently fixating on a target
  triggered,  // Dwell time exceeded — action triggered
  cooldown,   // Brief cooldown after trigger to prevent rapid re-triggers
}

/// Configuration for gaze tracking behavior
class GazeConfig {
  /// Dwell time in milliseconds to trigger selection
  int dwellTimeMs;

  /// Cooldown after selection in milliseconds
  int cooldownMs;

  /// Gaze smoothing window (number of frames)
  int smoothingWindow;

  /// Minimum confidence to show cursor
  double minConfidence;

  /// Cursor size in logical pixels
  double cursorSize;

  /// Fixation radius — max movement (pixels) to count as dwelling
  double fixationRadius;

  /// Camera processing FPS cap
  int targetFps;

  GazeConfig({
    this.dwellTimeMs = 2000,
    this.cooldownMs = 500,
    this.smoothingWindow = 5,
    this.minConfidence = 0.3,
    this.cursorSize = 40.0,
    this.fixationRadius = 50.0,
    this.targetFps = 15,
  });
}
