/// ===========================================================================
/// GazeNav - Dwell Detector
/// ===========================================================================
/// Detects when the user's gaze fixates on a screen region for a specified
/// duration (default: 2 seconds). This is the primary selection mechanism
/// for users with motor disabilities — look at something to select it.
///
/// Algorithm:
///   1. Track current gaze position
///   2. If gaze stays within fixation radius for dwell_time → trigger
///   3. Brief cooldown after trigger to prevent rapid re-triggers
///   4. Reset if gaze moves outside fixation radius
/// ===========================================================================

import 'dart:ui';
import '../models/gaze_data.dart';

class DwellDetector {
  /// Configuration
  final int dwellTimeMs;
  final int cooldownMs;
  final double fixationRadius;

  /// State
  DwellState _state = DwellState.idle;
  Offset? _fixationCenter;
  DateTime? _fixationStart;
  DateTime? _lastTrigger;

  /// Callbacks
  void Function(Offset position)? onDwellStart;
  void Function(Offset position, double progress)? onDwellProgress;
  void Function(Offset position)? onDwellTriggered;
  void Function()? onDwellCancelled;

  DwellDetector({
    this.dwellTimeMs = 2000,
    this.cooldownMs = 500,
    this.fixationRadius = 50.0,
    this.onDwellStart,
    this.onDwellProgress,
    this.onDwellTriggered,
    this.onDwellCancelled,
  });

  DwellState get state => _state;

  /// Current dwell progress (0.0 to 1.0)
  double get progress {
    if (_state != DwellState.dwelling || _fixationStart == null) return 0.0;
    final elapsed = DateTime.now().difference(_fixationStart!).inMilliseconds;
    return (elapsed / dwellTimeMs).clamp(0.0, 1.0);
  }

  /// Current fixation center point
  Offset? get fixationCenter => _fixationCenter;

  /// ─────────────────────────────────────────────────────────────────────
  /// Update with new gaze position — call this every frame
  /// ─────────────────────────────────────────────────────────────────────
  void update(Offset gazePosition) {
    final now = DateTime.now();

    // ── Handle cooldown state ──
    if (_state == DwellState.cooldown) {
      if (_lastTrigger != null &&
          now.difference(_lastTrigger!).inMilliseconds >= cooldownMs) {
        _state = DwellState.idle;
        _fixationCenter = null;
        _fixationStart = null;
      }
      return;
    }

    // ── Check if gaze is within fixation radius ──
    if (_fixationCenter != null) {
      final distance = (gazePosition - _fixationCenter!).distance;

      if (distance <= fixationRadius) {
        // Still fixating — check if dwell time exceeded
        if (_state == DwellState.idle) {
          // Start dwelling
          _state = DwellState.dwelling;
          _fixationStart = now;
          onDwellStart?.call(_fixationCenter!);
        }

        if (_state == DwellState.dwelling) {
          final elapsed = now.difference(_fixationStart!).inMilliseconds;
          final prog = (elapsed / dwellTimeMs).clamp(0.0, 1.0);

          onDwellProgress?.call(_fixationCenter!, prog);

          if (elapsed >= dwellTimeMs) {
            // ── DWELL TRIGGERED ──
            _state = DwellState.cooldown;
            _lastTrigger = now;
            onDwellTriggered?.call(_fixationCenter!);
          }
        }
      } else {
        // Gaze moved outside fixation radius — reset
        _cancelDwell();
        // Start tracking new position
        _fixationCenter = gazePosition;
      }
    } else {
      // First position — start tracking
      _fixationCenter = gazePosition;
    }
  }

  /// Cancel current dwell
  void _cancelDwell() {
    if (_state == DwellState.dwelling) {
      onDwellCancelled?.call();
    }
    _state = DwellState.idle;
    _fixationStart = null;
  }

  /// Force reset (e.g., when tracking is lost)
  void reset() {
    _cancelDwell();
    _fixationCenter = null;
    _lastTrigger = null;
  }

  /// ─────────────────────────────────────────────────────────────────────
  /// Check if a specific screen region is being dwelled on
  /// ─────────────────────────────────────────────────────────────────────
  bool isDwellingOn(Rect region) {
    if (_state != DwellState.dwelling || _fixationCenter == null) return false;
    return region.contains(_fixationCenter!);
  }

  /// Get dwell progress for a specific region (0.0 if not dwelling on it)
  double progressFor(Rect region) {
    if (!isDwellingOn(region)) return 0.0;
    return progress;
  }
}
