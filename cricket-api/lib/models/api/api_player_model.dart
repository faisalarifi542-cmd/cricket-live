class ApiPlayer {
  final String playerId;
  final String name;
  final String fullName;
  final DateTime? dob;
  final String nationality;
  final String role;
  final String battingStyle;
  final String bowlingStyle;
  final String imageUrl;
  final List<String> teams;
  final String bio;
  final Map<String, dynamic> stats;

  ApiPlayer({
    required this.playerId,
    required this.name,
    required this.fullName,
    this.dob,
    required this.nationality,
    required this.role,
    required this.battingStyle,
    required this.bowlingStyle,
    required this.imageUrl,
    required this.teams,
    required this.bio,
    required this.stats,
  });

  factory ApiPlayer.fromJson(Map<String, dynamic> json) {
    return ApiPlayer(
      playerId: json['player_id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      fullName: json['full_name']?.toString() ?? '',
      dob: json['dob'] != null ? DateTime.tryParse(json['dob'].toString()) : null,
      nationality: json['nationality']?.toString() ?? '',
      role: json['role']?.toString() ?? '',
      battingStyle: json['batting_style']?.toString() ?? '',
      bowlingStyle: json['bowling_style']?.toString() ?? '',
      imageUrl: json['image_url']?.toString() ?? '',
      teams: (json['teams'] as List?)?.map((e) => e.toString()).toList() ?? [],
      bio: json['bio']?.toString() ?? '',
      stats: json['stats'] is Map<String, dynamic> ? json['stats'] : {},
    );
  }

  bool get hasData => name.isNotEmpty || fullName.isNotEmpty;
}
