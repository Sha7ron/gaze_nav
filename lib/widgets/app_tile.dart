/// ===========================================================================
/// GazeNav - Gaze-Aware App Tile
/// ===========================================================================
/// An app icon tile that responds to gaze dwell selection.
/// Shows visual feedback when the user's gaze hovers over it,
/// and triggers app launch when dwell time (2s) is reached.
/// ===========================================================================

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../core/constants.dart';

class GazeAppTile extends StatelessWidget {
  final String appName;
  final IconData icon;
  final Color iconColor;
  final double dwellProgress; // 0.0 to 1.0
  final bool isGazeHovering;
  final VoidCallback? onSelected;

  const GazeAppTile({
    super.key,
    required this.appName,
    required this.icon,
    this.iconColor = Colors.white,
    this.dwellProgress = 0.0,
    this.isGazeHovering = false,
    this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onSelected, // Also support touch for fallback
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: isGazeHovering
              ? Colors.white.withOpacity(0.15)
              : Colors.transparent,
          border: isGazeHovering
              ? Border.all(color: AppConstants.cursorColor.withOpacity(0.5), width: 2)
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── App Icon with Dwell Progress Ring ──
            SizedBox(
              width: 64,
              height: 64,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Dwell progress ring
                  if (dwellProgress > 0)
                    SizedBox(
                      width: 64,
                      height: 64,
                      child: CustomPaint(
                        painter: _DwellRingPainter(progress: dwellProgress),
                      ),
                    ),

                  // App icon container
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: isGazeHovering ? 52 : 48,
                    height: isGazeHovering ? 52 : 48,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      color: iconColor.withOpacity(0.2),
                      boxShadow: isGazeHovering
                          ? [
                              BoxShadow(
                                color: iconColor.withOpacity(0.3),
                                blurRadius: 12,
                                spreadRadius: 1,
                              )
                            ]
                          : null,
                    ),
                    child: Icon(
                      icon,
                      size: isGazeHovering ? 28 : 24,
                      color: iconColor,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 6),

            // ── App Name ──
            Text(
              appName,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isGazeHovering ? FontWeight.w600 : FontWeight.w400,
                color: isGazeHovering ? Colors.white : Colors.white70,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DwellRingPainter extends CustomPainter {
  final double progress;

  _DwellRingPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 2;

    // Background ring
    final bgPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..color = Colors.white.withOpacity(0.1);
    canvas.drawCircle(center, radius, bgPaint);

    // Progress arc
    final progressColor = Color.lerp(
      AppConstants.dwellProgressColor,
      AppConstants.dwellCompleteColor,
      progress,
    )!;

    final arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round
      ..color = progressColor;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      progress * 2 * math.pi,
      false,
      arcPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _DwellRingPainter old) =>
      progress != old.progress;
}
