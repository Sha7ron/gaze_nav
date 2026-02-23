/// ===========================================================================
/// GazeNav - Gaze Engine v3  (COMPLETE REWRITE)
/// ===========================================================================
///
/// v1 problem: Used ML Kit eye landmark → barely moves (±0.5px)
/// v2 problem: Pixel iris detection fails with dark eyes / uneven lighting
///             Falls back to landmark → same issue as v1
///
/// v3 approach: "CONTOUR CORNER RATIO" method
/// ─────────────────────────────────────────────
/// Uses the eye CONTOUR CORNERS as stable reference anchors and measures
/// the ML Kit landmark position AS A RATIO within the eye opening.
///
/// ML Kit eye contour (16 points):
///   Point 0:  inner corner (near nose)
///   Points 1-7: upper eyelid (inner → outer)
///   Point 8:  outer corner (far from nose)
///   Points 9-15: lower eyelid (outer → inner)
///
/// Gaze computation:
///   horizontalRatio = (landmark.x - innerCorner.x) / (outerCorner.x - innerCorner.x)
///   verticalRatio   = (landmark.y - topLid.y) / (bottomLid.y - topLid.y)
///
/// This gives a small but CONSISTENT signal (range ±0.05 to ±0.15).
/// Combined with head pose and heavy amplification in the ScreenMapper,
/// this produces usable gaze tracking.
///
/// Additionally: auto-ranging tracks the min/max gaze values observed
/// and dynamically adjusts sensitivity to map the user's actual
/// eye movement range to the full screen.
///
/// ===========================================================================

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import '../models/gaze_data.dart';

class GazeEngine {
  // ── EMA smoothing ──
  double _alpha; // Higher = more responsive, lower = smoother
  ui.Offset _ema = ui.Offset.zero;
  bool _emaInit = false;

  // ── Head pose smoothing ──
  double _emaPitch = 0, _emaYaw = 0;

  // ── Auto-ranging: track observed gaze extremes ──
  double _minGX = 0, _maxGX = 0;
  double _minGY = 0, _maxGY = 0;
  int _rangeSamples = 0;
  static const int _rangeWarmup = 30; // frames before auto-range kicks in

  // ── Baseline: average gaze when looking straight ──
  double _baselineGX = 0, _baselineGY = 0;
  int _baselineSamples = 0;
  bool _baselineSet = false;
  static const int _baselineFrames = 20; // frames to establish baseline

  GazeEngine({double smoothingAlpha = 0.25}) : _alpha = smoothingAlpha;

  set smoothingFactor(double v) => _alpha = v.clamp(0.05, 0.90);

  /// Auto-range gain multiplier for X and Y
  double get _autoGainX {
    if (_rangeSamples < _rangeWarmup) return 1.0;
    final range = _maxGX - _minGX;
    if (range < 0.01) return 1.0;
    // We want to map the observed range to [-1, 1]
    // So gain = 2.0 / range, but cap it to avoid crazy amplification
    return (2.0 / range).clamp(1.0, 40.0);
  }

  double get _autoGainY {
    if (_rangeSamples < _rangeWarmup) return 1.0;
    final range = _maxGY - _minGY;
    if (range < 0.01) return 1.0;
    return (2.0 / range).clamp(1.0, 40.0);
  }

  /// ═══════════════════════════════════════════════════════════════════
  /// MAIN: Face → GazeData
  /// ═══════════════════════════════════════════════════════════════════
  GazeData? processFace(Face face, ui.Size imageSize) {
    final lc = face.contours[FaceContourType.leftEye];
    final rc = face.contours[FaceContourType.rightEye];
    final ll = face.landmarks[FaceLandmarkType.leftEye];
    final rl = face.landmarks[FaceLandmarkType.rightEye];

    if (lc == null && rc == null) return null;

    // ── Process each eye ──
    final leftEye = _processEye(lc, ll);
    final rightEye = _processEye(rc, rl);

    if (leftEye == null && rightEye == null) return null;

    // ── Combine ──
    final rawGaze = _combineEyes(leftEye, rightEye);

    // ── Subtract baseline (center offset) ──
    final centered = _subtractBaseline(rawGaze);

    // ── Head pose ──
    final pitch = face.headEulerAngleX ?? 0.0;
    final yaw = face.headEulerAngleY ?? 0.0;
    _emaPitch = _emaPitch * 0.7 + pitch * 0.3;
    _emaYaw = _emaYaw * 0.7 + yaw * 0.3;

    // ── Add head pose contribution ──
    // Head rotation provides a MUCH bigger signal than eye movement alone.
    // Fuse: gaze = eye_signal * weight + head_signal * weight
    // Head yaw of 10° ≈ looking ~15% to the side
    final fused = ui.Offset(
      centered.dx * 1.0 + _emaYaw * 0.04,   // Head yaw in degrees → gaze units
      centered.dy * 1.0 + _emaPitch * 0.035,  // Head pitch
    );

    // ── Update auto-range ──
    _updateAutoRange(fused);

    // ── Apply auto-gain ──
    final gained = ui.Offset(
      fused.dx * _autoGainX,
      fused.dy * _autoGainY,
    );

    // ── EMA smooth ──
    final smoothed = _applyEMA(gained);

    // ── Confidence ──
    final conf = _confidence(face, leftEye, rightEye);

    return GazeData(
      gazeDirection: smoothed,
      leftEye: leftEye,
      rightEye: rightEye,
      headPitch: _emaPitch,
      headYaw: _emaYaw,
      headRoll: face.headEulerAngleZ ?? 0,
      confidence: conf,
    );
  }

  /// ═══════════════════════════════════════════════════════════════════
  /// PROCESS ONE EYE (contour corner ratio method)
  /// ═══════════════════════════════════════════════════════════════════
  EyeData? _processEye(FaceContour? contour, FaceLandmark? landmark) {
    if (contour == null || contour.points.length < 9) return null;

    final pts = contour.points;

    // ── Eye contour analysis ──
    // Point 0 = inner corner, Point 8 = outer corner
    final innerCorner = ui.Offset(pts[0].x.toDouble(), pts[0].y.toDouble());
    final outerCorner = ui.Offset(pts[8].x.toDouble(), pts[8].y.toDouble());

    // Upper lid midpoint (average of points 3, 4, 5)
    final topLid = ui.Offset(
      (pts[3].x + pts[4].x + pts[5].x) / 3.0,
      (pts[3].y + pts[4].y + pts[5].y) / 3.0,
    );

    // Lower lid midpoint (average of points 11, 12, 13)
    final lowerIdx1 = math.min(11, pts.length - 1);
    final lowerIdx2 = math.min(12, pts.length - 1);
    final lowerIdx3 = math.min(13, pts.length - 1);
    final bottomLid = ui.Offset(
      (pts[lowerIdx1].x + pts[lowerIdx2].x + pts[lowerIdx3].x) / 3.0,
      (pts[lowerIdx1].y + pts[lowerIdx2].y + pts[lowerIdx3].y) / 3.0,
    );

    // Eye center from contour
    double sx = 0, sy = 0;
    for (final p in pts) { sx += p.x; sy += p.y; }
    final eyeCenter = ui.Offset(sx / pts.length, sy / pts.length);

    // Eye bounds
    double x0 = 1e9, x1 = -1e9, y0 = 1e9, y1 = -1e9;
    for (final p in pts) {
      if (p.x < x0) x0 = p.x.toDouble();
      if (p.x > x1) x1 = p.x.toDouble();
      if (p.y < y0) y0 = p.y.toDouble();
      if (p.y > y1) y1 = p.y.toDouble();
    }
    final eyeBounds = ui.Rect.fromLTRB(x0, y0, x1, y1);
    if (eyeBounds.width < 5) return null;

    // ── Compute iris center ──
    // Primary: ML Kit landmark (approximate iris position)
    // Secondary: contour centroid (always available)
    ui.Offset irisCenter;
    if (landmark != null) {
      irisCenter = ui.Offset(
        landmark.position.x.toDouble(),
        landmark.position.y.toDouble(),
      );
    } else {
      irisCenter = eyeCenter; // Fallback
    }

    // ── CONTOUR CORNER RATIO: the key gaze signal ──
    //
    // Horizontal: where is the iris between inner and outer corner?
    // When looking toward inner corner → ratio decreases
    // When looking toward outer corner → ratio increases
    //
    final eyeWidth = outerCorner.dx - innerCorner.dx;
    final eyeHeight = bottomLid.dy - topLid.dy;

    double gazeRatioX = 0.0;
    double gazeRatioY = 0.0;

    if (eyeWidth.abs() > 3) {
      gazeRatioX = (irisCenter.dx - innerCorner.dx) / eyeWidth - 0.5;
    }
    if (eyeHeight.abs() > 2) {
      gazeRatioY = (irisCenter.dy - topLid.dy) / eyeHeight - 0.5;
    }

    // ── CONTOUR SHAPE ASYMMETRY (supplementary signal) ──
    //
    // When looking to one side, the contour shape becomes asymmetric.
    // The side you're looking toward gets "compressed" and the
    // opposite side has more visible sclera (wider opening).
    //
    // We measure this by comparing the average distance of left-half
    // vs right-half contour points from the eye center.
    //
    double leftDist = 0, rightDist = 0;
    int leftCount = 0, rightCount = 0;
    for (final p in pts) {
      final px = p.x.toDouble();
      if (px < eyeCenter.dx) {
        leftDist += (eyeCenter.dx - px);
        leftCount++;
      } else {
        rightDist += (px - eyeCenter.dx);
        rightCount++;
      }
    }
    if (leftCount > 0) leftDist /= leftCount;
    if (rightCount > 0) rightDist /= rightCount;

    double asymmetry = 0.0;
    if (leftDist + rightDist > 1) {
      asymmetry = (rightDist - leftDist) / (rightDist + leftDist);
    }

    // ── Fuse signals ──
    // Landmark ratio: primary signal (70%)
    // Contour asymmetry: secondary signal (30%)
    final fusedGazeX = gazeRatioX * 0.7 + asymmetry * 0.3;

    // Encode gaze into virtual iris position (so EyeData.gazeX/gazeY works correctly)
    // EyeData.gazeX = (iris.dx - center.dx) / (width / 2)
    // So we set: iris.dx = center.dx + gaze * (width / 2)
    final virtualIrisX = eyeCenter.dx + fusedGazeX * (eyeBounds.width / 2.0);
    final virtualIrisY = eyeCenter.dy + gazeRatioY * (eyeBounds.height / 2.0);

    return EyeData(
      eyeCenter: eyeCenter,
      irisCenter: ui.Offset(virtualIrisX, virtualIrisY),
      eyeBounds: eyeBounds,
      irisRadius: eyeBounds.width * 0.25,
    );
  }

  /// ═══════════════════════════════════════════════════════════════════
  /// BASELINE: Learn the "looking straight" offset
  /// ═══════════════════════════════════════════════════════════════════
  /// The first 20 frames establish what "looking straight" means.
  /// We subtract this so the gaze is centered at (0,0) when looking
  /// at the phone normally.
  ///
  ui.Offset _subtractBaseline(ui.Offset raw) {
    if (!_baselineSet) {
      _baselineGX += raw.dx;
      _baselineGY += raw.dy;
      _baselineSamples++;
      if (_baselineSamples >= _baselineFrames) {
        _baselineGX /= _baselineSamples;
        _baselineGY /= _baselineSamples;
        _baselineSet = true;
        debugPrint('GazeEngine: baseline set at (${_baselineGX.toStringAsFixed(4)}, ${_baselineGY.toStringAsFixed(4)})');
      }
      return ui.Offset.zero; // During warmup, return center
    }
    return ui.Offset(raw.dx - _baselineGX, raw.dy - _baselineGY);
  }

  /// ═══════════════════════════════════════════════════════════════════
  /// AUTO-RANGE: Track observed gaze extremes for dynamic gain
  /// ═══════════════════════════════════════════════════════════════════
  void _updateAutoRange(ui.Offset gaze) {
    _rangeSamples++;

    if (_rangeSamples == 1) {
      _minGX = gaze.dx; _maxGX = gaze.dx;
      _minGY = gaze.dy; _maxGY = gaze.dy;
      return;
    }

    // Slowly expand range (but never shrink — that would cause jitter)
    if (gaze.dx < _minGX) _minGX = _minGX * 0.95 + gaze.dx * 0.05;
    if (gaze.dx > _maxGX) _maxGX = _maxGX * 0.95 + gaze.dx * 0.05;
    if (gaze.dy < _minGY) _minGY = _minGY * 0.95 + gaze.dy * 0.05;
    if (gaze.dy > _maxGY) _maxGY = _maxGY * 0.95 + gaze.dy * 0.05;

    // Quick expansion when new extremes are found
    if (gaze.dx < _minGX) _minGX = gaze.dx;
    if (gaze.dx > _maxGX) _maxGX = gaze.dx;
    if (gaze.dy < _minGY) _minGY = gaze.dy;
    if (gaze.dy > _maxGY) _maxGY = gaze.dy;
  }

  /// ═══════════════════════════════════════════════════════════════════
  /// COMBINE EYES (weighted by eye width as quality proxy)
  /// ═══════════════════════════════════════════════════════════════════
  ui.Offset _combineEyes(EyeData? l, EyeData? r) {
    if (l != null && r != null) {
      final lw = l.eyeBounds.width;
      final rw = r.eyeBounds.width;
      final t = lw + rw;
      if (t < 1) return ui.Offset.zero;
      return ui.Offset(
        (l.gazeX * lw + r.gazeX * rw) / t,
        (l.gazeY * lw + r.gazeY * rw) / t,
      );
    }
    return l?.gazeOffset ?? r?.gazeOffset ?? ui.Offset.zero;
  }

  /// EMA smoothing
  ui.Offset _applyEMA(ui.Offset raw) {
    if (!_emaInit) {
      _ema = raw;
      _emaInit = true;
      return raw;
    }
    _ema = ui.Offset(
      _ema.dx * (1 - _alpha) + raw.dx * _alpha,
      _ema.dy * (1 - _alpha) + raw.dy * _alpha,
    );
    return _ema;
  }

  double _confidence(Face face, EyeData? l, EyeData? r) {
    double s = 0;
    if (face.trackingId != null) s += 0.15;
    if (l != null) s += 0.2;
    if (r != null) s += 0.2;
    final lo = face.leftEyeOpenProbability ?? 0.5;
    final ro = face.rightEyeOpenProbability ?? 0.5;
    s += ((lo + ro) / 2) * 0.3;
    if (l != null && r != null) {
      if ((l.gazeOffset - r.gazeOffset).distance < 0.5) s += 0.15;
    }
    return s.clamp(0.0, 1.0);
  }

  /// Reset (call on tracking loss or recalibration)
  void reset() {
    _ema = ui.Offset.zero;
    _emaInit = false;
    _emaPitch = 0;
    _emaYaw = 0;
    _rangeSamples = 0;
    _minGX = 0; _maxGX = 0;
    _minGY = 0; _maxGY = 0;
    // Don't reset baseline — keep it across tracking pauses
  }

  /// Full reset including baseline (call for recalibration)
  void fullReset() {
    reset();
    _baselineGX = 0;
    _baselineGY = 0;
    _baselineSamples = 0;
    _baselineSet = false;
  }
}