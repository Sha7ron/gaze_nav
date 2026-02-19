/// ===========================================================================
/// GazeNav - Gaze Tracking Provider
/// ===========================================================================
/// Central state management class that coordinates all gaze tracking services:
///   Camera → Face Detection → Gaze Engine → Screen Mapper → Dwell Detector
///
/// This is the single source of truth for gaze state in the app.
/// Uses ChangeNotifier for Flutter Provider-based state management.
/// ===========================================================================

import 'dart:async';
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
  uninitialized,
  initializing,
  ready,       // Camera ready, not tracking yet
  tracking,    // Actively tracking gaze
  calibrating, // In calibration mode
  error,
}

class GazeTrackingProvider extends ChangeNotifier {
  // ── Services ──
  final CameraService _cameraService = CameraService(targetFps: 15);
  final FaceDetectionService _faceDetectionService = FaceDetectionService();
  final GazeEngine _gazeEngine = GazeEngine(smoothingWindow: 5);
  final ScreenMapper _screenMapper = ScreenMapper();
  late DwellDetector _dwellDetector;

  // ── State ──
  TrackingState _state = TrackingState.uninitialized;
  GazeData? _currentGaze;
  Offset? _cursorPosition;
  String? _errorMessage;
  bool _isCalibrated = false;

  // ── Config ──
  GazeConfig _config = GazeConfig();

  // ── Calibration ──
  List<CalibrationPoint> _calibrationPoints = [];
  int _currentCalibrationIndex = 0;
  List<Offset> _calibrationSamples = [];
  bool _isCollectingSamples = false;

  // ── Getters ──
  TrackingState get state => _state;
  GazeData? get currentGaze => _currentGaze;
  Offset? get cursorPosition => _cursorPosition;
  String? get errorMessage => _errorMessage;
  bool get isCalibrated => _isCalibrated;
  GazeConfig get config => _config;
  DwellDetector get dwellDetector => _dwellDetector;
  CameraController? get cameraController => _cameraService.controller;
  double get dwellProgress => _dwellDetector.progress;
  DwellState get dwellState => _dwellDetector.state;

  GazeTrackingProvider() {
    _dwellDetector = DwellDetector(
      dwellTimeMs: _config.dwellTimeMs,
      cooldownMs: _config.cooldownMs,
      fixationRadius: _config.fixationRadius,
    );
  }

  /// ─────────────────────────────────────────────────────────────────────
  /// Initialize camera and detection services
  /// ─────────────────────────────────────────────────────────────────────
  Future<void> initialize() async {
    if (_state == TrackingState.initializing) return;
    _state = TrackingState.initializing;
    notifyListeners();

    try {
      await _cameraService.initialize();

      // Set up frame processing callback
      _cameraService.onFrame = _onCameraFrame;

      _state = TrackingState.ready;
      _errorMessage = null;
    } catch (e) {
      _state = TrackingState.error;
      _errorMessage = 'Camera init failed: $e';
      debugPrint(_errorMessage);
    }
    notifyListeners();
  }

  /// ─────────────────────────────────────────────────────────────────────
  /// Start gaze tracking
  /// ─────────────────────────────────────────────────────────────────────
  Future<void> startTracking() async {
    if (_state != TrackingState.ready && _state != TrackingState.tracking) {
      return;
    }

    try {
      await _cameraService.startStreaming();
      _state = TrackingState.tracking;
      notifyListeners();
    } catch (e) {
      _state = TrackingState.error;
      _errorMessage = 'Streaming failed: $e';
      notifyListeners();
    }
  }

  /// ─────────────────────────────────────────────────────────────────────
  /// Stop gaze tracking
  /// ─────────────────────────────────────────────────────────────────────
  Future<void> stopTracking() async {
    await _cameraService.stopStreaming();
    _state = TrackingState.ready;
    _currentGaze = null;
    _cursorPosition = null;
    _gazeEngine.reset();
    _dwellDetector.reset();
    notifyListeners();
  }

  /// ─────────────────────────────────────────────────────────────────────
  /// Set screen size (call from build context)
  /// ─────────────────────────────────────────────────────────────────────
  void setScreenSize(Size size) {
    _screenMapper.setScreenSize(size);
  }

  /// ─────────────────────────────────────────────────────────────────────
  /// Process each camera frame
  /// ─────────────────────────────────────────────────────────────────────
  void _onCameraFrame(CameraImage image) async {
    if (_state != TrackingState.tracking && _state != TrackingState.calibrating) {
      return;
    }

    final camera = _cameraService.cameraDescription;
    if (camera == null) return;

    // ── Step 1: Detect faces ──
    final faces = await _faceDetectionService.detectFaces(image, camera);
    if (faces.isEmpty) {
      _currentGaze = null;
      _cursorPosition = null;
      _gazeEngine.reset();
      _dwellDetector.reset();
      notifyListeners();
      return;
    }

    // Use first detected face
    final face = faces.first;
    final imageSize = _faceDetectionService.getImageSize(image);

    // ── Step 2: Compute gaze ──
    final gazeData = _gazeEngine.processface(face, imageSize);
    if (gazeData == null) return;

    _currentGaze = gazeData;

    // ── Step 3: Map to screen ──
    if (_isCalibrated) {
      _cursorPosition = _screenMapper.mapToScreen(gazeData.gazeDirection);
    } else {
      _cursorPosition = _screenMapper.mapToScreenUncalibrated(gazeData.gazeDirection);
    }

    // ── Step 4: Feed to dwell detector ──
    if (_cursorPosition != null && _state == TrackingState.tracking) {
      _dwellDetector.update(_cursorPosition!);
    }

    // ── Step 5: Collect calibration samples if in calibration mode ──
    if (_state == TrackingState.calibrating && _isCollectingSamples) {
      _calibrationSamples.add(gazeData.gazeDirection);
    }

    notifyListeners();
  }

  // ═══════════════════════════════════════════════════════════════════════
  // CALIBRATION
  // ═══════════════════════════════════════════════════════════════════════

  /// Start calibration mode
  Future<void> startCalibration() async {
    _calibrationPoints = [];
    _currentCalibrationIndex = 0;
    _state = TrackingState.calibrating;
    _isCalibrated = false;

    if (!(_cameraService.controller?.value.isStreamingImages ?? false)) {
      await _cameraService.startStreaming();
    }

    notifyListeners();
  }

  /// Start collecting samples for the current calibration point
  void startSampleCollection() {
    _calibrationSamples = [];
    _isCollectingSamples = true;
  }

  /// Stop collecting and save the calibration point
  CalibrationPoint? finishSampleCollection(Offset screenPosition) {
    _isCollectingSamples = false;

    if (_calibrationSamples.isEmpty) return null;

    // Average all samples for this point
    double sumX = 0, sumY = 0;
    for (final s in _calibrationSamples) {
      sumX += s.dx;
      sumY += s.dy;
    }
    final avgGaze = Offset(
      sumX / _calibrationSamples.length,
      sumY / _calibrationSamples.length,
    );

    final point = CalibrationPoint(
      screenPosition: screenPosition,
      gazeDirection: avgGaze,
    );

    _calibrationPoints.add(point);
    _currentCalibrationIndex++;

    return point;
  }

  /// Finish calibration and compute mapping
  bool finishCalibration() {
    if (_calibrationPoints.length < 5) {
      debugPrint('Not enough calibration points: ${_calibrationPoints.length}');
      return false;
    }

    try {
      _screenMapper.calibrate(_calibrationPoints);
      _isCalibrated = true;
      _state = TrackingState.tracking;
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Calibration failed: $e');
      _state = TrackingState.tracking;
      notifyListeners();
      return false;
    }
  }

  /// Cancel calibration
  void cancelCalibration() {
    _isCollectingSamples = false;
    _state = TrackingState.tracking;
    notifyListeners();
  }

  int get currentCalibrationIndex => _currentCalibrationIndex;
  int get totalCalibrationPoints => 9;

  // ═══════════════════════════════════════════════════════════════════════
  // CONFIGURATION
  // ═══════════════════════════════════════════════════════════════════════

  void updateConfig(GazeConfig newConfig) {
    _config = newConfig;
    _gazeEngine.smoothingWindow = newConfig.smoothingWindow;
    _cameraService.targetFps = newConfig.targetFps;
    _dwellDetector = DwellDetector(
      dwellTimeMs: newConfig.dwellTimeMs,
      cooldownMs: newConfig.cooldownMs,
      fixationRadius: newConfig.fixationRadius,
    );
    notifyListeners();
  }

  /// Set dwell triggered callback
  void setDwellCallback(void Function(Offset position)? callback) {
    _dwellDetector.onDwellTriggered = callback;
  }

  // ═══════════════════════════════════════════════════════════════════════
  // CLEANUP
  // ═══════════════════════════════════════════════════════════════════════

  @override
  void dispose() {
    _cameraService.dispose();
    _faceDetectionService.dispose();
    super.dispose();
  }
}
