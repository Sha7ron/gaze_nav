/// ===========================================================================
/// GazeNav - Gaze Engine
/// ===========================================================================
/// Core gaze computation engine. Takes ML Kit face detection results and
/// computes gaze direction using the same principles as our Python
/// gaze_ray_tracker:
///
///   1. Eye center = geometric center of eye contour landmarks
///   2. Iris center = detected via ML Kit eye landmark + image processing
///   3. Gaze direction = normalized(iris_center - eye_center)
///   4. Combined gaze = average of both eye gaze vectors
///   5. Screen mapping via calibration polynomial
/// ===========================================================================

import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui';

import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../models/gaze_data.dart';

class GazeEngine {
  /// Smoothing buffer for gaze direction
  final Queue<Offset> _gazeBuffer = Queue();
  int smoothingWindow;

  /// Head pose smoothing
  final Queue<double> _pitchBuffer = Queue();
  final Queue<double> _yawBuffer = Queue();

  GazeEngine({this.smoothingWindow = 5});

  /// ─────────────────────────────────────────────────────────────────────
  /// MAIN: Process a detected face and compute gaze data
  /// ─────────────────────────────────────────────────────────────────────
  GazeData? processface(Face face, Size imageSize) {
    // Extract eye data from ML Kit landmarks and contours
    final leftEye = _extractEyeData(
      face,
      FaceContourType.leftEye,
      FaceLandmarkType.leftEye,
      imageSize,
    );
    final rightEye = _extractEyeData(
      face,
      FaceContourType.rightEye,
      FaceLandmarkType.rightEye,
      imageSize,
    );

    if (leftEye == null && rightEye == null) return null;

    // ── Combine gaze from both eyes ──
    final rawGaze = GazeData.combineEyes(leftEye, rightEye);

    // ── Apply smoothing (moving average filter) ──
    final smoothedGaze = _smooth(rawGaze);

    // ── Extract head pose ──
    final pitch = face.headEulerAngleX; // Up/down
    final yaw = face.headEulerAngleY;   // Left/right
    final roll = face.headEulerAngleZ;  // Tilt

    // ── Compensate gaze for head rotation ──
    // When head turns right, gaze shifts left relative to face.
    // We add a fraction of the head yaw/pitch to compensate.
    final compensatedGaze = _compensateForHeadPose(
      smoothedGaze,
      pitch ?? 0.0,
      yaw ?? 0.0,
    );

    // ── Compute confidence ──
    final confidence = _computeConfidence(face, leftEye, rightEye);

    return GazeData(
      gazeDirection: compensatedGaze,
      leftEye: leftEye,
      rightEye: rightEye,
      headPitch: pitch,
      headYaw: yaw,
      headRoll: roll,
      confidence: confidence,
    );
  }

  /// ─────────────────────────────────────────────────────────────────────
  /// Extract eye data from ML Kit face contours and landmarks
  /// ─────────────────────────────────────────────────────────────────────
  ///
  /// ML Kit provides:
  ///   - Eye contour: 16 points tracing the eye boundary
  ///   - Eye landmark: single point near the center of the visible eye
  ///
  /// We compute:
  ///   - eyeCenter: geometric center of the eye contour (= eye socket center)
  ///   - irisCenter: the ML Kit eye landmark point (approximates iris center)
  ///   - gazeDirection: irisCenter - eyeCenter (normalized by eye width)
  ///
  EyeData? _extractEyeData(
    Face face,
    FaceContourType contourType,
    FaceLandmarkType landmarkType,
    Size imageSize,
  ) {
    final contour = face.contours[contourType];
    final landmark = face.landmarks[landmarkType];

    if (contour == null || contour.points.isEmpty) return null;

    // ── Eye contour → eye center and bounds ──
    final points = contour.points;
    double sumX = 0, sumY = 0;
    double minX = double.infinity, maxX = double.negativeInfinity;
    double minY = double.infinity, maxY = double.negativeInfinity;

    for (final pt in points) {
      sumX += pt.x;
      sumY += pt.y;
      if (pt.x < minX) minX = pt.x.toDouble();
      if (pt.x > maxX) maxX = pt.x.toDouble();
      if (pt.y < minY) minY = pt.y.toDouble();
      if (pt.y > maxY) maxY = pt.y.toDouble();
    }

    final eyeCenter = Offset(sumX / points.length, sumY / points.length);
    final eyeBounds = Rect.fromLTRB(minX, minY, maxX, maxY);

    // ── Iris center from landmark ──
    // The ML Kit eye landmark gives us the approximate pupil/iris position.
    // When the user looks in different directions, this point shifts relative
    // to the eye contour center — that's our gaze signal!
    Offset irisCenter;
    if (landmark != null) {
      irisCenter = Offset(
        landmark.position.x.toDouble(),
        landmark.position.y.toDouble(),
      );
    } else {
      // Fallback: use contour center (no gaze info)
      irisCenter = eyeCenter;
    }

    // ── Estimate iris radius from eye size ──
    final eyeWidth = eyeBounds.width;
    final irisRadius = eyeWidth * 0.3; // Iris is roughly 30% of eye width

    return EyeData(
      eyeCenter: eyeCenter,
      irisCenter: irisCenter,
      eyeBounds: eyeBounds,
      irisRadius: irisRadius,
    );
  }

  /// ─────────────────────────────────────────────────────────────────────
  /// Apply moving average smoothing to reduce jitter
  /// ─────────────────────────────────────────────────────────────────────
  Offset _smooth(Offset raw) {
    _gazeBuffer.addLast(raw);
    while (_gazeBuffer.length > smoothingWindow) {
      _gazeBuffer.removeFirst();
    }

    double sx = 0, sy = 0;
    for (final pt in _gazeBuffer) {
      sx += pt.dx;
      sy += pt.dy;
    }
    return Offset(sx / _gazeBuffer.length, sy / _gazeBuffer.length);
  }

  /// ─────────────────────────────────────────────────────────────────────
  /// Compensate gaze direction for head rotation
  /// ─────────────────────────────────────────────────────────────────────
  ///
  /// When the head turns (e.g., 10° right), the eyes counter-rotate to
  /// maintain fixation. The raw gaze measured on the face doesn't account
  /// for this. We add a scaled head pose component to compensate.
  ///
  /// This is the same principle as our Python code's 3D gaze compensation
  /// using solvePnP + rotation matrix inversion.
  ///
  Offset _compensateForHeadPose(Offset gaze, double pitch, double yaw) {
    // Compensation factors (tune these empirically)
    const yawFactor = 0.02;   // How much head yaw affects horizontal gaze
    const pitchFactor = 0.015; // How much head pitch affects vertical gaze

    return Offset(
      gaze.dx + yaw * yawFactor,
      gaze.dy + pitch * pitchFactor,
    );
  }

  /// ─────────────────────────────────────────────────────────────────────
  /// Compute confidence score based on face detection quality
  /// ─────────────────────────────────────────────────────────────────────
  double _computeConfidence(Face face, EyeData? left, EyeData? right) {
    double score = 0.0;

    // Face tracking confidence
    if (face.trackingId != null) score += 0.2;

    // Both eyes detected
    if (left != null) score += 0.25;
    if (right != null) score += 0.25;

    // Eyes are open (check eye open probability)
    final leftOpen = face.leftEyeOpenProbability ?? 0.5;
    final rightOpen = face.rightEyeOpenProbability ?? 0.5;
    score += (leftOpen + rightOpen) / 2.0 * 0.3;

    return score.clamp(0.0, 1.0);
  }

  /// Reset smoothing buffers (call when tracking is lost)
  void reset() {
    _gazeBuffer.clear();
    _pitchBuffer.clear();
    _yawBuffer.clear();
  }
}
