/// ===========================================================================
/// GazeNav - Face Detection Service
/// ===========================================================================
/// Wraps Google ML Kit Face Detection to detect face landmarks and contours
/// from camera frames. Provides the raw face data that the GazeEngine
/// processes into gaze direction.
///
/// ML Kit Face Detection features used:
///   - Face landmarks (eye centers, nose, mouth)
///   - Face contours (16-point eye boundaries for precise eye tracking)
///   - Head pose (Euler angles for 3D gaze compensation)
///   - Eye open probability (blink detection)
///   - Performance mode: accurate (for best eye tracking quality)
/// ===========================================================================

import 'dart:ui';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class FaceDetectionService {
  late FaceDetector _faceDetector;
  bool _isBusy = false;

  FaceDetectionService() {
    _faceDetector = FaceDetector(
      options: FaceDetectorOptions(
        enableClassification: true,   // Eye open probability, smile
        enableLandmarks: true,        // Eye, nose, mouth, ear landmarks
        enableContours: true,         // 16-point eye contours (CRITICAL for gaze)
        enableTracking: true,         // Track face across frames
        performanceMode: FaceDetectorMode.accurate, // Best quality for eye tracking
        minFaceSize: 0.15,           // Minimum face size relative to image
      ),
    );
  }

  /// ─────────────────────────────────────────────────────────────────────
  /// Process a camera frame and return detected faces
  /// ─────────────────────────────────────────────────────────────────────
  Future<List<Face>> detectFaces(CameraImage cameraImage,
      CameraDescription camera) async {
    if (_isBusy) return [];
    _isBusy = true;

    try {
      // Convert CameraImage to InputImage for ML Kit
      final inputImage = _convertCameraImage(cameraImage, camera);
      if (inputImage == null) return [];

      // Run face detection
      final faces = await _faceDetector.processImage(inputImage);
      return faces;
    } catch (e) {
      debugPrint('Face detection error: $e');
      return [];
    } finally {
      _isBusy = false;
    }
  }

  /// ─────────────────────────────────────────────────────────────────────
  /// Convert CameraImage to ML Kit InputImage
  /// ─────────────────────────────────────────────────────────────────────
  ///
  /// This handles the platform-specific image format conversion:
  ///   - Android: NV21 format from CameraX
  ///   - iOS: BGRA8888 format from AVFoundation
  ///
  InputImage? _convertCameraImage(
      CameraImage image, CameraDescription camera) {
    // Determine rotation
    final rotation = _getRotation(camera.sensorOrientation);
    if (rotation == null) return null;

    // Determine format
    final format = _getFormat(image.format.group);
    if (format == null) return null;

    // For NV21 (Android), we can use the first plane directly
    // For BGRA8888 (iOS), we use the first plane as well
    if (image.planes.isEmpty) return null;

    return InputImage.fromBytes(
      bytes: image.planes[0].bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: image.planes[0].bytesPerRow,
      ),
    );
  }

  /// Get InputImageRotation from sensor orientation
  InputImageRotation? _getRotation(int sensorOrientation) {
    switch (sensorOrientation) {
      case 0:
        return InputImageRotation.rotation0deg;
      case 90:
        return InputImageRotation.rotation90deg;
      case 180:
        return InputImageRotation.rotation180deg;
      case 270:
        return InputImageRotation.rotation270deg;
      default:
        return null;
    }
  }

  /// Get InputImageFormat from image format group
  InputImageFormat? _getFormat(ImageFormatGroup group) {
    switch (group) {
      case ImageFormatGroup.nv21:
        return InputImageFormat.nv21;
      case ImageFormatGroup.bgra8888:
        return InputImageFormat.bgra8888;
      default:
        return null;
    }
  }

  /// Get image size for coordinate transformations
  Size getImageSize(CameraImage image) {
    return Size(image.width.toDouble(), image.height.toDouble());
  }

  /// Cleanup
  void dispose() {
    _faceDetector.close();
  }
}
