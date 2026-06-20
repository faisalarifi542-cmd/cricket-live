import 'api_match_model.dart';
import '../../core/utils/cricket_helpers.dart';

class ApiPlayerOfMatch {
  final String id;
  final String name;
  final String? imageId;
  final String? imageUrl;

  ApiPlayerOfMatch({
    required this.id,
    required this.name,
    this.imageId,
    this.imageUrl,
  });

  factory ApiPlayerOfMatch.fromJson(Map<String, dynamic> json) {
    return ApiPlayerOfMatch(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      imageId: json['image_id']?.toString(),
      imageUrl: json['image_url']?.toString(),
    );
  }
}

class ApiLatestPerformance {
  final int runs;
  final int wickets;
  final String label;

  ApiLatestPerformance({required this.runs, required this.wickets, required this.label});

  factory ApiLatestPerformance.fromJson(Map<String, dynamic> json) {
    return ApiLatestPerformance(
      runs: json['runs'] ?? 0,
      wickets: json['wickets'] ?? 0,
      label: json['label']?.toString() ?? '',
    );
  }
}

class ApiPowerplayData {
  final int id;
  final double oversFrom;
  final double oversTo;
  final String type;
  final int runsScored;

  ApiPowerplayData({
    required this.id,
    required this.oversFrom,
    required this.oversTo,
    required this.type,
    required this.runsScored,
  });

  factory ApiPowerplayData.fromJson(Map<String, dynamic> json) {
    return ApiPowerplayData(
      id: json['id'] ?? 0,
      oversFrom: (json['overs_from'] is num) ? (json['overs_from'] as num).toDouble() : 0.0,
      oversTo: (json['overs_to'] is num) ? (json['overs_to'] as num).toDouble() : 0.0,
      type: json['type']?.toString() ?? '',
      runsScored: json['runs_scored'] ?? 0,
    );
  }
}

class ApiToss {
  final String winner;
  final String decision;

  ApiToss({required this.winner, required this.decision});

  factory ApiToss.fromJson(Map<String, dynamic> json) {
    return ApiToss(
      winner: json['winner']?.toString() ?? '',
      decision: json['decision']?.toString() ?? '',
    );
  }

  String get displayText => winner.isNotEmpty ? '$winner elected to $decision' : '';
}

class ApiCurrentBatsman {
  final String playerId;
  final String name;
  final int runs;
  final int balls;
  final int fours;
  final int sixes;
  final double strikeRate;
  final bool isBatting;
  final bool isStriker;

  ApiCurrentBatsman({
    required this.playerId,
    required this.name,
    required this.runs,
    required this.balls,
    required this.fours,
    required this.sixes,
    required this.strikeRate,
    required this.isBatting,
    required this.isStriker,
  });

  factory ApiCurrentBatsman.fromJson(Map<String, dynamic> json) {
    return ApiCurrentBatsman(
      playerId: json['player_id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      runs: json['runs'] ?? 0,
      balls: json['balls'] ?? 0,
      fours: json['fours'] ?? 0,
      sixes: json['sixes'] ?? 0,
      strikeRate: (json['strike_rate'] is num) ? (json['strike_rate'] as num).toDouble() : 0.0,
      isBatting: json['is_batting'] ?? false,
      isStriker: json['is_striker'] ?? false,
    );
  }

  String get scoreText => '$runs($balls)';
}

class ApiCurrentBowler {
  final String playerId;
  final String name;
  final int overs;
  final int maidens;
  final int runs;
  final int wickets;
  final double economy;

  ApiCurrentBowler({
    required this.playerId,
    required this.name,
    required this.overs,
    required this.maidens,
    required this.runs,
    required this.wickets,
    required this.economy,
  });

  factory ApiCurrentBowler.fromJson(Map<String, dynamic> json) {
    return ApiCurrentBowler(
      playerId: json['player_id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      overs: json['overs'] ?? 0,
      maidens: json['maidens'] ?? 0,
      runs: json['runs'] ?? 0,
      wickets: json['wickets'] ?? 0,
      economy: (json['economy'] is num) ? (json['economy'] as num).toDouble() : 0.0,
    );
  }

  String get figuresText => '$wickets/$runs';
}

class ApiPartnership {
  final int runs;
  final int balls;

  ApiPartnership({required this.runs, required this.balls});

  factory ApiPartnership.fromJson(Map<String, dynamic> json) {
    return ApiPartnership(
      runs: json['runs'] ?? 0,
      balls: json['balls'] ?? 0,
    );
  }
}

class ApiInningsDetail {
  final int inningsNumber;
  final String battingTeamId;
  final String battingTeam;
  final int runs;
  final int wickets;
  final double overs;
  final double runRate;
  final int? target;
  final double? requiredRate;
  final bool declared;
  final bool followOn;

  ApiInningsDetail({
    required this.inningsNumber,
    required this.battingTeamId,
    required this.battingTeam,
    required this.runs,
    required this.wickets,
    required this.overs,
    required this.runRate,
    this.target,
    this.requiredRate,
    this.declared = false,
    this.followOn = false,
  });

  factory ApiInningsDetail.fromJson(Map<String, dynamic> json) {
    return ApiInningsDetail(
      inningsNumber: json['innings_number'] ?? 0,
      battingTeamId: json['batting_team_id']?.toString() ?? '',
      battingTeam: json['batting_team']?.toString() ?? '',
      runs: json['runs'] ?? 0,
      wickets: json['wickets'] ?? 0,
      overs: (json['overs'] is num) ? (json['overs'] as num).toDouble() : 0.0,
      runRate: (json['run_rate'] is num) ? (json['run_rate'] as num).toDouble() : 0.0,
      target: json['target'],
      requiredRate: (json['required_rate'] is num) ? (json['required_rate'] as num).toDouble() : null,
      declared: json['declared'] ?? false,
      followOn: json['follow_on'] ?? false,
    );
  }

  String get scoreText => '$runs/$wickets (${formatCricketOvers(overs)} ov)';
}

class ApiMatchDetail {
  final String matchId;
  final String seriesId;
  final String seriesName;
  final String matchDesc;
  final String matchFormat;
  final String matchType;
  final String matchNumber;
  final String status;
  final String statusText;
  final ApiTeam team1;
  final ApiTeam team2;
  final ApiVenue venue;
  final DateTime? startTime;
  final DateTime? endTime;
  final ApiToss? toss;
  final String result;
  final String manOfMatch;
  final int currentInnings;
  final int? dayNumber;
  final String? session;
  final List<ApiInningsDetail> innings;
  final List<ApiCurrentBatsman> currentBatsmen;
  final ApiCurrentBowler? currentBowler;
  final double currentRunRate;
  final double requiredRunRate;
  final ApiPartnership? partnership;
  final String? lastWicket;
  final String? recentOvers;
  final int? target;
  final int? remRunsToWin;
  final List<ApiLatestPerformance> latestPerformance;
  final List<ApiPowerplayData> powerplayData;
  final ApiPlayerOfMatch? playerOfMatch;
  final String? matchImageUrl;
  final DateTime? lastUpdated;

  ApiMatchDetail({
    required this.matchId,
    required this.seriesId,
    required this.seriesName,
    required this.matchDesc,
    required this.matchFormat,
    required this.matchType,
    required this.matchNumber,
    required this.status,
    required this.statusText,
    required this.team1,
    required this.team2,
    required this.venue,
    this.startTime,
    this.endTime,
    this.toss,
    required this.result,
    required this.manOfMatch,
    required this.currentInnings,
    this.dayNumber,
    this.session,
    required this.innings,
    required this.currentBatsmen,
    this.currentBowler,
    required this.currentRunRate,
    required this.requiredRunRate,
    this.partnership,
    this.lastWicket,
    this.recentOvers,
    this.target,
    this.remRunsToWin,
    this.latestPerformance = const [],
    this.powerplayData = const [],
    this.playerOfMatch,
    this.matchImageUrl,
    this.lastUpdated,
  });

  factory ApiMatchDetail.fromJson(Map<String, dynamic> json) {
    return ApiMatchDetail(
      matchId: json['match_id']?.toString() ?? '',
      seriesId: json['series_id']?.toString() ?? '',
      seriesName: json['series_name']?.toString() ?? '',
      matchDesc: json['match_desc']?.toString() ?? '',
      matchFormat: json['match_format']?.toString() ?? '',
      matchType: json['match_type']?.toString() ?? '',
      matchNumber: json['match_number']?.toString() ?? '',
      status: json['status']?.toString() ?? '',
      statusText: json['status_text']?.toString() ?? '',
      team1: ApiTeam.fromJson(json['team1'] ?? {}),
      team2: ApiTeam.fromJson(json['team2'] ?? {}),
      venue: ApiVenue.fromJson(json['venue'] ?? {}),
      startTime: json['start_time'] != null ? DateTime.tryParse(json['start_time'].toString()) : null,
      endTime: json['end_time'] != null ? DateTime.tryParse(json['end_time'].toString()) : null,
      toss: json['toss'] != null ? ApiToss.fromJson(json['toss']) : null,
      result: json['result']?.toString() ?? '',
      manOfMatch: json['man_of_match']?.toString() ?? '',
      currentInnings: json['current_innings'] ?? 0,
      dayNumber: json['day_number'],
      session: json['session']?.toString(),
      innings: (json['innings'] as List?)?.map((e) => ApiInningsDetail.fromJson(e)).toList() ?? [],
      currentBatsmen: (json['current_batsmen'] as List?)?.map((e) => ApiCurrentBatsman.fromJson(e)).toList() ?? [],
      currentBowler: json['current_bowler'] != null ? ApiCurrentBowler.fromJson(json['current_bowler']) : null,
      currentRunRate: (json['current_run_rate'] is num) ? (json['current_run_rate'] as num).toDouble() : 0.0,
      requiredRunRate: (json['required_run_rate'] is num) ? (json['required_run_rate'] as num).toDouble() : 0.0,
      partnership: json['partnership'] != null ? ApiPartnership.fromJson(json['partnership']) : null,
      lastWicket: json['last_wicket']?.toString(),
      recentOvers: json['recent_overs']?.toString(),
      target: json['target'],
      remRunsToWin: json['rem_runs_to_win'],
      latestPerformance: (json['latest_performance'] as List?)?.map((e) => ApiLatestPerformance.fromJson(e)).toList() ?? [],
      powerplayData: (json['powerplay_data'] as List?)?.map((e) => ApiPowerplayData.fromJson(e)).toList() ?? [],
      playerOfMatch: json['player_of_match'] != null ? ApiPlayerOfMatch.fromJson(json['player_of_match']) : null,
      matchImageUrl: json['match_image_url']?.toString(),
      lastUpdated: json['last_updated'] != null ? DateTime.tryParse(json['last_updated'].toString()) : null,
    );
  }

  bool get isLive => status == 'live' || status == 'in_progress';
  String get title => '${team1.name} vs ${team2.name}';
}
