class MatchModel {
  final String id;
  final String matchType;
  final String matchNumber;
  final String tournament;
  final String status; // live, finished, upcoming
  final String statusText;
  final TeamScore team1;
  final TeamScore team2;
  final String? result;
  final String? venue;
  final String? time;
  final PlayerOfMatch? playerOfMatch;

  MatchModel({
    required this.id,
    required this.matchType,
    required this.matchNumber,
    required this.tournament,
    required this.status,
    required this.statusText,
    required this.team1,
    required this.team2,
    this.result,
    this.venue,
    this.time,
    this.playerOfMatch,
  });
}

class TeamScore {
  final String name;
  final String shortName;
  final String? score;
  final String? overs;
  final String logoColor;

  TeamScore({
    required this.name,
    required this.shortName,
    this.score,
    this.overs,
    required this.logoColor,
  });
}

class PlayerOfMatch {
  final String name;
  final String score;

  PlayerOfMatch({required this.name, required this.score});
}

class BattingEntry {
  final String name;
  final String dismissal;
  final int runs;
  final int balls;
  final int fours;
  final int sixes;
  final double strikeRate;
  final bool isNotOut;

  BattingEntry({
    required this.name,
    this.dismissal = '',
    required this.runs,
    required this.balls,
    required this.fours,
    required this.sixes,
    required this.strikeRate,
    this.isNotOut = false,
  });
}

class BowlingEntry {
  final String name;
  final double overs;
  final int maidens;
  final int runs;
  final int wickets;
  final double economy;

  BowlingEntry({
    required this.name,
    required this.overs,
    required this.maidens,
    required this.runs,
    required this.wickets,
    required this.economy,
  });
}

class CommentaryEntry {
  final String over;
  final String outcome;
  final int runs;
  final String bowler;
  final String batter;
  final String text;
  final bool isWicket;
  final bool isBoundary;
  final bool isSix;

  CommentaryEntry({
    required this.over,
    required this.outcome,
    required this.runs,
    required this.bowler,
    required this.batter,
    required this.text,
    this.isWicket = false,
    this.isBoundary = false,
    this.isSix = false,
  });
}
