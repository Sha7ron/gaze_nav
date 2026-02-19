/// ===========================================================================
/// GazeNav - Calibration Screen
/// ===========================================================================
/// 9-point calibration flow: shows dots at known screen positions and
/// collects gaze samples while the user looks at each dot.
///
/// Flow:
///   1. Show instruction
///   2. For each of 9 points:
///      a. Show animated dot at target position
///      b. Wait for user to fixate (2 seconds)
///      c. Collect gaze samples during fixation
///      d. Move to next point
///   3. Compute calibration mapping
///   4. Show accuracy test
/// ===========================================================================

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/constants.dart';
import '../services/gaze_tracking_provider.dart';

class CalibrationScreen extends StatefulWidget {
  const CalibrationScreen({super.key});

  @override
  State<CalibrationScreen> createState() => _CalibrationScreenState();
}

class _CalibrationScreenState extends State<CalibrationScreen>
    with TickerProviderStateMixin {
  int _currentPointIndex = -1; // -1 = instruction screen
  bool _isCollecting = false;
  double _collectProgress = 0.0;
  Timer? _collectTimer;
  late AnimationController _dotAnimController;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _dotAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _collectTimer?.cancel();
    _dotAnimController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: _currentPointIndex < 0
            ? _buildInstructionScreen()
            : _buildCalibrationView(),
      ),
    );
  }

  /// ─── Instruction Screen ────────────────────────────────────────────
  Widget _buildInstructionScreen() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.visibility, size: 64, color: Colors.cyanAccent),
            const SizedBox(height: 24),
            const Text(
              'Gaze Calibration',
              style: TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'You will see dots appear at different positions on the screen.\n\n'
              'Look directly at each dot and hold your gaze steady for 2 seconds.\n\n'
              'Keep your head still and move only your eyes.\n\n'
              'This helps the app learn where you\'re looking.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 16, height: 1.5),
            ),
            const SizedBox(height: 40),
            ElevatedButton(
              onPressed: _startCalibration,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.cyanAccent,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30),
                ),
              ),
              child: const Text(
                'Start Calibration',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Skip', style: TextStyle(color: Colors.white54)),
            ),
          ],
        ),
      ),
    );
  }

  /// ─── Calibration View (shows dots) ─────────────────────────────────
  Widget _buildCalibrationView() {
    final screenSize = MediaQuery.of(context).size;
    final points = AppConstants.calibrationPoints;

    if (_currentPointIndex >= points.length) {
      return _buildCompletionScreen();
    }

    final normalizedPos = points[_currentPointIndex];
    final dotX = normalizedPos.dx * screenSize.width;
    final dotY = normalizedPos.dy * screenSize.height;

    return Stack(
      children: [
        // ── Progress indicator ──
        Positioned(
          top: 16,
          left: 0,
          right: 0,
          child: Column(
            children: [
              Text(
                'Point ${_currentPointIndex + 1} of ${points.length}',
                style: const TextStyle(color: Colors.white54, fontSize: 14),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: LinearProgressIndicator(
                  value: _currentPointIndex / points.length,
                  backgroundColor: Colors.white12,
                  valueColor: const AlwaysStoppedAnimation(Colors.cyanAccent),
                ),
              ),
            ],
          ),
        ),

        // ── Instruction text ──
        Positioned(
          bottom: 80,
          left: 0,
          right: 0,
          child: Text(
            _isCollecting ? 'Hold your gaze...' : 'Look at the dot',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: _isCollecting ? Colors.greenAccent : Colors.white70,
              fontSize: 18,
            ),
          ),
        ),

        // ── Calibration dot ──
        Positioned(
          left: dotX - 30,
          top: dotY - 30,
          child: _CalibrationDot(
            isCollecting: _isCollecting,
            progress: _collectProgress,
            pulseAnimation: _pulseController,
          ),
        ),

        // ── Cancel button ──
        Positioned(
          bottom: 24,
          right: 24,
          child: TextButton(
            onPressed: _cancelCalibration,
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
        ),
      ],
    );
  }

  /// ─── Completion Screen ─────────────────────────────────────────────
  Widget _buildCompletionScreen() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.check_circle, size: 64, color: Colors.greenAccent),
          const SizedBox(height: 24),
          const Text(
            'Calibration Complete!',
            style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          const Text(
            'Your gaze tracking is now calibrated.\nThe cursor should follow your eyes more accurately.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, fontSize: 16),
          ),
          const SizedBox(height: 40),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.greenAccent,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
            ),
            child: const Text('Continue', style: TextStyle(fontSize: 18)),
          ),
        ],
      ),
    );
  }

  /// ─── Start calibration flow ────────────────────────────────────────
  void _startCalibration() async {
    final provider = context.read<GazeTrackingProvider>();
    await provider.startCalibration();

    setState(() {
      _currentPointIndex = 0;
    });

    // Wait a moment then start collecting for first point
    await Future.delayed(const Duration(seconds: 1));
    _startCollecting();
  }

  /// ─── Start collecting samples for current point ────────────────────
  void _startCollecting() {
    final provider = context.read<GazeTrackingProvider>();
    provider.startSampleCollection();

    setState(() {
      _isCollecting = true;
      _collectProgress = 0.0;
    });

    // Animate collection progress over 2 seconds
    const totalMs = 2000;
    const intervalMs = 50;
    int elapsed = 0;

    _collectTimer?.cancel();
    _collectTimer = Timer.periodic(const Duration(milliseconds: intervalMs), (timer) {
      elapsed += intervalMs;
      setState(() {
        _collectProgress = (elapsed / totalMs).clamp(0.0, 1.0);
      });

      if (elapsed >= totalMs) {
        timer.cancel();
        _finishCurrentPoint();
      }
    });
  }

  /// ─── Finish current point and move to next ─────────────────────────
  void _finishCurrentPoint() {
    final provider = context.read<GazeTrackingProvider>();
    final screenSize = MediaQuery.of(context).size;
    final normalizedPos = AppConstants.calibrationPoints[_currentPointIndex];

    // Compute actual screen position
    final screenPos = Offset(
      normalizedPos.dx * screenSize.width,
      normalizedPos.dy * screenSize.height,
    );

    provider.finishSampleCollection(screenPos);

    setState(() {
      _isCollecting = false;
      _collectProgress = 0.0;
      _currentPointIndex++;
    });

    // If more points, start next after a brief pause
    if (_currentPointIndex < AppConstants.calibrationPoints.length) {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) _startCollecting();
      });
    } else {
      // All points collected — compute calibration
      provider.finishCalibration();
    }
  }

  /// ─── Cancel calibration ────────────────────────────────────────────
  void _cancelCalibration() {
    _collectTimer?.cancel();
    context.read<GazeTrackingProvider>().cancelCalibration();
    Navigator.pop(context, false);
  }
}

/// ─── Animated calibration dot ──────────────────────────────────────────
class _CalibrationDot extends StatelessWidget {
  final bool isCollecting;
  final double progress;
  final AnimationController pulseAnimation;

  const _CalibrationDot({
    required this.isCollecting,
    required this.progress,
    required this.pulseAnimation,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pulseAnimation,
      builder: (context, child) {
        final scale = isCollecting ? 1.0 : 1.0 + pulseAnimation.value * 0.3;
        return Transform.scale(
          scale: scale,
          child: SizedBox(
            width: 60,
            height: 60,
            child: CustomPaint(
              painter: _DotPainter(
                progress: progress,
                isCollecting: isCollecting,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _DotPainter extends CustomPainter {
  final double progress;
  final bool isCollecting;

  _DotPainter({required this.progress, required this.isCollecting});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    // Outer ring
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..color = isCollecting ? Colors.greenAccent : AppConstants.calibrationDotColor;
    canvas.drawCircle(center, 24, ringPaint);

    // Progress arc
    if (progress > 0) {
      final arcPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.0
        ..strokeCap = StrokeCap.round
        ..color = Colors.greenAccent;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: 24),
        -3.14159 / 2,
        progress * 2 * 3.14159,
        false,
        arcPaint,
      );
    }

    // Center dot
    final dotPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = AppConstants.calibrationDotColor;
    canvas.drawCircle(center, 8, dotPaint);
  }

  @override
  bool shouldRepaint(covariant _DotPainter old) =>
      progress != old.progress || isCollecting != old.isCollecting;
}
