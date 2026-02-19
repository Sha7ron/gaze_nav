/// ===========================================================================
/// GazeNav - Constants
/// ===========================================================================

import 'dart:ui';

class AppConstants {
  // ─── MediaPipe / ML Kit Landmark Indices ─────────────────────────────
  // These match the landmark indices from our Python gaze_ray_tracker.py
  //
  // ML Kit provides landmarks and contours:
  //   - FaceLandmarkType.leftEye  → approximate eye center
  //   - FaceLandmarkType.rightEye → approximate eye center
  //   - FaceContourType.leftEye   → 16 points around left eye boundary
  //   - FaceContourType.rightEye  → 16 points around right eye boundary
  //
  // For iris: ML Kit doesn't expose iris landmarks directly, so we use
  // image processing on the eye region to find the iris center.

  // ─── Calibration ─────────────────────────────────────────────────────
  /// Standard 9-point calibration grid positions (normalized 0-1)
  static const List<Offset> calibrationPoints = [
    Offset(0.1, 0.1),   // Top-left
    Offset(0.5, 0.1),   // Top-center
    Offset(0.9, 0.1),   // Top-right
    Offset(0.1, 0.5),   // Middle-left
    Offset(0.5, 0.5),   // Center
    Offset(0.9, 0.5),   // Middle-right
    Offset(0.1, 0.9),   // Bottom-left
    Offset(0.5, 0.9),   // Bottom-center
    Offset(0.9, 0.9),   // Bottom-right
  ];

  /// Seconds to hold gaze at each calibration point
  static const double calibrationHoldSeconds = 2.0;

  /// Number of gaze samples to collect per calibration point
  static const int samplesPerCalibrationPoint = 20;

  // ─── Gaze Tracking ───────────────────────────────────────────────────
  static const int defaultDwellTimeMs = 2000;
  static const int defaultCooldownMs = 500;
  static const int defaultSmoothingWindow = 5;
  static const double defaultFixationRadius = 50.0;
  static const double defaultCursorSize = 40.0;
  static const double defaultMinConfidence = 0.3;

  // ─── UI ──────────────────────────────────────────────────────────────
  static const double appGridColumns = 4;
  static const double appTileSize = 80.0;
  static const double appTileSpacing = 16.0;

  // ─── Colors ──────────────────────────────────────────────────────────
  static const Color cursorColor = Color(0xFF00E5FF);      // Cyan
  static const Color dwellProgressColor = Color(0xFF00E676); // Green
  static const Color dwellCompleteColor = Color(0xFFFF5252);  // Red
  static const Color calibrationDotColor = Color(0xFFFFD600); // Yellow
}
