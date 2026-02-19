/// ===========================================================================
/// GazeNav - Gaze Home Screen
/// ===========================================================================
/// The main launcher screen that displays apps in a grid layout.
/// Users navigate by looking at app icons — looking at an app for 2+ seconds
/// launches it (dwell-click). The gaze cursor overlay tracks eye position.
///
/// Layout:
///   ┌─────────────────────────────────────┐
///   │  Status Bar (tracking info)          │
///   │  ┌───┐ ┌───┐ ┌───┐ ┌───┐          │
///   │  │App│ │App│ │App│ │App│          │
///   │  └───┘ └───┘ └───┘ └───┘          │
///   │  ┌───┐ ┌───┐ ┌───┐ ┌───┐          │
///   │  │App│ │App│ │App│ │App│          │
///   │  └───┘ └───┘ └───┘ └───┘          │
///   │  ...                                │
///   │  [Calibrate] [Settings]             │
///   │                                     │
///   │  ● ← Gaze cursor (follows eyes)    │
///   └─────────────────────────────────────┘
/// ===========================================================================

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../core/constants.dart';
import '../models/gaze_data.dart';
import '../services/gaze_tracking_provider.dart';
import '../widgets/gaze_cursor.dart';
import '../widgets/app_tile.dart';
import 'calibration_screen.dart';
import 'settings_screen.dart';

class GazeHomeScreen extends StatefulWidget {
  const GazeHomeScreen({super.key});

  @override
  State<GazeHomeScreen> createState() => _GazeHomeScreenState();
}

class _GazeHomeScreenState extends State<GazeHomeScreen> {
  /// Keys for each app tile (to get their global positions for hit testing)
  final Map<int, GlobalKey> _appKeys = {};

  /// Which app tile is currently being gazed at (-1 = none)
  int _hoveredAppIndex = -1;

  /// Timer for checking gaze-app intersection
  Timer? _hitTestTimer;

  /// Show debug panel
  bool _showDebug = false;

  /// Demo apps (replace with actual installed apps via device_apps package)
  final List<_DemoApp> _apps = [
    _DemoApp('Phone', Icons.phone, Colors.green),
    _DemoApp('Messages', Icons.message, Colors.blue),
    _DemoApp('Camera', Icons.camera_alt, Colors.orange),
    _DemoApp('Gallery', Icons.photo_library, Colors.purple),
    _DemoApp('Settings', Icons.settings, Colors.grey),
    _DemoApp('Browser', Icons.language, Colors.indigo),
    _DemoApp('Maps', Icons.map, Colors.teal),
    _DemoApp('Music', Icons.music_note, Colors.pink),
    _DemoApp('Calendar', Icons.calendar_today, Colors.red),
    _DemoApp('Clock', Icons.access_time, Colors.amber),
    _DemoApp('Calculator', Icons.calculate, Colors.cyan),
    _DemoApp('Notes', Icons.note, Colors.yellow),
    _DemoApp('Weather', Icons.cloud, Colors.lightBlue),
    _DemoApp('Mail', Icons.mail, Colors.redAccent),
    _DemoApp('Contacts', Icons.contacts, Colors.blueGrey),
    _DemoApp('Files', Icons.folder, Colors.brown),
  ];

  @override
  void initState() {
    super.initState();
    // Generate keys for each app tile
    for (int i = 0; i < _apps.length; i++) {
      _appKeys[i] = GlobalKey();
    }
    // Start hit testing loop
    _hitTestTimer = Timer.periodic(const Duration(milliseconds: 100), _checkGazeHits);

    // Initialize tracking after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initTracking();
    });
  }

  @override
  void dispose() {
    _hitTestTimer?.cancel();
    super.dispose();
  }

  Future<void> _initTracking() async {
    final provider = context.read<GazeTrackingProvider>();
    final screenSize = MediaQuery.of(context).size;
    provider.setScreenSize(screenSize);

    if (provider.state == TrackingState.uninitialized) {
      await provider.initialize();
    }
    if (provider.state == TrackingState.ready) {
      await provider.startTracking();
    }

    // Set up dwell callback
    provider.setDwellCallback((position) {
      _onDwellTriggered(position);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<GazeTrackingProvider>(
      builder: (context, provider, _) {
        return Scaffold(
          backgroundColor: const Color(0xFF121212),
          body: SafeArea(
            child: Stack(
              children: [
                // ── Main content ──
                Column(
                  children: [
                    _buildStatusBar(provider),
                    Expanded(child: _buildAppGrid(provider)),
                    _buildBottomBar(provider),
                  ],
                ),

                // ── Gaze cursor overlay (on top of everything) ──
                GazeCursorOverlay(
                  position: provider.cursorPosition,
                  dwellProgress: provider.dwellProgress,
                  dwellState: provider.dwellState,
                  cursorSize: provider.config.cursorSize,
                  showDebugInfo: _showDebug,
                  gazeData: provider.currentGaze,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// ─── Status Bar ────────────────────────────────────────────────────
  Widget _buildStatusBar(GazeTrackingProvider provider) {
    final stateText = switch (provider.state) {
      TrackingState.uninitialized => 'Not Started',
      TrackingState.initializing => 'Starting...',
      TrackingState.ready => 'Ready',
      TrackingState.tracking => 'Tracking',
      TrackingState.calibrating => 'Calibrating',
      TrackingState.error => 'Error',
    };

    final stateColor = switch (provider.state) {
      TrackingState.tracking => Colors.greenAccent,
      TrackingState.calibrating => Colors.amberAccent,
      TrackingState.error => Colors.redAccent,
      _ => Colors.white54,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.black26,
      child: Row(
        children: [
          // Status indicator
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: stateColor,
            ),
          ),
          const SizedBox(width: 8),
          Text(stateText, style: TextStyle(color: stateColor, fontSize: 13)),

          const Spacer(),

          // Calibration indicator
          Icon(
            provider.isCalibrated ? Icons.check_circle : Icons.warning_amber,
            size: 16,
            color: provider.isCalibrated ? Colors.greenAccent : Colors.amberAccent,
          ),
          const SizedBox(width: 4),
          Text(
            provider.isCalibrated ? 'Calibrated' : 'Not Calibrated',
            style: TextStyle(
              color: provider.isCalibrated ? Colors.greenAccent : Colors.amberAccent,
              fontSize: 12,
            ),
          ),

          const SizedBox(width: 12),

          // Debug toggle
          GestureDetector(
            onTap: () => setState(() => _showDebug = !_showDebug),
            child: Icon(
              Icons.bug_report,
              size: 18,
              color: _showDebug ? Colors.cyanAccent : Colors.white30,
            ),
          ),
        ],
      ),
    );
  }

  /// ─── App Grid ──────────────────────────────────────────────────────
  Widget _buildAppGrid(GazeTrackingProvider provider) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: GridView.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          childAspectRatio: 0.8,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        itemCount: _apps.length,
        itemBuilder: (context, index) {
          final app = _apps[index];
          final isHovered = _hoveredAppIndex == index;
          final dwellProg = isHovered ? provider.dwellProgress : 0.0;

          return Container(
            key: _appKeys[index],
            child: GazeAppTile(
              appName: app.name,
              icon: app.icon,
              iconColor: app.color,
              isGazeHovering: isHovered,
              dwellProgress: dwellProg,
              onSelected: () => _launchApp(index),
            ),
          );
        },
      ),
    );
  }

  /// ─── Bottom Bar ────────────────────────────────────────────────────
  Widget _buildBottomBar(GazeTrackingProvider provider) {
    return Container(
      padding: const EdgeInsets.all(12),
      color: Colors.black26,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _BottomAction(
            icon: Icons.visibility,
            label: 'Calibrate',
            onTap: () => _openCalibration(),
          ),
          _BottomAction(
            icon: provider.state == TrackingState.tracking
                ? Icons.pause
                : Icons.play_arrow,
            label: provider.state == TrackingState.tracking ? 'Pause' : 'Start',
            onTap: () {
              if (provider.state == TrackingState.tracking) {
                provider.stopTracking();
              } else {
                provider.startTracking();
              }
            },
          ),
          _BottomAction(
            icon: Icons.settings,
            label: 'Settings',
            onTap: () => _openSettings(),
          ),
        ],
      ),
    );
  }

  /// ─── Hit Testing: Check which app tile the gaze is over ───────────
  void _checkGazeHits(Timer timer) {
    final provider = context.read<GazeTrackingProvider>();
    final cursorPos = provider.cursorPosition;

    if (cursorPos == null) {
      if (_hoveredAppIndex != -1) {
        setState(() => _hoveredAppIndex = -1);
      }
      return;
    }

    int hitIndex = -1;

    for (int i = 0; i < _apps.length; i++) {
      final key = _appKeys[i];
      if (key?.currentContext == null) continue;

      final renderBox = key!.currentContext!.findRenderObject() as RenderBox?;
      if (renderBox == null || !renderBox.hasSize) continue;

      final position = renderBox.localToGlobal(Offset.zero);
      final size = renderBox.size;
      final rect = Rect.fromLTWH(position.dx, position.dy, size.width, size.height);

      if (rect.contains(cursorPos)) {
        hitIndex = i;
        break;
      }
    }

    if (hitIndex != _hoveredAppIndex) {
      setState(() => _hoveredAppIndex = hitIndex);
    }
  }

  /// ─── Handle dwell selection ────────────────────────────────────────
  void _onDwellTriggered(Offset position) {
    if (_hoveredAppIndex >= 0 && _hoveredAppIndex < _apps.length) {
      _launchApp(_hoveredAppIndex);
    }
  }

  /// ─── Launch an app ─────────────────────────────────────────────────
  void _launchApp(int index) {
    final app = _apps[index];

    // Haptic feedback
    HapticFeedback.mediumImpact();

    // Show feedback
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(app.icon, color: app.color, size: 20),
            const SizedBox(width: 12),
            Text('Launching ${app.name}...'),
          ],
        ),
        duration: const Duration(seconds: 1),
        backgroundColor: Colors.grey[900],
        behavior: SnackBarBehavior.floating,
      ),
    );

    // TODO: Actually launch the app using device_apps package:
    // DeviceApps.openApp(app.packageName);
    debugPrint('Launching app: ${app.name}');
  }

  /// ─── Open calibration ──────────────────────────────────────────────
  void _openCalibration() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const CalibrationScreen()),
    );
    if (result == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Calibration successful!'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  /// ─── Open settings ─────────────────────────────────────────────────
  void _openSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
  }
}

/// Bottom action button
class _BottomAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _BottomAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white70, size: 24),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11)),
        ],
      ),
    );
  }
}

/// Demo app data
class _DemoApp {
  final String name;
  final IconData icon;
  final Color color;
  _DemoApp(this.name, this.icon, this.color);
}
