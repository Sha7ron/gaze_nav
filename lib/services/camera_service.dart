/// ===========================================================================
/// GazeNav - Camera Service
/// ===========================================================================
/// Manages the front-facing camera for continuous face/eye tracking.
/// Provides a stream of camera frames to the face detection pipeline.
/// ===========================================================================

import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

class CameraService {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  bool _isInitialized = false;
  bool _isProcessing = false;

  /// Callback for each camera frame
  void Function(CameraImage image)? onFrame;

  /// Target FPS for processing (skip frames to match)
  int targetFps;
  DateTime _lastProcessed = DateTime.now();

  CameraService({this.targetFps = 15});

  bool get isInitialized => _isInitialized;
  CameraController? get controller => _controller;

  /// ─────────────────────────────────────────────────────────────────────
  /// Initialize the front camera
  /// ─────────────────────────────────────────────────────────────────────
  Future<void> initialize() async {
    _cameras = await availableCameras();

    // Find front camera
    final frontCamera = _cameras!.firstWhere(
      (cam) => cam.lensDirection == CameraLensDirection.front,
      orElse: () => _cameras!.first,
    );

    _controller = CameraController(
      frontCamera,
      // Use medium resolution for balance between accuracy and performance.
      // Higher resolution = better eye detail but slower processing.
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: defaultTargetPlatform == TargetPlatform.android
          ? ImageFormatGroup.nv21   // Required by ML Kit on Android
          : ImageFormatGroup.bgra8888, // Required by ML Kit on iOS
    );

    await _controller!.initialize();
    _isInitialized = true;
  }

  /// ─────────────────────────────────────────────────────────────────────
  /// Start streaming camera frames for processing
  /// ─────────────────────────────────────────────────────────────────────
  Future<void> startStreaming() async {
    if (!_isInitialized || _controller == null) return;

    await _controller!.startImageStream((CameraImage image) {
      // Frame rate limiting
      final now = DateTime.now();
      final minInterval = Duration(milliseconds: (1000 / targetFps).round());
      if (now.difference(_lastProcessed) < minInterval) return;

      // Skip if still processing previous frame
      if (_isProcessing) return;

      _lastProcessed = now;
      _isProcessing = true;

      try {
        onFrame?.call(image);
      } finally {
        _isProcessing = false;
      }
    });
  }

  /// ─────────────────────────────────────────────────────────────────────
  /// Stop streaming
  /// ─────────────────────────────────────────────────────────────────────
  Future<void> stopStreaming() async {
    if (_controller?.value.isStreamingImages ?? false) {
      await _controller?.stopImageStream();
    }
  }

  /// ─────────────────────────────────────────────────────────────────────
  /// Get camera info for coordinate transformations
  /// ─────────────────────────────────────────────────────────────────────
  CameraDescription? get cameraDescription => _cameras?.firstWhere(
        (cam) => cam.lensDirection == CameraLensDirection.front,
        orElse: () => _cameras!.first,
      );

  int get sensorOrientation => cameraDescription?.sensorOrientation ?? 0;

  /// ─────────────────────────────────────────────────────────────────────
  /// Cleanup
  /// ─────────────────────────────────────────────────────────────────────
  Future<void> dispose() async {
    await stopStreaming();
    await _controller?.dispose();
    _controller = null;
    _isInitialized = false;
  }
}
