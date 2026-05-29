class ApiTeamDetail {
  final String teamId;
  final String name;
  final String shortName;
  final String logoUrl;
  final String country;
  final List<String> players;

  ApiTeamDetail({
    required this.teamId,
    required this.name,
    required this.shortName,
    required this.logoUrl,
    required this.country,
    required this.players,
  });

  factory ApiTeamDetail.fromJson(Map<String, dynamic> json) {
    return ApiTeamDetail(
      teamId: json['team_id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      shortName: json['short_name']?.toString() ?? '',
      logoUrl: json['logo_url']?.toString() ?? '',
      country: json['country']?.toString() ?? '',
      players: (json['players'] as List?)?.map((e) => e.toString()).toList() ?? [],
    );
  }

  bool get hasData => name.isNotEmpty;
}
