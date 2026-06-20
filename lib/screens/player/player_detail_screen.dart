import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'package:cricpro_flutter/app_theme.dart';
import 'package:cricpro_flutter/api_models.dart';
import 'package:cricpro_flutter/components.dart';
import 'package:cricpro_flutter/models.dart';
import 'package:cricpro_flutter/models/api_response.dart';
import 'package:cricpro_flutter/repositories/cricket_repository.dart';

part 'widgets/player_hero.dart';
part 'widgets/player_tabs.dart';
part 'widgets/player_cards.dart';

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
  int _tab = 0;
  Map<String, dynamic>? _routeArgs;

  String get _playerId {
    final arg = ModalRoute.of(context)?.settings.arguments;
    if (arg is String && arg.isNotEmpty) return arg;
    if (arg is Map && apiString(arg['playerId'] ?? arg['id']).isNotEmpty) {
      return apiString(arg['playerId'] ?? arg['id']);
    }
    return widget.playerId;
  }

  Map<String, dynamic>? get _playerArgs {
    final arg = ModalRoute.of(context)?.settings.arguments;
    if (arg is Map<String, dynamic>) return arg;
    if (arg is Map) return Map<String, dynamic>.from(arg);
    return _routeArgs;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _routeArgs ??= _playerArgs;
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
                  showLogo: true,
                  trailing: [
                    GlowIconButton(
                        icon: Icons.notifications_none_rounded, onTap: () {}),
                    const SizedBox(width: 8),
                    GlowIconButton(
                        icon: Icons.more_vert_rounded, onTap: () {}),
                  ],
                ),
                const SizedBox(height: 18),
                if (_player != null)
                  _ApiPlayerProfile(
                    future: _player!,
                    tab: _tab,
                    ranking: _playerArgs,
                    onTabChanged: (value) => setState(() => _tab = value),
                  )
                else if (fallback != null)
                  _FallbackPlayerCard(player: fallback)
                else
                  const _PlayerStateCard(
                    title: 'No player selected',
                    text:
                        'Open a player from rankings, squads, or scorecard to view the real profile.',
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

