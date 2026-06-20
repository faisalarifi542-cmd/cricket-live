import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cricpro_flutter/app_theme.dart';
import 'package:cricpro_flutter/services/notification_service.dart';

/// First-run notification permission prompt.
///
/// Shown once (or until the user taps "Enable" or "Not Now"). Does NOT spam on
/// every app open: a "asked once" flag in SharedPreferences suppresses it for
/// the session and until the next fresh install (or prefs clear).
///
/// Usage: call [maybePrompt] from RootShell's first build / first didChangeDependencies.
class NotificationPromptService {
  NotificationPromptService._();
  static final NotificationPromptService instance =
      NotificationPromptService._();

  static const _keyAsked = 'notification_prompt_asked';
  bool _prompted = false;

  /// Shows the rationale bottom-sheet if:
  ///  * permission is not already granted
  ///  * the prompt hasn't been shown before (persisted pref)
  ///  * we haven't prompted in this session already
  ///
  /// Returns true if the user granted, false otherwise (including "Not Now").
  Future<bool> maybePrompt(BuildContext context) async {
    if (_prompted) return false;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_keyAsked) == true) return false;
    // Wait (bounded) for OneSignal init, which runs concurrently with the
    // splash. Showing the rationale before init means the "Enable" button would
    // hit requestPermission()'s !_initialized guard and silently no-op, and the
    // one-shot "asked" flag would be burned for nothing. Poll up to ~6s; if init
    // never lands this session, return without burning the flag so a later entry
    // (e.g. opening settings) can still prompt.
    if (!NotificationService.instance.isInitialized) {
      for (var i = 0; i < 30; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 200));
        if (NotificationService.instance.isInitialized) break;
      }
      if (!NotificationService.instance.isInitialized) return false;
    }
    if (NotificationService.instance.permissionGranted) return false;
    if (!context.mounted) return false;
    _prompted = true;
    await prefs.setBool(_keyAsked, true);
    if (!context.mounted) return false;
    final granted = await _showPrompt(context);
    return granted;
  }

  Future<bool> _showPrompt(BuildContext context) async {
    bool? result = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isDismissible: true,
      builder: (ctx) => const _NotificationPromptSheet(),
    );
    return result == true;
  }
}

class _NotificationPromptSheet extends StatelessWidget {
  const _NotificationPromptSheet();

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        decoration: BoxDecoration(
          gradient: c.cardGradient,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: c.border),
          boxShadow: c.cardShadow,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.notifications_active_rounded,
                color: c.cyan, size: 48),
            const SizedBox(height: 16),
            Text(
              'Enable match alerts?',
              style: TextStyle(
                color: c.text,
                fontWeight: FontWeight.w900,
                fontSize: 20,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Get live match, wicket, score, and stream alerts. '
              'You can change this anytime in Settings.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: c.muted,
                fontSize: 14,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: GestureDetector(
                onTap: () async {
                  final granted =
                      await NotificationService.instance.requestPermission();
                  if (context.mounted) Navigator.pop(context, granted);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: c.primaryGradient,
                  ),
                  child: const Text(
                    'Enable Notifications',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () => Navigator.pop(context, false),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Not Now',
                  style: TextStyle(
                    color: c.muted,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
