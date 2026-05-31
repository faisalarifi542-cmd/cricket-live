import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../components.dart';
import '../../models.dart';
import '../../models/api_models.dart';
import '../../models/api_response.dart';
import '../../repositories/cricket_repository.dart';

class PlayerDetailScreen extends StatefulWidget {
  const PlayerDetailScreen({super.key, this.player, this.playerId = ''});

  final PlayerInfo? player;
  final String playerId;

  @override
  State<PlayerDetailScreen> createState() => _PlayerDetailScreenState();
}

class _PlayerDetailScreenState extends State<PlayerDetailScreen> {
  final CricketRepository _repository = CricketRepository();
  Future<ApiEnvelope<ApiPlayer>>? _player;

  String get _playerId {
    final arg = ModalRoute.of(context)?.settings.arguments;
    if (arg is String && arg.isNotEmpty) return arg;
    return widget.playerId;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_player == null && _playerId.isNotEmpty) {
      _player = _repository.player(_playerId);
    }
  }

  Future<void> _refresh() async {
    if (_playerId.isEmpty) return;
    setState(() => _player = _repository.player(_playerId, forceRefresh: true));
    await _player;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final fallback = widget.player;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: c.bgGradient),
        child: SafeArea(
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: EdgeInsets.fromLTRB(
                context.horizontalPadding,
                18,
                context.horizontalPadding,
                context.detailBottomPadding,
              ),
              children: [
                AppHeader(
                  leading: IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.arrow_back_rounded, color: c.text),
                  ),
                  title: fallback?.name ?? 'Player',
                ),
                const SizedBox(height: 18),
                if (_player != null)
                  _ApiPlayerCard(future: _player!)
                else if (fallback != null)
                  _FallbackPlayerCard(player: fallback)
                else
                  const _PlayerStateCard(
                    text: 'Open a player from a squad or scorecard to view the real profile.',
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ApiPlayerCard extends StatelessWidget {
  const _ApiPlayerCard({required this.future});

  final Future<ApiEnvelope<ApiPlayer>> future;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return FutureBuilder<ApiEnvelope<ApiPlayer>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const LinearProgressIndicator();
        }
        if (snapshot.hasError) {
          return const _PlayerStateCard(text: 'Unable to load player profile. Pull to retry.');
        }
        final player = snapshot.data?.data;
        if (player == null || player.id.isEmpty) {
          return const _PlayerStateCard(text: 'Player profile is not available yet.');
        }
        final stats = player.stats.entries.where((entry) => apiString(entry.value).isNotEmpty).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PremiumCard(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 38,
                        backgroundColor: c.card2,
                        backgroundImage: player.image == null
                            ? null
                            : NetworkImage(
                                player.image!,
                                webHtmlElementStrategy:
                                    WebHtmlElementStrategy.prefer,
                              ),
                        child: player.image == null
                            ? Text(
                                player.name.isEmpty ? '?' : player.name[0],
                                style: TextStyle(color: c.text, fontWeight: FontWeight.w900, fontSize: 24),
                              )
                            : null,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(player.name, style: TextStyle(color: c.text, fontWeight: FontWeight.w900, fontSize: 22)),
                            const SizedBox(height: 4),
                            Text(
                              '${player.country ?? 'Unknown'} - ${player.role ?? 'Role unavailable'}',
                              style: TextStyle(color: c.cyan, fontWeight: FontWeight.w800),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _PlayerFacts(player: player),
                ],
              ),
            ),
            const SizedBox(height: 12),
            PremiumCard(
              padding: const EdgeInsets.all(18),
              child: stats.isEmpty
                  ? Text('Stats are not available yet.', style: TextStyle(color: c.muted, fontWeight: FontWeight.w700))
                  : Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        for (final entry in stats.take(12))
                          _ApiStatPill(title: entry.key, value: apiString(entry.value)),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _FallbackPlayerCard extends StatelessWidget {
  const _FallbackPlayerCard({required this.player});

  final PlayerInfo player;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return PremiumCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          PlayerAvatar(player: player, size: 110, borderColor: c.cyan),
          const SizedBox(height: 16),
          Text(player.name, style: TextStyle(color: c.text, fontSize: 28, fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          Text('${player.team.name} - ${player.role}', style: TextStyle(color: c.cyan, fontWeight: FontWeight.w700)),
          if (player.subtitle != null) ...[
            const SizedBox(height: 6),
            Text(player.subtitle!, style: TextStyle(color: c.muted)),
          ],
        ],
      ),
    );
  }
}

class _PlayerFacts extends StatelessWidget {
  const _PlayerFacts({required this.player});

  final ApiPlayer player;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final rows = {
      'Batting': player.battingStyle,
      'Bowling': player.bowlingStyle,
      'Born': player.dateOfBirth,
    }.entries.where((entry) => apiString(entry.value).isNotEmpty).toList();
    if (rows.isEmpty) {
      return Text(
        'Profile details will appear here when the provider includes them.',
        style: TextStyle(color: c.muted, height: 1.4),
      );
    }
    return Column(
      children: [
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                SizedBox(width: 82, child: Text(row.key, style: TextStyle(color: c.muted, fontWeight: FontWeight.w800))),
                Expanded(child: Text(apiString(row.value), style: TextStyle(color: c.text, fontWeight: FontWeight.w800))),
              ],
            ),
          ),
      ],
    );
  }
}

class _ApiStatPill extends StatelessWidget {
  const _ApiStatPill({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Container(
      constraints: const BoxConstraints(minWidth: 96),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.cyan.withValues(alpha: 0.20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: TextStyle(color: c.text, fontWeight: FontWeight.w900, fontSize: 18)),
          const SizedBox(height: 4),
          Text(title, style: TextStyle(color: c.muted, fontWeight: FontWeight.w700, fontSize: 11)),
        ],
      ),
    );
  }
}

class _PlayerStateCard extends StatelessWidget {
  const _PlayerStateCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return PremiumCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Icon(Icons.person_outline_rounded, color: c.cyan),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: TextStyle(color: c.muted, fontWeight: FontWeight.w700))),
        ],
      ),
    );
  }
}
