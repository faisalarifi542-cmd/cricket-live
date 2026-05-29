import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../components.dart';
import '../../models/api_models.dart';
import '../../models/api_response.dart';
import '../../repositories/cricket_repository.dart';
import '../player/player_detail_screen.dart';

class TeamDetailScreen extends StatefulWidget {
  const TeamDetailScreen({super.key, required this.teamId});

  final String teamId;

  @override
  State<TeamDetailScreen> createState() => _TeamDetailScreenState();
}

class _TeamDetailScreenState extends State<TeamDetailScreen> {
  final CricketRepository _repository = CricketRepository();
  late Future<ApiEnvelope<ApiTeamProfile>> _team;

  @override
  void initState() {
    super.initState();
    _team = _repository.team(widget.teamId);
  }

  Future<void> _refresh() async {
    setState(() => _team = _repository.team(widget.teamId, forceRefresh: true));
    await _team;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(gradient: c.bgGradient),
        child: SafeArea(
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: EdgeInsets.fromLTRB(context.horizontalPadding, 18,
                  context.horizontalPadding, context.detailBottomPadding),
              children: [
                AppHeader(
                  leading: IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.arrow_back_rounded, color: c.text),
                  ),
                  title: 'Team',
                ),
                const SizedBox(height: 18),
                FutureBuilder<ApiEnvelope<ApiTeamProfile>>(
                  future: _team,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 28),
                        child: Center(child: CircularProgressIndicator()),
                      );
                    }
                    if (snapshot.hasError) {
                      return _TeamStateCard(
                        text: 'Unable to load team profile. Pull to retry.',
                        onRetry: () => setState(() => _team =
                            _repository.team(widget.teamId, forceRefresh: true)),
                      );
                    }
                    final team = snapshot.data?.data;
                    if (team == null || team.id.isEmpty) {
                      return _TeamStateCard(
                        text: 'Team profile is not available yet.',
                        onRetry: () => setState(() => _team =
                            _repository.team(widget.teamId, forceRefresh: true)),
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _TeamHero(team: team),
                        const SizedBox(height: 16),
                        _TeamSection(
                          title: 'Squad',
                          empty: 'Squad is not available yet.',
                          items: team.squad,
                          itemBuilder: (item) => _SquadPlayerTile(player: apiMap(item)),
                        ),
                        const SizedBox(height: 16),
                        _TeamSection(
                          title: 'Recent matches',
                          empty: 'Recent matches are not available yet.',
                          items: team.recentMatches,
                          itemBuilder: (item) => _SimpleTeamRow(data: apiMap(item)),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TeamHero extends StatelessWidget {
  const _TeamHero({required this.team});

  final ApiTeamProfile team;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return PremiumCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          CircleAvatar(
            radius: 46,
            backgroundColor: c.card2,
            backgroundImage: team.logo == null ? null : NetworkImage(team.logo!),
            child: team.logo == null
                ? Text(
                    (team.shortName ?? team.name).isEmpty ? '?' : (team.shortName ?? team.name)[0],
                    style: TextStyle(color: c.text, fontWeight: FontWeight.w900, fontSize: 30),
                  )
                : null,
          ),
          const SizedBox(height: 14),
          Text(
            team.name,
            textAlign: TextAlign.center,
            style: TextStyle(color: c.text, fontWeight: FontWeight.w900, fontSize: 26),
          ),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              _TeamChip(text: team.shortName ?? team.id),
              if (team.country?.isNotEmpty == true) _TeamChip(text: team.country!),
            ],
          ),
        ],
      ),
    );
  }
}

class _TeamSection extends StatelessWidget {
  const _TeamSection({
    required this.title,
    required this.empty,
    required this.items,
    required this.itemBuilder,
  });

  final String title;
  final String empty;
  final List<dynamic> items;
  final Widget Function(dynamic item) itemBuilder;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return PremiumCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(color: c.text, fontWeight: FontWeight.w900, fontSize: 18)),
          const SizedBox(height: 12),
          if (items.isEmpty)
            Text(empty, style: TextStyle(color: c.muted, fontWeight: FontWeight.w700))
          else
            for (final item in items.take(20)) itemBuilder(item),
        ],
      ),
    );
  }
}

class _SquadPlayerTile extends StatelessWidget {
  const _SquadPlayerTile({required this.player});

  final Map<String, dynamic> player;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    final id = apiString(player['playerId'] ?? player['player_id'] ?? player['id']);
    final name = apiString(player['name'] ?? player['playerName'], 'Player');
    final image = apiString(player['imageUrl'] ?? player['image_url']);
    return InkWell(
      onTap: id.isEmpty ? null : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => PlayerDetailScreen(playerId: id))),
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: c.card2,
              backgroundImage: image.isEmpty ? null : NetworkImage(image),
              child: image.isEmpty ? Icon(Icons.person_rounded, color: c.muted) : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, style: TextStyle(color: c.text, fontWeight: FontWeight.w900)),
                  Text(apiString(player['role'], 'Role unavailable'), style: TextStyle(color: c.muted, fontWeight: FontWeight.w700, fontSize: 12)),
                ],
              ),
            ),
            if (id.isNotEmpty) Icon(Icons.chevron_right_rounded, color: c.muted),
          ],
        ),
      ),
    );
  }
}

class _SimpleTeamRow extends StatelessWidget {
  const _SimpleTeamRow({required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        apiString(data['title'] ?? data['name'] ?? data['matchDesc'], 'Match'),
        style: TextStyle(color: c.text, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _TeamChip extends StatelessWidget {
  const _TeamChip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: c.cyan.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: c.cyan.withValues(alpha: 0.25)),
      ),
      child: Text(text, style: TextStyle(color: c.cyan, fontWeight: FontWeight.w900, fontSize: 12)),
    );
  }
}

class _TeamStateCard extends StatelessWidget {
  const _TeamStateCard({required this.text, required this.onRetry});

  final String text;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final c = context.cric;
    return PremiumCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Icon(Icons.shield_outlined, color: c.cyan, size: 38),
          const SizedBox(height: 12),
          Text(text,
              textAlign: TextAlign.center,
              style: TextStyle(color: c.muted, height: 1.4)),
          const SizedBox(height: 16),
          GradientButton(
              label: 'Retry', icon: Icons.refresh_rounded, onTap: onRetry),
        ],
      ),
    );
  }
}
