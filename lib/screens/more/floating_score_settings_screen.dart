import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../components.dart';
import '../../services/floating_score_overlay_service.dart';

/// Settings screen for the optional "Floating Score over other apps" feature.
///
/// Shows the current permission status and lets the user grant the permission or
/// stop an active bubble. This is informational + control only — the bubble is
/// actually started from Match Details (which has a live match in context).
class FloatingScoreSettingsScreen extends StatefulWidget {
  const FloatingScoreSettingsScreen({super.key});

  @override
  State<FloatingScoreSettingsScreen> createState() =>
      _FloatingScoreSettingsScreenState();
}

class _FloatingScoreSettingsScreenState
    extends State<FloatingScoreSettingsScreen> with WidgetsBindingObserver {
  final FloatingScoreOverlay _overlay = FloatingScoreOverlay.instance;

  FloatingScoreStatus? _status;
  bool _running = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-check after the user returns from the system permission screen.
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final status = await _overlay.status();
    final running = await _overlay.isRunning();
    if (!mounted) return;
    setState(() {
      _status = status;
      _running = running;
    });
  }

  Future<void> _grant() async {
    await _overlay.requestPermission();
    // Status refreshes via the lifecycle resume hook when the user returns.
  }

  Future<void> _stop() async {
    await _overlay.stop();
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final status = _status;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: c.bgGradient),
        child: SafeArea(
          child: ListView(
            padding: EdgeInsets.fromLTRB(context.horizontalPadding, 10,
                context.horizontalPadding, 24),
            children: [
              Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    behavior: HitTestBehavior.opaque,
                    child:
                        Icon(Icons.arrow_back_rounded, color: c.text, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Floating Score',
                      style: TextStyle(
                        color: c.text,
                        fontWeight: FontWeight.w900,
                        fontSize: 22,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              PremiumCard(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.picture_in_picture_alt_rounded,
                            color: c.cyan, size: 26),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Floating Score over other apps',
                            style: TextStyle(
                                color: c.text,
                                fontWeight: FontWeight.w800,
                                fontSize: 16),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Shows a small live cricket score bubble while you use other '
                      'apps, and a live score in your status bar. Start it from a '
                      'live match’s Minimize button. You can close it anytime.',
                      style: TextStyle(
                          color: c.muted, fontSize: 13, height: 1.4),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.touch_app_rounded, color: c.cyan, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Drag to move it. Double-tap the bubble to resize it '
                            '(compact → normal → large). Tap once to open the match.',
                            style: TextStyle(
                                color: c.muted, fontSize: 12, height: 1.4),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (status == null)
                      _StatusChip(label: 'Checking…', color: c.muted)
                    else
                      _StatusChip(
                        label: _statusLabel(status),
                        color: _statusColor(context, status),
                      ),
                    const SizedBox(height: 16),
                    if (status == FloatingScoreStatus.permissionNeeded)
                      _ActionButton(
                        label: 'Grant permission',
                        onTap: _grant,
                      ),
                    if (status == FloatingScoreStatus.unsupported)
                      Text(
                        'This device doesn’t support floating overlays. The '
                        'in-app minimized score bar will be used instead.',
                        style: TextStyle(color: c.muted, fontSize: 12),
                      ),
                    if (_running) ...[
                      const SizedBox(height: 10),
                      _ActionButton(
                        label: 'Stop floating score',
                        onTap: _stop,
                        danger: true,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _statusLabel(FloatingScoreStatus status) {
    switch (status) {
      case FloatingScoreStatus.enabled:
        return _running ? 'Active' : 'Enabled';
      case FloatingScoreStatus.permissionNeeded:
        return 'Permission needed';
      case FloatingScoreStatus.unsupported:
        return 'Unsupported';
    }
  }

  Color _statusColor(BuildContext context, FloatingScoreStatus status) {
    final c = context.cric;
    switch (status) {
      case FloatingScoreStatus.enabled:
        return const Color(0xff36d399);
      case FloatingScoreStatus.permissionNeeded:
        return const Color(0xffffc83d);
      case FloatingScoreStatus.unsupported:
        return c.muted;
    }
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: .45)),
      ),
      child: Text(
        label,
        style: TextStyle(
            color: color, fontWeight: FontWeight.w900, fontSize: 12),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final color = danger ? const Color(0xffef4444) : c.cyan;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color.withValues(alpha: .14),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: .5)),
        ),
        child: Text(
          label,
          style: TextStyle(
              color: color, fontWeight: FontWeight.w800, fontSize: 15),
        ),
      ),
    );
  }
}
