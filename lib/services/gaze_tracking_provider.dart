/// ===========================================================================
/// GazeNav - Gaze Tracking Provider v3
/// ===========================================================================
///
/// Changes from v2:
///   - No longer passes CameraImage to GazeEngine (pixel iris detection removed)
///   - GazeEngine v3 uses contour corner ratios only — no pixel processing
///   - Guaranteed cursor: if face detected, cursor is ALWAYS shown
///   - Debug logging to diagnose gaze values in real-time
///   - Full baseline reset on calibration start
///
/// ===========================================================================

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

import '../core/gaze_engine.dart';
import '../core/screen_mapper.dart';
import '../core/dwell_detector.dart';
import '../models/gaze_data.dart';
import '../services/camera_service.dart';
import '../services/face_detection_service.dart';

enum TrackingState {
  uninitialized, initializing, ready, tracking, calibrating, error,
}

class GazeTrackingProvider extends ChangeNotifier {
  final CameraService _cam = CameraService(targetFps: 15);
  final FaceDetectionService _fd = FaceDetectionService();
  final GazeEngine _engine = GazeEngine(smoothingAlpha: 0.25);
  final ScreenMapper _mapper = ScreenMapper();
  late DwellDetector _dwell;

  TrackingState _state = TrackingState.uninitialized;
  GazeData? _currentGaze;
  Offset? _cursorPosition;
  String? _errorMessage;
  bool _isCalibrated = false;

  GazeConfig _config = GazeConfig();

  // Calibration
  List<CalibrationPoint> _calPts = [];
  int _calIndex = 0;
  List<Offset> _calSamples = [];
  bool _collecting = false;

  // Debug
  int _frameCount = 0;
  int _faceDetectedCount = 0;
  int _gazeComputedCount = 0;

  // Getters
  TrackingState get state => _state;
  GazeData? get currentGaze => _currentGaze;
  Offset? get cursorPosition => _cursorPosition;
  String? get errorMessage => _errorMessage;
  bool get isCalibrated => _isCalibrated;
  GazeConfig get config => _config;
  DwellDetector get dwellDetector => _dwell;
  CameraController? get cameraController => _cam.controller;
  double get dwellProgress => _dwell.progress;
  DwellState get dwellState => _dwell.state;
  int get currentCalibrationIndex => _calIndex;
  int get totalCalibrationPoints => 9;

  GazeTrackingProvider() {
    _dwell = DwellDetector(
      dwellTimeMs: _config.dwellTimeMs,
      cooldownMs: _config.cooldownMs,
      fixationRadius: _config.fixationRadius,
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // LIFECYCLE
  // ═══════════════════════════════════════════════════════════════════

  Future<void> initialize() async {
    if (_state == TrackingState.initializing) return;
    _state = TrackingState.initializing;
    notifyListeners();
    try {
      await _cam.initialize();
      _cam.onFrame = _onFrame;
      _state = TrackingState.ready;
      _errorMessage = null;
    } catch (e) {
      _state = TrackingState.error;
      _errorMessage = 'Camera init failed: $e';
    }
    notifyListeners();
  }

  Future<void> startTracking() async {
    if (_state != TrackingState.ready && _state != TrackingState.tracking) return;
    try {
      await _cam.startStreaming();
      _state = TrackingState.tracking;
      notifyListeners();
    } catch (e) {
      _state = TrackingState.error;
      _errorMessage = 'Stream failed: $e';
      notifyListeners();
    }
  }

  Future<void> stopTracking() async {
    await _cam.stopStreaming();
    _state = TrackingState.ready;
    _currentGaze = null;
    _cursorPosition = null;
    _engine.reset();
    _dwell.reset();
    notifyListeners();
  }

  void setScreenSize(Size s) => _mapper.setScreenSize(s);

  // ═══════════════════════════════════════════════════════════════════
  // FRAME PROCESSING PIPELINE
  // ═══════════════════════════════════════════════════════════════════

  void _onFrame(CameraImage image) async {
    if (_state != TrackingState.tracking &&
        _state != TrackingState.calibrating) return;

    final cam = _cam.cameraDescription;
    if (cam == null) return;

    _frameCount++;

    // Step 1: Detect face
    final faces = await _fd.detectFaces(image, cam);
    if (faces.isEmpty) {
      _currentGaze = null;
      _cursorPosition = null;
      _engine.reset();
      _dwell.reset();
      notifyListeners();
      return;
    }

    _faceDetectedCount++;
    final face = faces.first;
    final imgSize = _fd.getImageSize(image);

    // Step 2: Compute gaze (NO camera image needed in v3!)
    final gaze = _engine.processFace(face, imgSize);

    if (gaze == null) {
      // Face detected but gaze computation failed — shouldn't happen often
      debugPrint('GazeProvider: face detected but gaze null');
      return;
    }

    _gazeComputedCount++;
    _currentGaze = gaze;

    // Step 3: Map to screen — ALWAYS produce a position when face detected
    if (_isCalibrated) {
      _cursorPosition = _mapper.mapToScreen(gaze.gazeDirection)
          ?? _mapper.mapToScreenUncalibrated(gaze.gazeDirection);
    } else {
      _cursorPosition = _mapper.mapToScreenUncalibrated(gaze.gazeDirection);
    }

    // Step 4: Dwell detection
    if (_cursorPosition != null && _state == TrackingState.tracking) {
      _dwell.update(_cursorPosition!);
    }

    // Step 5: Calibration samples
    if (_state == TrackingState.calibrating && _collecting) {
      _calSamples.add(gaze.gazeDirection);
    }

    // Debug logging every 45 frames (~3 seconds)
    if (_frameCount % 45 == 0) {
      debugPrint(
          'GAZE DEBUG: '
              'dir=(${gaze.gazeDirection.dx.toStringAsFixed(4)}, ${gaze.gazeDirection.dy.toStringAsFixed(4)}) '
              'cursor=(${_cursorPosition?.dx.toStringAsFixed(0)}, ${_cursorPosition?.dy.toStringAsFixed(0)}) '
              'conf=${gaze.confidence.toStringAsFixed(2)} '
              'head=(${gaze.headYaw?.toStringAsFixed(1)}, ${gaze.headPitch?.toStringAsFixed(1)}) '
              'frames=$_frameCount faces=$_faceDetectedCount gaze=$_gazeComputedCount'
      );
    }

    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════
  // CALIBRATION
  // ═══════════════════════════════════════════════════════════════════

  Future<void> startCalibration() async {
    _calPts = [];
    _calIndex = 0;
    _state = TrackingState.calibrating;
    _isCalibrated = false;

    // Full reset: clear baseline so it relearns during calibration
    _engine.fullReset();
    _mapper.clearCalibration();

    if (!(_cam.controller?.value.isStreamingImages ?? false)) {
      await _cam.startStreaming();
    }
    notifyListeners();
  }

  void startSampleCollection() {
    _calSamples = [];
    _collecting = true;
  }

  CalibrationPoint? finishSampleCollection(Offset screenPos) {
    _collecting = false;
    if (_calSamples.isEmpty) return null;

    // Outlier-trimmed average
    Offset avg;
    if (_calSamples.length > 5) {
      final sortedX = List<Offset>.from(_calSamples)
        ..sort((a, b) => a.dx.compareTo(b.dx));
      final trim = (_calSamples.length * 0.2).round();
      final kept = sortedX.sublist(trim, sortedX.length - trim);
      double sx = 0, sy = 0;
      for (final s in kept) { sx += s.dx; sy += s.dy; }
      avg = Offset(sx / kept.length, sy / kept.length);
    } else {
      double sx = 0, sy = 0;
      for (final s in _calSamples) { sx += s.dx; sy += s.dy; }
      avg = Offset(sx / _calSamples.length, sy / _calSamples.length);
    }

    debugPrint('CAL point #$_calIndex: screen=(${screenPos.dx.toStringAsFixed(0)}, ${screenPos.dy.toStringAsFixed(0)}) '
        'gaze=(${avg.dx.toStringAsFixed(4)}, ${avg.dy.toStringAsFixed(4)}) '
        'samples=${_calSamples.length}');

    final pt = CalibrationPoint(screenPosition: screenPos, gazeDirection: avg);
    _calPts.add(pt);
    _calIndex++;
    return pt;
  }

  bool finishCalibration() {
    if (_calPts.length < 5) return false;

    // Check if calibration data has enough variance
    final gxs = _calPts.map((p) => p.gazeDirection.dx).toList();
    final gys = _calPts.map((p) => p.gazeDirection.dy).toList();
    final gxRange = gxs.reduce((a, b) => a > b ? a : b) - gxs.reduce((a, b) => a < b ? a : b);
    final gyRange = gys.reduce((a, b) => a > b ? a : b) - gys.reduce((a, b) => a < b ? a : b);

    debugPrint('CAL finish: ${_calPts.length} points, '
        'gaze X range=${gxRange.toStringAsFixed(4)}, Y range=${gyRange.toStringAsFixed(4)}');

    // If gaze range is too small, calibration won't help — skip it
    if (gxRange < 0.01 && gyRange < 0.01) {
      debugPrint('CAL SKIPPED: gaze range too small, using uncalibrated mode');
      _state = TrackingState.tracking;
      notifyListeners();
      return false;
    }

    try {
      _mapper.calibrate(_calPts);
      _isCalibrated = true;
      _state = TrackingState.tracking;
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('CAL failed: $e');
      _state = TrackingState.tracking;
      notifyListeners();
      return false;
    }
  }

  void cancelCalibration() {
    _collecting = false;
    _state = TrackingState.tracking;
    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════
  // CONFIG
  // ═══════════════════════════════════════════════════════════════════

  void updateConfig(GazeConfig c) {
    _config = c;
    _engine.smoothingFactor = c.smoothingWindow / 20.0;
    _cam.targetFps = c.targetFps;
    _dwell = DwellDetector(
      dwellTimeMs: c.dwellTimeMs,
      cooldownMs: c.cooldownMs,
      fixationRadius: c.fixationRadius,
    );
    notifyListeners();
  }

  void setDwellCallback(void Function(Offset)? cb) {
    _dwell.onDwellTriggered = cb;
  }

  @override
  void dispose() {
    _cam.dispose();
    _fd.dispose();
    super.dispose();
  }
}