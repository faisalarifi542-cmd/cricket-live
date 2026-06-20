import '../models/match_model.dart';
import '../models/news_model.dart';
import '../models/video_model.dart';
import '../models/series_model.dart';
import '../models/ranking_model.dart';

class MockData {
  static List<MatchModel> get heroMatches => [
    MatchModel(
      id: '1',
      matchType: 'T20',
      matchNumber: '63rd Match',
      tournament: 'Premier League 2026',
      status: 'finished',
      statusText: 'Finished',
      team1: TeamScore(name: 'Sunrisers Hyderabad', shortName: 'SRH', score: '181/5', overs: '19.0', logoColor: 'FF6B00'),
      team2: TeamScore(name: 'Chennai Super Kings', shortName: 'CSK', score: '180/7', overs: '20.0', logoColor: 'FFCC00'),
      result: 'SRH won by 5 wickets',
      playerOfMatch: PlayerOfMatch(name: 'Ishan Kishan', score: '64* (45)'),
    ),
    MatchModel(
      id: '2',
      matchType: 'T20',
      matchNumber: '62nd Match',
      tournament: 'Premier League 2026',
      status: 'finished',
      statusText: 'Finished',
      team1: TeamScore(name: 'Mumbai Indians', shortName: 'MI', score: '195/4', overs: '20.0', logoColor: '004BA0'),
      team2: TeamScore(name: 'Royal Challengers', shortName: 'RCB', score: '178/8', overs: '20.0', logoColor: 'EC1C24'),
      result: 'MI won by 17 runs',
      playerOfMatch: PlayerOfMatch(name: 'Rohit Sharma', score: '78 (52)'),
    ),
    MatchModel(
      id: '3',
      matchType: 'T20',
      matchNumber: '61st Match',
      tournament: 'Premier League 2026',
      status: 'finished',
      statusText: 'Finished',
      team1: TeamScore(name: 'Rajasthan Royals', shortName: 'RR', score: '165/6', overs: '20.0', logoColor: 'EA1A85'),
      team2: TeamScore(name: 'Delhi Capitals', shortName: 'DC', score: '152/9', overs: '20.0', logoColor: '004C93'),
      result: 'RR won by 13 runs',
      playerOfMatch: PlayerOfMatch(name: 'Sanju Samson', score: '71 (48)'),
    ),
  ];

  static List<MatchModel> get upcomingMatches => [
    MatchModel(
      id: '4',
      matchType: 'T20',
      matchNumber: '64th Match',
      tournament: 'IPL 2026',
      status: 'upcoming',
      statusText: '7:30 PM',
      team1: TeamScore(name: 'Mumbai Indians', shortName: 'MI', logoColor: '004BA0'),
      team2: TeamScore(name: 'Rajasthan Royals', shortName: 'RR', logoColor: 'EA1A85'),
      venue: 'Wankhede Stadium, Mumbai',
      time: '7:30 PM',
    ),
    MatchModel(
      id: '5',
      matchType: 'T20',
      matchNumber: '65th Match',
      tournament: 'IPL 2026',
      status: 'upcoming',
      statusText: '7:30 PM',
      team1: TeamScore(name: 'Royal Challengers', shortName: 'RCB', logoColor: 'EC1C24'),
      team2: TeamScore(name: 'Kolkata Knight Riders', shortName: 'KKR', logoColor: '3A225D'),
      venue: 'M. Chinnaswamy Stadium, Bengaluru',
      time: '7:30 PM',
    ),
    MatchModel(
      id: '6',
      matchType: 'T20',
      matchNumber: '66th Match',
      tournament: 'IPL 2026',
      status: 'upcoming',
      statusText: '3:30 PM',
      team1: TeamScore(name: 'Delhi Capitals', shortName: 'DC', logoColor: '004C93'),
      team2: TeamScore(name: 'Lucknow Super Giants', shortName: 'LSG', logoColor: '00AEEF'),
      venue: 'Arun Jaitley Stadium, Delhi',
      time: '3:30 PM',
    ),
    MatchModel(
      id: '7',
      matchType: 'T20',
      matchNumber: '67th Match',
      tournament: 'IPL 2026',
      status: 'upcoming',
      statusText: '7:30 PM',
      team1: TeamScore(name: 'Punjab Kings', shortName: 'PBKS', logoColor: 'ED1B24'),
      team2: TeamScore(name: 'Gujarat Titans', shortName: 'GT', logoColor: '1C1C2B'),
      venue: 'IS Bindra Stadium, Mohali',
      time: '7:30 PM',
    ),
  ];

  static List<BattingEntry> get srhBatting => [
    BattingEntry(name: 'Abhishek Sharma', runs: 42, balls: 21, fours: 4, sixes: 3, strikeRate: 200.0),
    BattingEntry(name: 'Travis Head', runs: 31, balls: 20, fours: 3, sixes: 1, strikeRate: 155.0),
    BattingEntry(name: 'Ishan Kishan (wk)', runs: 64, balls: 45, fours: 5, sixes: 3, strikeRate: 142.2, isNotOut: true),
    BattingEntry(name: 'Aiden Markram', runs: 25, balls: 18, fours: 2, sixes: 1, strikeRate: 138.9),
    BattingEntry(name: 'Heinrich Klaasen', runs: 9, balls: 6, fours: 1, sixes: 0, strikeRate: 150.0),
    BattingEntry(name: 'Abdul Samad', runs: 6, balls: 3, fours: 0, sixes: 1, strikeRate: 200.0, isNotOut: true),
  ];

  static List<BowlingEntry> get cskBowling => [
    BowlingEntry(name: 'T. Deshpande', overs: 4, maidens: 0, runs: 32, wickets: 3, economy: 8.00),
    BowlingEntry(name: 'M. Theekshana', overs: 4, maidens: 0, runs: 33, wickets: 1, economy: 8.25),
    BowlingEntry(name: 'R. Jadeja', overs: 4, maidens: 0, runs: 28, wickets: 0, economy: 7.00),
    BowlingEntry(name: 'M. Pathirana', overs: 4, maidens: 0, runs: 42, wickets: 1, economy: 10.50),
    BowlingEntry(name: 'R. Ashwin', overs: 3, maidens: 0, runs: 26, wickets: 0, economy: 8.66),
  ];

  static List<BattingEntry> get cskBatting => [
    BattingEntry(name: 'Ruturaj Gaikwad (c)', runs: 55, balls: 38, fours: 6, sixes: 2, strikeRate: 144.7),
    BattingEntry(name: 'Devon Conway', runs: 32, balls: 25, fours: 3, sixes: 1, strikeRate: 128.0),
    BattingEntry(name: 'Shivam Dube', runs: 28, balls: 18, fours: 2, sixes: 2, strikeRate: 155.5),
    BattingEntry(name: 'R. Jadeja', runs: 22, balls: 16, fours: 1, sixes: 1, strikeRate: 137.5),
    BattingEntry(name: 'MS Dhoni (wk)', runs: 18, balls: 14, fours: 1, sixes: 1, strikeRate: 128.5),
    BattingEntry(name: 'M. Ali', runs: 12, balls: 10, fours: 1, sixes: 0, strikeRate: 120.0),
    BattingEntry(name: 'R. Ashwin', runs: 5, balls: 6, fours: 0, sixes: 0, strikeRate: 83.3, isNotOut: true),
  ];

  static List<BowlingEntry> get srhBowling => [
    BowlingEntry(name: 'B. Kumar', overs: 4, maidens: 0, runs: 30, wickets: 2, economy: 7.50),
    BowlingEntry(name: 'T. Natarajan', overs: 4, maidens: 0, runs: 38, wickets: 1, economy: 9.50),
    BowlingEntry(name: 'Abhishek Sharma', overs: 2, maidens: 0, runs: 18, wickets: 0, economy: 9.00),
    BowlingEntry(name: 'Aiden Markram', overs: 4, maidens: 0, runs: 35, wickets: 2, economy: 8.75),
    BowlingEntry(name: 'W. Sundar', overs: 4, maidens: 0, runs: 32, wickets: 1, economy: 8.00),
    BowlingEntry(name: 'Umran Malik', overs: 2, maidens: 0, runs: 27, wickets: 1, economy: 13.50),
  ];

  static List<CommentaryEntry> get commentary => [
    CommentaryEntry(over: '19.0', outcome: '1', runs: 1, bowler: 'T. Deshpande', batter: 'Ishan Kishan', text: 'Full and on middle, Ishan Kishan drives to long on for a single.'),
    CommentaryEntry(over: '18.6', outcome: '6', runs: 6, bowler: 'T. Deshpande', batter: 'Abdul Samad', text: 'Short and outside off, pulled away over deep square leg for a SIX!', isSix: true),
    CommentaryEntry(over: '18.5', outcome: '1', runs: 1, bowler: 'T. Deshpande', batter: 'Abdul Samad', text: 'On a length, guided to third man for one.'),
    CommentaryEntry(over: '18.4', outcome: '1', runs: 1, bowler: 'T. Deshpande', batter: 'Ishan Kishan', text: 'Full toss, slammed to long on for a single.'),
    CommentaryEntry(over: '18.3', outcome: '4', runs: 4, bowler: 'T. Deshpande', batter: 'Ishan Kishan', text: 'Good length, punched through covers for a FOUR!', isBoundary: true),
    CommentaryEntry(over: '18.2', outcome: '0', runs: 0, bowler: 'T. Deshpande', batter: 'Ishan Kishan', text: 'Back of a length, defended to point.'),
  ];

  static List<NewsModel> get news => [
    NewsModel(id: '1', storyType: 'Match Report', headline: "Kishan's masterclass powers SRH to thrilling 5-wicket win", publishedTime: '2h ago', context: 'IPL 2026'),
    NewsModel(id: '2', storyType: 'Analysis', headline: 'Where CSK lost the game: Key moments breakdown', publishedTime: '5h ago', context: 'IPL 2026'),
    NewsModel(id: '3', storyType: 'News', headline: 'IPL 2026: Points Table After 63 Matches', publishedTime: '6h ago', context: 'IPL 2026'),
    NewsModel(id: '4', storyType: 'Features', headline: 'The rise of Abhishek Sharma: A star in the making', publishedTime: '1d ago', context: 'IPL 2026'),
  ];

  static List<VideoModel> get videos => [
    VideoModel(id: '1', title: 'SRH vs CSK Highlights', subtitle: 'Match 63 \u2022 IPL 2026', duration: '06:45'),
    VideoModel(id: '2', title: "Ishan Kishan's Match-winning 64*", subtitle: 'Top knocks \u2022 IPL 2026', duration: '04:12'),
    VideoModel(id: '3', title: 'All 12 Wickets - SRH vs CSK', subtitle: 'Wicket Reel \u2022 IPL 2026', duration: '05:08'),
    VideoModel(id: '4', title: 'Post Match Presentation', subtitle: 'SRH vs CSK \u2022 IPL 2026', duration: '02:16'),
  ];

  static List<SeriesModel> get featuredSeries => [
    SeriesModel(id: '1', title: 'Premier League 2026', type: 'T20 League', dateRange: '22 Mar \u2013 31 May', gradientIndex: 0),
    SeriesModel(id: '2', title: 'National T20 Cup 2026', type: 'T20 Cup', dateRange: '02 May \u2013 14 May', gradientIndex: 1),
    SeriesModel(id: '3', title: 'ENG-W vs NZ-W Tour', type: 'Women Tour', dateRange: '10 May \u2013 25 May', gradientIndex: 2),
    SeriesModel(id: '4', title: 'PAK vs WI T20I Series', type: 'T20I Series', dateRange: '01 Jun \u2013 10 Jun', gradientIndex: 3),
  ];

  static List<SeriesModel> get allSeries => [
    SeriesModel(id: '10', title: 'INDIA TOUR OF ENGLAND 2026', type: 'Test Series', dateRange: '20 Jun \u2013 04 Aug 2026', gradientIndex: 0),
    SeriesModel(id: '11', title: 'AUSTRALIA TOUR OF PAKISTAN 2026', type: 'ODI Series', dateRange: '10 Jul \u2013 28 Jul 2026', gradientIndex: 1),
    SeriesModel(id: '12', title: 'ICC T20 WORLD CUP 2026', type: 'T20 World Cup', dateRange: '12 Feb \u2013 15 Mar 2026', gradientIndex: 2),
    SeriesModel(id: '13', title: 'SOUTH AFRICA TOUR OF WEST INDIES', type: 'T20 Series', dateRange: '01 Aug \u2013 12 Aug 2026', gradientIndex: 3),
  ];

  static List<RankingModel> get battingRankings => [
    RankingModel(rank: 1, name: 'Shubman Gill', team: 'GT', country: 'India', rating: 895, change: 2, teamShort: 'GT'),
    RankingModel(rank: 2, name: 'Babar Azam', team: 'PAK', country: 'Pakistan', rating: 876, change: -1, teamShort: 'PAK'),
    RankingModel(rank: 3, name: 'Virat Kohli', team: 'RCB', country: 'India', rating: 861, change: 0, teamShort: 'RCB'),
    RankingModel(rank: 4, name: 'Ruturaj Gaikwad', team: 'CSK', country: 'India', rating: 833, change: 1, teamShort: 'CSK'),
    RankingModel(rank: 5, name: 'Jos Buttler', team: 'RR', country: 'England', rating: 812, change: -1, teamShort: 'RR'),
  ];

  static List<RankingModel> get bowlingRankings => [
    RankingModel(rank: 1, name: 'Jasprit Bumrah', team: 'MI', country: 'India', rating: 901, change: 0, teamShort: 'MI'),
    RankingModel(rank: 2, name: 'Pat Cummins', team: 'AUS', country: 'Australia', rating: 878, change: 1, teamShort: 'AUS'),
    RankingModel(rank: 3, name: 'Rashid Khan', team: 'GT', country: 'Afghanistan', rating: 855, change: -1, teamShort: 'GT'),
    RankingModel(rank: 4, name: 'Kagiso Rabada', team: 'PBKS', country: 'South Africa', rating: 842, change: 2, teamShort: 'PBKS'),
    RankingModel(rank: 5, name: 'Yuzvendra Chahal', team: 'RR', country: 'India', rating: 830, change: 0, teamShort: 'RR'),
  ];
}
