import 'package:flutter/material.dart';

import '../native/accessibility_permission.dart';
import '../native/camera_permission.dart';
import '../native/cursor_backend.dart';

/// First-run permission flow: camera, then Accessibility, each with its own
/// explanatory copy shown *before* triggering the OS prompt for it — the
/// camera TCC dialog especially shouldn't appear before the user
/// understands why a menu-bar app wants their camera.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({required this.onComplete, super.key});

  final VoidCallback onComplete;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

enum _Step { cameraExplain, cameraDenied, accessibilityExplain }

class _OnboardingScreenState extends State<OnboardingScreen> {
  _Step _step = _Step.cameraExplain;

  Future<void> _requestCamera() async {
    final granted = await CameraPermission.request();
    if (!mounted) return;
    if (!granted) {
      setState(() => _step = _Step.cameraDenied);
      return;
    }
    // `isTrusted` is unconditionally true on Windows (no Accessibility-style
    // grant needed for SendInput) and may already be true on macOS from a
    // previous session — either way, skip a step that has nothing left to
    // ask for instead of showing macOS-specific copy that wouldn't apply.
    if (CursorBackend.instance.isTrusted) {
      widget.onComplete();
    } else {
      setState(() => _step = _Step.accessibilityExplain);
    }
  }

  void _checkAccessibility() {
    if (CursorBackend.instance.isTrusted) {
      widget.onComplete();
    } else {
      setState(() {}); // re-render the "not yet granted" hint
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0F),
      body: Center(
        child: SizedBox(
          width: 360,
          child: switch (_step) {
            _Step.cameraExplain => _StepCard(
                icon: Icons.videocam_outlined,
                title: 'Camera access',
                body: 'air_pointer_app watches your hand through the camera '
                    'to move the cursor and click. Video is processed '
                    'entirely on this device and never leaves it.',
                actionLabel: 'Continue',
                onAction: _requestCamera,
              ),
            _Step.cameraDenied => _StepCard(
                icon: Icons.videocam_off_outlined,
                title: 'Camera access denied',
                body: 'Enable it in System Settings > Privacy & Security > '
                    'Camera, then reopen this window from the menu bar.',
                actionLabel: 'Open System Settings',
                onAction: () => AccessibilityPermission.openSystemSettings(),
              ),
            _Step.accessibilityExplain => _StepCard(
                icon: Icons.accessibility_new_rounded,
                title: 'Accessibility access',
                body: 'To move the real cursor and click, macOS requires '
                    'Accessibility permission. Grant it in System Settings, '
                    'then come back here.',
                actionLabel: 'Open System Settings',
                onAction: () => AccessibilityPermission.openSystemSettings(),
                secondaryLabel: "I've granted it",
                onSecondary: _checkAccessibility,
              ),
          },
        ),
      ),
    );
  }
}

class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.icon,
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.onAction,
    this.secondaryLabel,
    this.onSecondary,
  });

  final IconData icon;
  final String title;
  final String body;
  final String actionLabel;
  final VoidCallback onAction;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white70, size: 36),
          const SizedBox(height: 16),
          Text(title, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          Text(
            body,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white60, fontSize: 13, height: 1.5),
          ),
          const SizedBox(height: 24),
          SizedBox(width: double.infinity, child: FilledButton(onPressed: onAction, child: Text(actionLabel))),
          if (secondaryLabel != null) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(onPressed: onSecondary, child: Text(secondaryLabel!)),
            ),
          ],
        ],
      );
}
