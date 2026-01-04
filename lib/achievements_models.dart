// lib/achievements_models.dart
class AchievementDef {
  final String id;
  final String title;
  final String description;
  final int threshold;
  final String scope; // "global" | "group"
  final String? groupName;

  const AchievementDef({
    required this.id,
    required this.title,
    required this.description,
    required this.threshold,
    required this.scope,
    this.groupName,
  });
}

class AchievementUnlocked {
  final AchievementDef def;
  final DateTime unlockedAt;

  AchievementUnlocked({required this.def, required this.unlockedAt});
}
