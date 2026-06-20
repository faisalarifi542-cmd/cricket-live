import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../components.dart';
import '../../services/notification_service.dart';
import '../../services/notification_settings_service.dart';

/// Lets the user enable/disable notification categories. Choices persist
/// locally and mirror to OneSignal tags so server-side sends respect them.
///
/// We do NOT request the system notification permission aggressively: the
/// current status is shown, and the user may opt in with an explicit button
/// when permission has not yet been granted.
class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> with WidgetsBindingObserver {
  final NotificationSettingsService _settings =
      NotificationSettingsService.instance;

  bool _permissionGranted = false;
  bool _requesting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _settings.load();
    _refreshPermission();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-check after the user returns from the system permission screen.
    if (state == AppLifecycleState.resumed) _refreshPermission();
  }

  void _refreshPermission() {
    final granted = NotificationService.instance.permissionGranted;
    if (!mounted) return;
    setState(() => _permissionGranted = granted);
  }

  Future<void> _requestPermission() async {
    if (_requesting) return;
    setState(() => _requesting = true);
    final granted = await NotificationService.instance.requestPermission();
    if (!mounted) return;
    setState(() {
      _permissionGranted = granted;
      _requesting = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
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
                      'Notifications',
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
              _PermissionCard(
                granted: _permissionGranted,
                requesting: _requesting,
                onEnable: _requestPermission,
              ),
              const SizedBox(height: 16),
              ValueListenableBuilder<Map<String, bool>>(
                valueListenable: _settings.values,
                builder: (context, values, _) {
                  return PremiumCard(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 6),
                    child: Column(
                      children: [
                        for (var i = 0;
                            i < NotificationSettingsService.categories.length;
                            i++) ...[
                          if (i != 0)
                            Divider(
                              height: 1,
                              color: c.text.withValues(alpha: .07),
                            ),
                          _CategoryRow(
                            category:
                                NotificationSettingsService.categories[i],
                            enabled: values[NotificationSettingsService
                                    .categories[i].key] ??
                                NotificationSettingsService
                                    .categories[i].defaultOn,
                            onChanged: (v) => _settings.setEnabled(
                                NotificationSettingsService.categories[i].key,
                                v),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
              const SizedBox(height: 14),
              Text(
                'These choices are saved on this device. Turning a category off '
                'stops those alerts even while notifications are enabled.',
                style: TextStyle(color: c.muted, fontSize: 12, height: 1.4),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PermissionCard extends StatelessWidget {
  const _PermissionCard({
    required this.granted,
    required this.requesting,
    required this.onEnable,
  });

  final bool granted;
  final bool requesting;
  final VoidCallback onEnable;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final color =
        granted ? const Color(0xff36d399) : const Color(0xffffc83d);
    return PremiumCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.notifications_active_rounded, color: c.cyan, size: 26),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'System notifications',
                  style: TextStyle(
                      color: c.text,
                      fontWeight: FontWeight.w800,
                      fontSize: 16),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: .16),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: color.withValues(alpha: .45)),
            ),
            child: Text(
              granted ? 'Enabled' : 'Not enabled',
              style: TextStyle(
                  color: color, fontWeight: FontWeight.w900, fontSize: 12),
            ),
          ),
          if (!granted) ...[
            const SizedBox(height: 14),
            Text(
              'Notifications are turned off for this app, so you won’t receive '
              'any alerts. Enable them to get the categories below.',
              style: TextStyle(color: c.muted, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 14),
            InkWell(
              onTap: requesting ? null : onEnable,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: c.cyan.withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: c.cyan.withValues(alpha: .5)),
                ),
                child: Text(
                  requesting ? 'Requesting…' : 'Enable notifications',
                  style: TextStyle(
                      color: c.cyan,
                      fontWeight: FontWeight.w800,
                      fontSize: 15),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.category,
    required this.enabled,
    required this.onChanged,
  });

  final NotificationCategory category;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  category.title,
                  style: TextStyle(
                      color: c.text,
                      fontWeight: FontWeight.w700,
                      fontSize: 15),
                ),
                const SizedBox(height: 3),
                Text(
                  category.description,
                  style: TextStyle(
                      color: c.muted, fontSize: 12, height: 1.35),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Switch.adaptive(
            value: enabled,
            onChanged: onChanged,
            activeThumbColor: c.cyan,
          ),
        ],
      ),
    );
  }
}
