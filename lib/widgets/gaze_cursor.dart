/// ===========================================================================
/// GazeNav - Gaze Cursor Overlay
/// ===========================================================================
/// Floating cursor that follows the user's gaze on screen.
/// Shows dwell progress as a circular indicator around the cursor.
/// ===========================================================================

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/constants.dart';
import '../models/gaze_data.dart';

class GazeCursorOverlay extends StatelessWidget {
  final Offset? position;
  final double dwellProgress; // 0.0 to 1.0
  final DwellState dwellState;
  final double cursorSize;
  final bool showDebugInfo;
  final GazeData? gazeData;

  const GazeCursorOverlay({
    super.key,
    this.position,
    this.dwellProgress = 0.0,
    this.dwellState = DwellState.idle,
    this.cursorSize = 40.0,
    this.showDebugInfo = false,
    this.gazeData,
  });

  @override
  Widget build(BuildContext context) {
    if (position == null) return const SizedBox.shrink();

    return Stack(
      children: [
        // ── Gaze cursor ──
        Positioned(
          left: position!.dx - cursorSize / 2,
          top: position!.dy - cursorSize / 2,
          child: _GazeCursor(
            size: cursorSize,
            dwellProgress: dwellProgress,
            dwellState: dwellState,
          ),
        ),

        // ── Debug info overlay ──
        if (showDebugInfo && gazeData != null)
          Positioned(
            bottom: 100,
            left: 16,
            right: 16,
            child: _DebugPanel(gazeData: gazeData!),
          ),
      ],
    );
  }
}

class _GazeCursor extends StatelessWidget {
  final double size;
  final double dwellProgress;
  final DwellState dwellState;

  const _GazeCursor({
    required this.size,
    required this.dwellProgress,
    required this.dwellState,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = dwellState == DwellState.dwelling;
    final isTriggered = dwellState == DwellState.triggered ||
        dwellState == DwellState.cooldown;

    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _CursorPainter(
          progress: dwellProgress,
          isActive: isActive,
          isTriggered: isTriggered,
        ),
        child: Center(
          child: Container(
            width: size * 0.3,
            height: size * 0.3,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isTriggered
                  ? AppConstants.dwellCompleteColor.withOpacity(0.8)
                  : AppConstants.cursorColor.withOpacity(0.6),
              boxShadow: [
                BoxShadow(
                  color: (isTriggered
                          ? AppConstants.dwellCompleteColor
                          : AppConstants.cursorColor)
                      .withOpacity(0.4),
                  blurRadius: 12,
                  spreadRadius: 2,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CursorPainter extends CustomPainter {
  final double progress;
  final bool isActive;
  final bool isTriggered;

  _CursorPainter({
    required this.progress,
    required this.isActive,
    required this.isTriggered,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 2;

    // ── Outer ring ──
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..color = AppConstants.cursorColor.withOpacity(0.5);
    canvas.drawCircle(center, radius, ringPaint);

    // ── Crosshair lines ──
    final crossPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = AppConstants.cursorColor.withOpacity(0.3);
    final crossLen = radius * 0.3;
    canvas.drawLine(
        Offset(center.dx - crossLen, center.dy),
        Offset(center.dx + crossLen, center.dy),
        crossPaint);
    canvas.drawLine(
        Offset(center.dx, center.dy - crossLen),
        Offset(center.dx, center.dy + crossLen),
        crossPaint);

    // ── Dwell progress arc ──
    if (isActive && progress > 0) {
      final progressColor = Color.lerp(
        AppConstants.dwellProgressColor,
        AppConstants.dwellCompleteColor,
        progress,
      )!;

      final arcPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.0
        ..strokeCap = StrokeCap.round
        ..color = progressColor;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        -math.pi / 2, // Start at top
        progress * 2 * math.pi, // Sweep angle
        false,
        arcPaint,
      );
    }

    // ── Triggered flash ──
    if (isTriggered) {
      final flashPaint = Paint()
        ..style = PaintingStyle.fill
        ..color = AppConstants.dwellCompleteColor.withOpacity(0.2);
      canvas.drawCircle(center, radius, flashPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _CursorPainter oldDelegate) =>
      progress != oldDelegate.progress ||
      isActive != oldDelegate.isActive ||
      isTriggered != oldDelegate.isTriggered;
}

class _DebugPanel extends StatelessWidget {
  final GazeData gazeData;

  const _DebugPanel({required this.gazeData});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'GAZE DEBUG',
            style: TextStyle(
              color: Colors.cyanAccent,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          _debugRow('Direction',
              '(${gazeData.gazeDirection.dx.toStringAsFixed(3)}, ${gazeData.gazeDirection.dy.toStringAsFixed(3)})'),
          _debugRow('Confidence', '${(gazeData.confidence * 100).toInt()}%'),
          if (gazeData.headPitch != null)
            _debugRow('Head',
                'P:${gazeData.headPitch!.toStringAsFixed(1)} Y:${gazeData.headYaw!.toStringAsFixed(1)} R:${gazeData.headRoll!.toStringAsFixed(1)}'),
          if (gazeData.leftEye != null)
            _debugRow('L-Eye',
                '(${gazeData.leftEye!.gazeX.toStringAsFixed(3)}, ${gazeData.leftEye!.gazeY.toStringAsFixed(3)})'),
          if (gazeData.rightEye != null)
            _debugRow('R-Eye',
                '(${gazeData.rightEye!.gazeX.toStringAsFixed(3)}, ${gazeData.rightEye!.gazeY.toStringAsFixed(3)})'),
        ],
      ),
    );
  }

  Widget _debugRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(label,
                style: const TextStyle(color: Colors.grey, fontSize: 11)),
          ),
          Text(value,
              style: const TextStyle(color: Colors.white, fontSize: 11)),
        ],
      ),
    );
  }
}
