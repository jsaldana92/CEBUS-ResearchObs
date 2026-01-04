// lib/achievements_service.dart
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'achievements_models.dart';

class AchievementsService {
  static const _kStatsKey = 'achv_stats_v1';
  static const _kUnlockedKey = 'achv_unlocked_v1';
  static const _kHistoryKey = 'achv_history_v1';

// NEW: cancel-near-complete “fail” achievements (the only non-completion exception)
  static const _kFailStatsKey = 'achv_fail_stats_v1';
  static const _kFailUnlockedKey = 'achv_fail_unlocked_v1';
  static const _kFailHistoryKey = 'achv_fail_history_v1';

  // ---- Public read API (for “View Achievements” page later) ----
  static Future<List<String>> listObservers() async {
    final prefs = await SharedPreferences.getInstance();

    final a = _readMapJson(prefs.getString(_kStatsKey));
    final b = _readMapJson(prefs.getString(_kFailStatsKey));

    final set = <String>{};
    set.addAll(a.keys.map((e) => e.toString()));
    set.addAll(b.keys.map((e) => e.toString()));

    final list = set.toList()..sort();
    return list;
  }


  static Future<Map<String, dynamic>> getObserverStats(String observer) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kStatsKey);
    if (raw == null || raw.isEmpty) return {'total': 0, 'groups': <String, int>{}, 'locations': <String, int>{}};
    final j = jsonDecode(raw);
    if (j is! Map) return {'total': 0, 'groups': <String, int>{}, 'locations': <String, int>{}};
    final o = j[observer];
    if (o is! Map) return {'total': 0, 'groups': <String, int>{}, 'locations': <String, int>{}};
    final total = (o['total'] is num) ? (o['total'] as num).toInt() : 0;
    final groupsRaw = o['groups'];
    final groups = <String, int>{};
    if (groupsRaw is Map) {
      for (final entry in groupsRaw.entries) {
        final k = entry.key.toString();
        final v = entry.value;
        groups[k] = (v is num) ? v.toInt() : 0;
      }
    }
    final locationsRaw = o['locations'];
    final locations = <String, int>{};
    if (locationsRaw is Map) {
      for (final entry in locationsRaw.entries) {
        final k = entry.key.toString();
        final v = entry.value;
        locations[k] = (v is num) ? v.toInt() : 0;
      }
    }

    return {'total': total, 'groups': groups, 'locations': locations};

  }

  static Future<Map<String, String>> getObserverHistory(String observer) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kHistoryKey);
    if (raw == null || raw.isEmpty) return {};
    final j = jsonDecode(raw);
    if (j is! Map) return {};
    final o = j[observer];
    if (o is! Map) return {};
    return o.map<String, String>((k, v) => MapEntry(k.toString(), v.toString()));
  }

  static Future<Set<String>> getObserverUnlocked(String observer) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kUnlockedKey);
    if (raw == null || raw.isEmpty) return {};
    final j = jsonDecode(raw);
    if (j is! Map) return {};
    final arr = j[observer];
    if (arr is! List) return {};
    return arr.map((e) => e.toString()).toSet();
  }

  static String? _normLocation(String? location) {
    final raw = (location ?? '').trim().toLowerCase();
    if (raw.isEmpty) return null;
    if (raw.startsWith('in')) return 'inside';
    if (raw.startsWith('out')) return 'outside';
    return null;
  }

  static int? _normTempF(num? tempF) {
    if (tempF == null) return null;

    // If it's already an int (or effectively an int), keep it.
    final asDouble = tempF.toDouble();
    final asInt = asDouble.round();
    final diff = (asDouble - asInt).abs();

    // Only accept if it's basically an integer (e.g., 98.0)
    if (diff > 0.0001) return null;

    return asInt;
  }



  // ---- Award API (canonical) ----
  static Future<List<AchievementUnlocked>> awardIfCompleted({
    required String observerName,
    required String groupName,
    required bool isValidComplete,
    DateTime? completedAt,

    // NEW: used only at valid completion (no drift)
    num? temperatureF,
    String? location, // expected: "inside" or "outside" (we’ll normalize)
  }) async {
    if (!isValidComplete) return [];

    final now = completedAt ?? DateTime.now();
    final prefs = await SharedPreferences.getInstance();

    // Load JSON blobs
    final statsJ = _readMapJson(prefs.getString(_kStatsKey));
    final unlockedJ = _readMapJson(prefs.getString(_kUnlockedKey));
    final historyJ = _readMapJson(prefs.getString(_kHistoryKey));

    // Ensure observer nodes exist
    final obsStats = (statsJ[observerName] is Map) ? (statsJ[observerName] as Map) : <String, dynamic>{};
    final groups = (obsStats['groups'] is Map) ? (obsStats['groups'] as Map) : <String, dynamic>{};
    final locations = (obsStats['locations'] is Map) ? (obsStats['locations'] as Map) : <String, dynamic>{};

    final total = (obsStats['total'] is num) ? (obsStats['total'] as num).toInt() : 0;
    final newTotal = total + 1;

    final groupCount = (groups[groupName] is num) ? (groups[groupName] as num).toInt() : 0;
    final newGroupCount = groupCount + 1;

    // Normalize location to "inside" | "outside" if provided
    final loc = _normLocation(location);
    final locCount = (loc != null && locations[loc] is num) ? (locations[loc] as num).toInt() : 0;
    final newLocCount = (loc != null) ? (locCount + 1) : null;


    // Write back updated counts
    obsStats['total'] = newTotal;
    groups[groupName] = newGroupCount;
    obsStats['groups'] = groups;

    if (loc != null && newLocCount != null) {
      locations[loc] = newLocCount;
      obsStats['locations'] = locations;
    }

    statsJ[observerName] = obsStats;


    // Unlocked set
    final unlockedArr = (unlockedJ[observerName] is List) ? (unlockedJ[observerName] as List) : <dynamic>[];
    final unlockedSet = unlockedArr.map((e) => e.toString()).toSet();

    // History map
    final hist = (historyJ[observerName] is Map) ? (historyJ[observerName] as Map) : <String, dynamic>{};

    // Determine newly unlocked achievements
    final defs = _catalogFor(groupName);
    final tempInt = _normTempF(temperatureF); // e.g., 38.2 -> 38 (only for matching special temps)

    final newlyUnlocked = <AchievementUnlocked>[];

    for (final def in defs) {
      final reached = () {
        switch (def.scope) {
          case 'global':
            return newTotal >= def.threshold;

          case 'group':
            return (def.groupName == groupName) && (newGroupCount >= def.threshold);

          case 'temp':
          // threshold stores the *temperature value* (38, 40, 42, 96, 98, 100)
            return (tempInt != null) && (tempInt == def.threshold);

          case 'location':
          // groupName field stores "inside" or "outside" for location achievements
            if (loc == null || newLocCount == null) return false;
            return (def.groupName == loc) && (newLocCount >= def.threshold);

          default:
            return false;
        }
      }();

      if (!reached) continue;


      if (unlockedSet.contains(def.id)) continue;

      // Unlock it
      unlockedSet.add(def.id);
      hist[def.id] = now.toIso8601String();
      newlyUnlocked.add(AchievementUnlocked(def: def, unlockedAt: now));
    }

    // Persist all three stores together
    unlockedJ[observerName] = unlockedSet.toList()..sort();
    historyJ[observerName] = hist;

    await prefs.setString(_kStatsKey, jsonEncode(statsJ));
    await prefs.setString(_kUnlockedKey, jsonEncode(unlockedJ));
    await prefs.setString(_kHistoryKey, jsonEncode(historyJ));

    return newlyUnlocked;
  }


  // ---- Award API (canonical, CANCEL EXCEPTION) ----
// This is the ONLY non-completion achievement path.
// Rule: only count cancels that have at least one timestamp at 27:XX.
  static Future<List<AchievementUnlocked>> awardIfCancelledNearComplete({
    required String observerName,
    required bool isCancelledNearComplete, // true only if 27:XX exists
    DateTime? cancelledAt,
  }) async {
    if (!isCancelledNearComplete) return [];

    final now = cancelledAt ?? DateTime.now();
    final prefs = await SharedPreferences.getInstance();

    // Load fail JSON blobs
    final statsJ = _readMapJson(prefs.getString(_kFailStatsKey));
    final unlockedJ = _readMapJson(prefs.getString(_kFailUnlockedKey));
    final historyJ = _readMapJson(prefs.getString(_kFailHistoryKey));

    // Ensure observer node
    final obsStats = (statsJ[observerName] is Map) ? (statsJ[observerName] as Map) : <String, dynamic>{};
    final totalFails = (obsStats['total'] is num) ? (obsStats['total'] as num).toInt() : 0;
    final newTotalFails = totalFails + 1;

    obsStats['total'] = newTotalFails;
    statsJ[observerName] = obsStats;

    // Unlocked set
    final unlockedArr = (unlockedJ[observerName] is List) ? (unlockedJ[observerName] as List) : <dynamic>[];
    final unlockedSet = unlockedArr.map((e) => e.toString()).toSet();

    // History map
    final hist = (historyJ[observerName] is Map) ? (historyJ[observerName] as Map) : <String, dynamic>{};

    // Determine newly unlocked fail achievements
    final defs = _failCatalog();
    final newlyUnlocked = <AchievementUnlocked>[];

    for (final def in defs) {
      // Fail achievements are global and based on fail total
      final reached = newTotalFails >= def.threshold;
      if (!reached) continue;

      if (unlockedSet.contains(def.id)) continue;

      unlockedSet.add(def.id);
      hist[def.id] = now.toIso8601String();
      newlyUnlocked.add(AchievementUnlocked(def: def, unlockedAt: now));
    }

    // Persist together
    unlockedJ[observerName] = unlockedSet.toList()..sort();
    historyJ[observerName] = hist;

    await prefs.setString(_kFailStatsKey, jsonEncode(statsJ));
    await prefs.setString(_kFailUnlockedKey, jsonEncode(unlockedJ));
    await prefs.setString(_kFailHistoryKey, jsonEncode(historyJ));

    return newlyUnlocked;
  }

  static Map<String, dynamic> _readMapJson(String? raw) {
    if (raw == null || raw.isEmpty) return <String, dynamic>{};
    try {
      final j = jsonDecode(raw);
      if (j is Map) return j.map((k, v) => MapEntry(k.toString(), v));
    } catch (_) {}
    return <String, dynamic>{};
  }

  static String _safeGroupId(String groupName) {
    return groupName.trim().replaceAll(RegExp(r'\s+'), '_').replaceAll(RegExp(r'[^A-Za-z0-9_]+'), '');
  }

  static List<AchievementDef> _failCatalog() {
    // “fun poke” achievements for cancelling right near completion
    const thresholds = [1, 5, 10, 20];

    final titles = <int, String>{
      1: "Maybe next time champ...",
      5: "You tried... I think",
      10: "No one remembers second place",
      20: "Real commitment issues",
    };

    final desc = <int, String>{
      1: "Cancelled an observation at 27 mins. Ouch.",
      5: "Cancelled 5 observations at 27 mins. Pattern forming.",
      10: "Cancelled 10 observations at 27 mins. This is a lifestyle.",
      20: "Cancelled 20 observations at 27 mins. Respectfully: why.",
    };

    final defs = <AchievementDef>[];
    for (final t in thresholds) {
      defs.add(AchievementDef(
        id: 'global_fail_total_$t',
        title: titles[t] ?? 'Fails: $t',
        description: desc[t] ?? 'Cancelled $t near-complete observations.',
        threshold: t,
        scope: 'fail', // NEW scope string; only used by cancel API
      ));
    }
    return defs;
  }

  static Future<Map<String, dynamic>> getObserverFailStats(String observer) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kFailStatsKey);
    if (raw == null || raw.isEmpty) return {'total': 0};
    final j = jsonDecode(raw);
    if (j is! Map) return {'total': 0};
    final o = j[observer];
    if (o is! Map) return {'total': 0};
    final total = (o['total'] is num) ? (o['total'] as num).toInt() : 0;
    return {'total': total};
  }

  static Future<Map<String, String>> getObserverFailHistory(String observer) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kFailHistoryKey);
    if (raw == null || raw.isEmpty) return {};
    final j = jsonDecode(raw);
    if (j is! Map) return {};
    final o = j[observer];
    if (o is! Map) return {};
    return o.map<String, String>((k, v) => MapEntry(k.toString(), v.toString()));
  }

  static Future<Set<String>> getObserverFailUnlocked(String observer) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kFailUnlockedKey);
    if (raw == null || raw.isEmpty) return {};
    final j = jsonDecode(raw);
    if (j is! Map) return {};
    final arr = j[observer];
    if (arr is! List) return {};
    return arr.map((e) => e.toString()).toSet();
  }

  // Public wrappers so UI can display the same titles/descriptions as the service catalog.
  static List<AchievementDef> catalogForGroup(String groupName) => _catalogFor(groupName);

  static List<AchievementDef> failCatalog() => _failCatalog();



  static List<AchievementDef> _catalogFor(String groupName) {
    final gId = _safeGroupId(groupName);

    // Halo-ish quirky names (we can tune later)
    const globalThresholds = [1, 25, 50, 100, 200, 400, 800, 1000];
    final globalTitles = <int, String>{
      1: 'The first of many...',
      25: "Don't forget to blink",
      50: 'It gets better the more you do it',
      100: "Hope you like standing",
      200: 'Monkey creeper',
      400: 'Big brother is watching',
      800: 'I hope this is for a project',
      1000: 'Please graduate soon...',
    };

    const groupThresholds = [1, 10, 20, 50, 100, 200, 400, 800, 1000];

    final defs = <AchievementDef>[];

    for (final t in globalThresholds) {
      defs.add(AchievementDef(
        id: 'global_total_$t',
        title: globalTitles[t] ?? 'Total $t',
        description: t == 1
            ? 'Collected your first observation.'
            : 'Collected $t observations.',
        threshold: t,
        scope: 'global',
      ));
    }

    final groupTitles = <int, String>{
      1: 'Hello, $groupName',
      10: '$groupName Regular',
      20: '$groupName Local',
      50: '$groupName Friend',
      100: '$groupName Creeper',
      200: '$groupName Biased',
      400: '$groupName Fanboy',
      800: '$groupName Glazer',
      1000: '$groupName Stalker',
    };

    for (final t in groupThresholds) {
      defs.add(AchievementDef(
        id: 'group_${gId}_$t',
        title: groupTitles[t] ?? '$groupName: $t',
        description: t == 1
            ? 'Collected your first $groupName observation.'
            : 'Collected $t $groupName observations.',
        threshold: t,
        scope: 'group',
        groupName: groupName,
      ));
    }

    // --- Temperature “special day” achievements (valid completion only) ---
    const tempSpecials = [38, 40, 42, 96, 98, 100];
    final tempTitles = <int, String>{
      38: 'Should have done an inside obs',
      40: 'And maybe a heater...',
      42: 'I hope you brought a jacket',
      96: 'Where is a good shadow?',
      98: 'Sweaty gloves',
      100: 'Shorts are not PPE?!',
    };

    for (final t in tempSpecials) {
      defs.add(AchievementDef(
        id: 'global_temp_${t}F',
        title: tempTitles[t] ?? 'Temp $t°F',
        description: 'Completed an observation at $t°F.',
        threshold: t,   // used as “match value” for temp scope
        scope: 'temp',
      ));
    }

// --- Location totals (inside/outside), valid completion only ---
    const locThresholds = [200, 400, 600];
    final locTitlesInside = <int, String>{
      200: 'I love the smell of wet monkey in the morning',
      400: 'Go touch grass',
      600: 'Sunlight is good too you know',
    };
    final locTitlesOutside = <int, String>{
      200: 'Tree hugger',
      400: "Hope you don't have allergies",
      600: 'Actually touched grass',
    };

    for (final t in locThresholds) {
      defs.add(AchievementDef(
        id: 'global_location_inside_$t',
        title: locTitlesInside[t] ?? 'Inside $t',
        description: 'Completed $t inside observations.',
        threshold: t,
        scope: 'location',
        groupName: 'inside',
      ));

      defs.add(AchievementDef(
        id: 'global_location_outside_$t',
        title: locTitlesOutside[t] ?? 'Outside $t',
        description: 'Completed $t outside observations.',
        threshold: t,
        scope: 'location',
        groupName: 'outside',
      ));
    }



    return defs;
  }

  // DEBUG: unlock everything for one observer (UI testing only)
  static Future<void> debugUnlockAllForObserver({
    required String observerName,
    String sampleGroupName = 'Griffin',
  }) async {
    final now = DateTime.now();
    final prefs = await SharedPreferences.getInstance();

    // Load normal blobs
    final statsJ = _readMapJson(prefs.getString(_kStatsKey));
    final unlockedJ = _readMapJson(prefs.getString(_kUnlockedKey));
    final historyJ = _readMapJson(prefs.getString(_kHistoryKey));

    // Ensure stats high enough to satisfy every threshold
    final obsStats = (statsJ[observerName] is Map) ? (statsJ[observerName] as Map) : <String, dynamic>{};
    final groups = (obsStats['groups'] is Map) ? (obsStats['groups'] as Map) : <String, dynamic>{};
    final locations = (obsStats['locations'] is Map) ? (obsStats['locations'] as Map) : <String, dynamic>{};

    obsStats['total'] = 1000;
    groups[sampleGroupName] = 1000;
    obsStats['groups'] = groups;

    locations['inside'] = 600;
    locations['outside'] = 600;
    obsStats['locations'] = locations;

    statsJ[observerName] = obsStats;

    // Unlock all normal IDs that exist for that group (includes global/group/temp/location)
    final defs = _catalogFor(sampleGroupName);
    final allIds = defs.map((d) => d.id).toSet();

    unlockedJ[observerName] = allIds.toList()..sort();

    final hist = (historyJ[observerName] is Map) ? (historyJ[observerName] as Map) : <String, dynamic>{};
    int i = 0;
    for (final id in allIds) {
      hist[id] = now.subtract(Duration(minutes: i)).toIso8601String();
      i++;
    }
    historyJ[observerName] = hist;

    await prefs.setString(_kStatsKey, jsonEncode(statsJ));
    await prefs.setString(_kUnlockedKey, jsonEncode(unlockedJ));
    await prefs.setString(_kHistoryKey, jsonEncode(historyJ));

    // Load fail blobs
    final fStatsJ = _readMapJson(prefs.getString(_kFailStatsKey));
    final fUnlockedJ = _readMapJson(prefs.getString(_kFailUnlockedKey));
    final fHistoryJ = _readMapJson(prefs.getString(_kFailHistoryKey));

    final fObs = (fStatsJ[observerName] is Map) ? (fStatsJ[observerName] as Map) : <String, dynamic>{};
    fObs['total'] = 20; // highest fail threshold
    fStatsJ[observerName] = fObs;

    final fDefs = _failCatalog();
    final fIds = fDefs.map((d) => d.id).toSet();
    fUnlockedJ[observerName] = fIds.toList()..sort();

    final fHist = (fHistoryJ[observerName] is Map) ? (fHistoryJ[observerName] as Map) : <String, dynamic>{};
    int j = 0;
    for (final id in fIds) {
      fHist[id] = now.subtract(Duration(hours: 1, minutes: j)).toIso8601String();
      j++;
    }
    fHistoryJ[observerName] = fHist;

    await prefs.setString(_kFailStatsKey, jsonEncode(fStatsJ));
    await prefs.setString(_kFailUnlockedKey, jsonEncode(fUnlockedJ));
    await prefs.setString(_kFailHistoryKey, jsonEncode(fHistoryJ));
  }

}
