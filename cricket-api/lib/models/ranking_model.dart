class RankingModel {
  final int rank;
  final String name;
  final String team;
  final String country;
  final int rating;
  final int change; // positive = up, negative = down, 0 = no change
  final String teamShort;

  RankingModel({
    required this.rank,
    required this.name,
    required this.team,
    required this.country,
    required this.rating,
    required this.change,
    required this.teamShort,
  });
}
