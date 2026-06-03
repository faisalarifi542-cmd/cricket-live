import 'package:flutter/material.dart';

import 'package:cricpro_flutter/app_theme.dart';
import 'package:cricpro_flutter/api_models.dart';
import 'package:cricpro_flutter/components.dart';
import 'package:cricpro_flutter/models.dart';
import 'package:cricpro_flutter/models/api_response.dart';
import 'package:cricpro_flutter/repositories/cricket_repository.dart';
import 'package:cricpro_flutter/widgets/squad.dart';

class TeamDetailScreen extends StatefulWidget {
  const TeamDetailScreen({
    super.key,
    this.teamId = '',
    this.initialName,
    this.initialShortName,
    this.initialLogoUrl,
    this.sourceSeriesId,
  });

  final String teamId;
  final String? initialName;
  final String? initialShortName;
  final String? initialLogoUrl;
  final String? sourceSeriesId;

  @override
  State<TeamDetailScreen> createState() => _TeamDetailScreenState();
}

class _TeamDetailScreenState extends State<TeamDetailScreen> {
  final CricketRepository _repository = CricketRepository();
  late Future<ApiEnvelope<ApiTeamProfile>> _team;

  @override
  void initState() {
    super.initState();
    _team = widget.teamId.isNotEmpty
        ? _repository.team(widget.teamId)
        : Future.value(
            ApiEnvelope<ApiTeamProfile>(
              data: ApiTeamProfile(
                id: widget.teamId,
                name: widget.initialName ?? 'Team',
                shortName: widget.initialShortName,
                logo: widget.initialLogoUrl,
                squad: const [],
                recentMatches: const [],
                series: widget.sourceSeriesId == null
                    ? const []
                    : [
                        {'seriesId': widget.sourceSeriesId},
                      ],
              ),
              meta: const ApiMeta(
                provider: 'webcrichd',
                cache: 'MISS',
                isStale: false,
              ),
            ),
          );
  }

  Future<void> _refresh() async {
    if (widget.teamId.isEmpty) return;
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
                      final fallback = _fallbackTeam();
                      if (fallback != null) {
                        return _TeamProfileView(
                          team: fallback,
                          sourceSeriesId: widget.sourceSeriesId,
                        );
                      }
                      return _TeamStateCard(
                        text: 'Unable to load team profile. Pull to retry.',
                        onRetry: widget.teamId.isEmpty
                            ? null
                            : () => setState(() => _team = _repository
                                .team(widget.teamId, forceRefresh: true)),
                      );
                    }
                    final team = snapshot.data?.data;
                    if (team == null || team.id.isEmpty) {
                      final fallback = _fallbackTeam();
                      if (fallback != null) {
                        return _TeamProfileView(
                          team: fallback,
                          sourceSeriesId: widget.sourceSeriesId,
                        );
                      }
                      return _TeamStateCard(
                        text: 'Team profile is not available yet.',
                        onRetry: widget.teamId.isEmpty
                            ? null
                            : () => setState(() => _team = _repository
                                .team(widget.teamId, forceRefresh: true)),
                      );
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _TeamHero(team: team),
                        const SizedBox(height: 16),
                        PremiumSquad(
                          playingXi: team.squad,
                          bench: const [],
                          title: 'Squad',
                        ),
                        const SizedBox(height: 16),
                        _TeamSection(
                          title: 'Recent matches',
                          empty: 'Recent matches are not available yet.',
                          items: team.recentMatches,
                          itemBuilder: (item) =>
                              _SimpleTeamRow(data: apiMap(item)),
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

  ApiTeamProfile? _fallbackTeam() {
    final name = widget.initialName?.trim() ?? '';
    final shortName = widget.initialShortName?.trim() ?? '';
    final logo = widget.initialLogoUrl?.trim() ?? '';
    if (name.isEmpty && shortName.isEmpty && logo.isEmpty) return null;
    return ApiTeamProfile(
      id: widget.teamId,
      name: name.isNotEmpty ? name : (shortName.isNotEmpty ? shortName : 'Team'),
      shortName: shortName.isNotEmpty ? shortName : null,
      logo: logo.isNotEmpty ? logo : null,
      squad: const [],
      recentMatches: const [],
      series: widget.sourceSeriesId == null
          ? const []
          : [
              {'seriesId': widget.sourceSeriesId},
            ],
    );
  }
}

class _TeamProfileView extends StatelessWidget {
  const _TeamProfileView({required this.team, this.sourceSeriesId});

  final ApiTeamProfile team;
  final String? sourceSeriesId;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TeamHero(team: team),
        const SizedBox(height: 16),
        PremiumSquad(
          playingXi: team.squad,
          bench: const [],
          title: 'Squad',
        ),
        const SizedBox(height: 16),
        _TeamSection(
          title: 'Recent matches',
          empty: 'Recent matches are not available yet.',
          items: team.recentMatches,
          itemBuilder: (item) => _SimpleTeamRow(data: apiMap(item)),
        ),
        if (sourceSeriesId != null) ...[
          const SizedBox(height: 16),
          const _TeamStateCard(
            text: 'Team profile loaded from series context. Full team stats are not available yet.',
            onRetry: null,
          ),
        ],
      ],
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
          TeamBadge(
            TeamInfo(
              code: team.shortName ?? team.name,
              name: team.name,
              shortName: team.shortName ?? team.name,
              color: c.cyan,
              asset: team.logo,
            ),
            size: 92,
            borderColor: c.cyan.withValues(alpha: .45),
          ),
          const SizedBox(height: 14),
          Text(
            team.name,
            textAlign: TextAlign.center,
            style: TextStyle(
                color: c.text, fontWeight: FontWeight.w900, fontSize: 26),
          ),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              _TeamChip(text: team.shortName ?? team.id),
              if (team.country?.isNotEmpty == true)
                _TeamChip(text: team.country!),
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
          Text(title,
              style: TextStyle(
                  color: c.text, fontWeight: FontWeight.w900, fontSize: 18)),
          const SizedBox(height: 12),
          if (items.isEmpty)
            Text(empty,
                style: TextStyle(color: c.muted, fontWeight: FontWeight.w700))
          else
            for (final item in items.take(20)) itemBuilder(item),
        ],
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
      child: Text(text,
          style: TextStyle(
              color: c.cyan, fontWeight: FontWeight.w900, fontSize: 12)),
    );
  }
}

class _TeamStateCard extends StatelessWidget {
  const _TeamStateCard({required this.text, this.onRetry});

  final String text;
  final VoidCallback? onRetry;

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
            label: 'Retry',
            icon: Icons.refresh_rounded,
            onTap: onRetry ?? () {},
            outlined: onRetry == null,
          ),
        ],
      ),
    );
  }
}
