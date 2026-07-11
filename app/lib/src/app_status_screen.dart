import 'package:flutter/material.dart';

/// Shown when the user opens the window from the tray (outside onboarding).
/// A thin status readout + shortcuts — the tray menu is the primary
/// control surface; this window exists mainly to host dialogs (calibration)
/// and the debug tools.
class AppStatusScreen extends StatelessWidget {
  const AppStatusScreen({
    required this.enabled,
    required this.onToggleEnabled,
    required this.onCalibrate,
    required this.onDebugTools,
    required this.onSettings,
    super.key,
  });

  final bool enabled;
  final VoidCallback onToggleEnabled;
  final VoidCallback onCalibrate;
  final VoidCallback onDebugTools;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xFF0D0D0F),
        body: Center(
          child: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  enabled ? Icons.front_hand_rounded : Icons.front_hand_outlined,
                  color: enabled ? Colors.greenAccent : Colors.white38,
                  size: 40,
                ),
                const SizedBox(height: 12),
                Text(
                  enabled ? 'Cursor control is on' : 'Cursor control is off',
                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Use the menu-bar icon to toggle at any time.',
                  style: TextStyle(color: Colors.white38, fontSize: 12),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(onPressed: onToggleEnabled, child: Text(enabled ? 'Disable' : 'Enable')),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(onPressed: onCalibrate, child: const Text('Calibrate…')),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(onPressed: onSettings, child: const Text('Settings…')),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(onPressed: onDebugTools, child: const Text('Debug tools…')),
                ),
              ],
            ),
          ),
        ),
      );
}
