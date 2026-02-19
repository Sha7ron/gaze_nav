/// ===========================================================================
/// GazeNav - Settings Screen
/// ===========================================================================

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/gaze_data.dart';
import '../services/gaze_tracking_provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late GazeConfig _config;

  @override
  void initState() {
    super.initState();
    _config = GazeConfig(
      dwellTimeMs: context.read<GazeTrackingProvider>().config.dwellTimeMs,
      cooldownMs: context.read<GazeTrackingProvider>().config.cooldownMs,
      smoothingWindow: context.read<GazeTrackingProvider>().config.smoothingWindow,
      fixationRadius: context.read<GazeTrackingProvider>().config.fixationRadius,
      cursorSize: context.read<GazeTrackingProvider>().config.cursorSize,
      targetFps: context.read<GazeTrackingProvider>().config.targetFps,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        title: const Text('Settings'),
        backgroundColor: Colors.black26,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionHeader('Dwell Selection'),
          _sliderSetting(
            'Dwell Time',
            '${(_config.dwellTimeMs / 1000).toStringAsFixed(1)}s',
            'How long to look at an app to select it',
            _config.dwellTimeMs.toDouble(),
            500,
            5000,
            (v) => setState(() => _config.dwellTimeMs = v.round()),
          ),
          _sliderSetting(
            'Cooldown',
            '${(_config.cooldownMs / 1000).toStringAsFixed(1)}s',
            'Pause after selection before next trigger',
            _config.cooldownMs.toDouble(),
            200,
            2000,
            (v) => setState(() => _config.cooldownMs = v.round()),
          ),
          _sliderSetting(
            'Fixation Radius',
            '${_config.fixationRadius.round()}px',
            'Max cursor movement to count as still looking',
            _config.fixationRadius,
            20,
            100,
            (v) => setState(() => _config.fixationRadius = v),
          ),

          const SizedBox(height: 24),
          _sectionHeader('Tracking'),
          _sliderSetting(
            'Smoothing',
            '${_config.smoothingWindow} frames',
            'More smoothing = less jitter but more latency',
            _config.smoothingWindow.toDouble(),
            1,
            15,
            (v) => setState(() => _config.smoothingWindow = v.round()),
          ),
          _sliderSetting(
            'Processing FPS',
            '${_config.targetFps} fps',
            'Higher = more responsive but uses more battery',
            _config.targetFps.toDouble(),
            5,
            30,
            (v) => setState(() => _config.targetFps = v.round()),
          ),

          const SizedBox(height: 24),
          _sectionHeader('Cursor'),
          _sliderSetting(
            'Cursor Size',
            '${_config.cursorSize.round()}px',
            'Size of the gaze cursor',
            _config.cursorSize,
            20,
            80,
            (v) => setState(() => _config.cursorSize = v),
          ),

          const SizedBox(height: 32),
          Center(
            child: ElevatedButton(
              onPressed: _saveSettings,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.cyanAccent,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 14),
              ),
              child: const Text('Save Settings', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: TextButton(
              onPressed: _resetDefaults,
              child: const Text('Reset to Defaults', style: TextStyle(color: Colors.white54)),
            ),
          ),

          const SizedBox(height: 32),
          _sectionHeader('About'),
          const Padding(
            padding: EdgeInsets.all(8),
            child: Text(
              'GazeNav v1.0\n'
              'Eye gaze navigation for accessibility.\n\n'
              'Uses MediaPipe/ML Kit for face and iris detection, '
              'computes gaze rays from eye centers through pupil centers, '
              'and maps them to screen coordinates for dwell-click interaction.\n\n'
              'Built as a college project to help people with motor disabilities '
              'access their mobile phones with ease.',
              style: TextStyle(color: Colors.white38, fontSize: 13, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 8),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.cyanAccent,
          fontSize: 16,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _sliderSetting(String title, String value, String description,
      double current, double min, double max, ValueChanged<double> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: const TextStyle(color: Colors.white, fontSize: 14)),
              Text(value, style: const TextStyle(color: Colors.cyanAccent, fontSize: 14)),
            ],
          ),
          const SizedBox(height: 2),
          Text(description, style: const TextStyle(color: Colors.white38, fontSize: 11)),
          Slider(
            value: current.clamp(min, max),
            min: min,
            max: max,
            activeColor: Colors.cyanAccent,
            inactiveColor: Colors.white12,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  void _saveSettings() {
    context.read<GazeTrackingProvider>().updateConfig(_config);
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Settings saved'), backgroundColor: Colors.green),
    );
  }

  void _resetDefaults() {
    setState(() {
      _config = GazeConfig();
    });
  }
}
