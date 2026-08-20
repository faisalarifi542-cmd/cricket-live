// M6 PERFORMANCE MEASUREMENT — non-production instrumentation.
//
// Realistic payload fixtures for the Match Details performance scenarios.
// Shapes mirror the backend normalizer exactly:
//   cricket-api/src/providers/cricbuzz/normalizer.js :1605-1678
//     { innings, over, team, teamShort, score, type, label, title, text,
//       isBall, isWicket, isBoundary, isKeyEvent, runs, ballNbr, timestamp }
//
// DELETE THIS DIRECTORY once the measurement milestone is signed off.

/// One normalized commentary delivery, exactly as `/app/live-commentary`
/// returns it after `classifyCommentaryItem`.
Map<String, dynamic> commItem({
  required int innings,
  required double over,
  required int ballNbr,
  required int timestamp,
  String type = 'run',
  int runs = 1,
  String team = 'India',
  String teamShort = 'IND',
  String score = '148/3',
  String? text,
}) {
  const isBall = true;
  final isWicket = type == 'wicket';
  final isBoundary = type == 'four' || type == 'six';
  return <String, dynamic>{
    'innings': innings,
    'over': over.toStringAsFixed(1),
    'team': team,
    'teamShort': teamShort,
    'score': score,
    'type': type,
    'label': switch (type) {
      'wicket' => 'WICKET',
      'six' => 'SIX',
      'four' => 'FOUR',
      'dot' => 'DOT BALL',
      _ => '$runs RUN${runs == 1 ? '' : 'S'}',
    },
    'title': null,
    // Realistic length: real Cricbuzz ball commentary runs 90-220 chars.
    'text': text ??
        'Jasprit Bumrah to Travis Head, $runs run, angled in from wide of '
            'the crease, pushed with soft hands towards the covers and they '
            'scamper through for a comfortable single.',
    'isBall': isBall,
    'isWicket': isWicket,
    'isBoundary': isBoundary,
    'isKeyEvent': isWicket || isBoundary,
    'runs': runs,
    'ballNbr': ballNbr,
    'timestamp': timestamp,
  };
}

/// A non-ball note row (over break / milestone), `isBall: false`.
Map<String, dynamic> commNote({
  required int innings,
  required int timestamp,
  String text = 'Drinks break! India are cruising at this stage, needing '
      'just 42 runs off the last 8 overs with 7 wickets in hand.',
}) =>
    <String, dynamic>{
      'innings': innings,
      'over': null,
      'team': null,
      'teamShort': null,
      'score': null,
      'type': 'note',
      'label': 'DRINKS',
      'title': null,
      'text': text,
      'isBall': false,
      'isWicket': false,
      'isBoundary': false,
      'isKeyEvent': true,
      'runs': null,
      'ballNbr': 0,
      'timestamp': timestamp,
    };

/// Newest-first commentary feed of [count] items, mixing ball types in
/// realistic proportions (~58% runs/dots, 18% dots, 12% four, 6% six, 4%
/// wicket, plus a note every 6th over).
List<Map<String, dynamic>> commentaryFeed(int count, {int innings = 2}) {
  final items = <Map<String, dynamic>>[];
  var ball = count;
  var ts = 1755600000000;
  for (var i = 0; i < count; i++) {
    final over = (ball / 6).floor() + (ball % 6) / 10.0;
    final mod = i % 17;
    final type = switch (mod) {
      0 || 8 => 'four',
      3 => 'six',
      11 => 'wicket',
      1 || 5 || 9 || 13 || 15 => 'dot',
      _ => 'run',
    };
    final runs = switch (type) {
      'four' => 4,
      'six' => 6,
      'dot' || 'wicket' => 0,
      _ => (i % 3) + 1,
    };
    items.add(commItem(
      innings: innings,
      over: over,
      ballNbr: ball,
      timestamp: ts,
      type: type,
      runs: runs,
      score: '${148 - i}/${3 - (i ~/ 40)}',
    ));
    if (i % 36 == 35) {
      items.add(commNote(innings: innings, timestamp: ts - 1));
    }
    ball--;
    ts -= 32000;
  }
  return items;
}

/// `/app/live-commentary` envelope data for the Commentary tab (tab 4).
Map<String, dynamic> liveCommentaryPayload(int count) => <String, dynamic>{
      'items': commentaryFeed(count),
      'source': 'comm',
      'latestOver': 24.4,
      'scoreOver': 24.4,
      'providerLag': false,
      'completeHistory': true,
      'sourceCandidates': const ['comm', 'full-commentary'],
      'cacheStatus': 'fresh',
    };

/// `/match/:id` summary for a LIVE match.
Map<String, dynamic> liveSummary({int runs = 148, int wickets = 3}) =>
    <String, dynamic>{
      'match_id': 'perf-1',
      'status': 'live',
      'state': 'live',
      'match_format': 'T20',
      'match_type': 'T20',
      'series_name': 'ICC Champions Trophy 2026',
      'match_desc': '2nd Semi-Final',
      'venue': {'name': 'Wankhede Stadium', 'city': 'Mumbai'},
      'status_text': 'India need 42 runs in 48 balls',
      'team1': {
        'name': 'India',
        'short': 'IND',
        'logo_url': '',
        'innings': [
          {'runs': runs, 'wickets': wickets, 'overs': '24.4'}
        ],
      },
      'team2': {
        'name': 'Australia',
        'short': 'AUS',
        'logo_url': '',
        'innings': [
          {'runs': 189, 'wickets': 7, 'overs': '20.0'}
        ],
      },
    };

/// Terminal (completed) `/match/:id` summary.
Map<String, dynamic> completedSummary() {
  final data = liveSummary(runs: 191, wickets: 5);
  data['status'] = 'completed';
  data['state'] = 'completed';
  data['status_text'] = 'India won by 5 wickets';
  return data;
}

/// `/match/:id/live-center` payload with current batters/bowler/recent balls.
Map<String, dynamic> liveCenterPayload({int commentaryCount = 12}) =>
    <String, dynamic>{
      'match_state': 'live',
      'status': 'live',
      'current_batters': [
        {
          'name': 'Shubman Gill',
          'runs': '64',
          'balls': '41',
          'fours': '6',
          'sixes': '2',
          'strike_rate': '156.09',
          'is_striker': true,
        },
        {
          'name': 'Hardik Pandya',
          'runs': '23',
          'balls': '14',
          'fours': '1',
          'sixes': '1',
          'strike_rate': '164.28',
        },
      ],
      'current_bowler': {
        'name': 'Pat Cummins',
        'overs': '3.4',
        'maidens': '0',
        'runs': '31',
        'wickets': '1',
        'economy': '8.45',
      },
      'partnership': {'runs': '58', 'balls': '34'},
      'last_wicket':
          'Virat Kohli 45(28) c Maxwell b Zampa - 90/3 in 12.4 ov',
      'recent_balls': [
        {'over': '24', 'ball': '1', 'value': '1', 'type': 'run'},
        {'over': '24', 'ball': '2', 'value': '4', 'type': 'four'},
        {'over': '24', 'ball': '3', 'value': '0', 'type': 'dot'},
        {'over': '24', 'ball': '4', 'value': '6', 'type': 'six'},
      ],
      'commentary': commentaryFeed(commentaryCount),
    };

/// `/match/:id/scorecard` payload with a full innings of batting + bowling.
Map<String, dynamic> scorecardPayload() => <String, dynamic>{
      'curr_bat_team_id': '1',
      'innings': [
        {
          'teamName': 'Australia',
          'teamShort': 'AUS',
          'batting_team_id': '2',
          'runs': 189,
          'wickets': 7,
          'overs': '20.0',
          'batting': [
            for (var i = 0; i < 11; i++)
              {
                'name': 'AUS Batter $i',
                'runs': '${40 - i * 3}',
                'balls': '${28 - i}',
                'fours': '${3 - (i % 3)}',
                'sixes': '${i % 2}',
                'strike_rate': '${140 - i * 4}.5',
                'dismissal': i < 7 ? 'c Rahul b Bumrah' : '',
                'is_out': i < 7,
              }
          ],
          'bowling': [
            for (var i = 0; i < 6; i++)
              {
                'name': 'IND Bowler $i',
                'overs': '4',
                'maidens': '0',
                'runs': '${28 + i}',
                'wickets': '${2 - (i % 3)}',
                'economy': '${7 + i}.2',
              }
          ],
        },
        {
          'teamName': 'India',
          'teamShort': 'IND',
          'batting_team_id': '1',
          'runs': 148,
          'wickets': 3,
          'overs': '24.4',
          'batting': [
            for (var i = 0; i < 11; i++)
              {
                'name': 'IND Batter $i',
                'runs': '${64 - i * 5}',
                'balls': '${41 - i * 2}',
                'fours': '${6 - (i % 4)}',
                'sixes': '${i % 3}',
                'strike_rate': '${156 - i * 5}.0',
                'dismissal': i < 3 ? 'c Maxwell b Zampa' : '',
                'is_out': i < 3,
              }
          ],
          'bowling': [
            for (var i = 0; i < 6; i++)
              {
                'name': 'AUS Bowler $i',
                'overs': '4',
                'maidens': '0',
                'runs': '${31 + i}',
                'wickets': '${1 + (i % 2)}',
                'economy': '${8 + i}.4',
              }
          ],
        },
      ],
    };

/// `/match/:id/overs` payload — 20 overs of ball chips.
Map<String, dynamic> oversPayload({int overCount = 20}) => <String, dynamic>{
      'overs': [
        for (var i = overCount; i > 0; i--)
          {
            'over': '$i',
            'runs': '${(i % 7) + 2}',
            'wickets': '${i % 2}',
            'balls': const ['1', '4', '0', '6', 'W', '1'],
            'bowler': 'Bowler ${i % 5}',
            'score': '${148 - i * 6}/${3 - (i ~/ 8)}',
          }
      ],
      'recent_overs': const ['1', '4', '0', '6', 'W', '1'],
      'latest_performance': const [],
    };

/// `/match/:id/squads` payload — two 15-player squads.
Map<String, dynamic> squadsPayload() => <String, dynamic>{
      'team1': {
        'name': 'India',
        'players': [
          for (var i = 0; i < 15; i++)
            {
              'name': 'IND Player $i',
              'role': i == 0 ? 'Batsman (C)' : 'Bowler',
              'is_wicketkeeper': i == 3,
              'image_url': '',
            }
        ],
      },
      'team2': {
        'name': 'Australia',
        'players': [
          for (var i = 0; i < 15; i++)
            {
              'name': 'AUS Player $i',
              'role': i == 0 ? 'Batsman (C)' : 'Bowler',
              'is_wicketkeeper': i == 3,
              'image_url': '',
            }
        ],
      },
    };
