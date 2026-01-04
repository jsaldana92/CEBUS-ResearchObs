// lib/achievements_page.dart
import 'package:flutter/material.dart';

import 'achievements_service.dart';
import 'achievements_models.dart';

class AchievementsPage extends StatefulWidget {
  const AchievementsPage({super.key});

  @override
  State<AchievementsPage> createState() => _AchievementsPageState();
}

class _AchievementsPageState extends State<AchievementsPage> {
  late Future<List<String>> _observersF;

  @override
  void initState() {
    super.initState();
    _observersF = AchievementsService.listObservers();
  }

  Future<void> _refresh() async {
    setState(() {
      _observersF = AchievementsService.listObservers();
    });
    await _observersF;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Achievements')),
      body: FutureBuilder<List<String>>(
        future: _observersF,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final observers = (snap.data ?? const <String>[]).where((e) => e.trim().isNotEmpty).toList();

          if (observers.isEmpty) {
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 120),
                  Padding(
                    padding: EdgeInsets.all(20),
                    child: Text(
                      'No achievements yet.\nComplete an observation to begin.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                ],
              ),
            );
          }

          return DefaultTabController(
            length: observers.length,
            child: Column(
              children: [
                Material(
                  color: Theme.of(context).colorScheme.surface,
                  child: TabBar(
                    isScrollable: true,
                    tabs: observers.map((o) => Tab(text: o)).toList(),
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    children: observers
                        .map((o) => _ObserverUnlockedAchievements(
                      observer: o,
                      onGlobalRefresh: _refresh,
                    ))
                        .toList(),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ObserverUnlockedAchievements extends StatefulWidget {
  final String observer;
  final Future<void> Function() onGlobalRefresh;

  const _ObserverUnlockedAchievements({
    required this.observer,
    required this.onGlobalRefresh,
  });

  @override
  State<_ObserverUnlockedAchievements> createState() => _ObserverUnlockedAchievementsState();
}

class _ObserverUnlockedAchievementsState extends State<_ObserverUnlockedAchievements> {
  late Future<List<_UnlockedRow>> _rowsF;

  @override
  void initState() {
    super.initState();
    _rowsF = _loadRows();
  }

  Future<void> _refreshLocal() async {
    setState(() {
      _rowsF = _loadRows();
    });
    await _rowsF;

    // Also refresh the observer list in the parent (new observers can appear).
    await widget.onGlobalRefresh();
  }

  Future<Map<String, AchievementDef>> _buildDefsById() async {
    final defsById = <String, AchievementDef>{};

    // 1) Fail/cancel catalog (global)
    for (final d in AchievementsService.failCatalog()) {
      defsById[d.id] = d;
    }

    // 2) Normal catalogs for any groups the observer has stats for
    //    (catalogForGroup() is the authoritative source for titles/descriptions)
    try {
      final stats = await AchievementsService.getObserverStats(widget.observer);

      final groups = <String>[];
      final g = stats['groups'];
      if (g is Map) {
        for (final k in g.keys) {
          final s = k.toString().trim();
          if (s.isNotEmpty) groups.add(s);
        }
      }

      // Build catalog entries for each group and merge by id
      for (final groupName in groups) {
        final defs = AchievementsService.catalogForGroup(groupName);
        for (final d in defs) {
          defsById[d.id] = d;
        }
      }
    } catch (_) {
      // If stats can't be read, we still show unlocked IDs as fallback.
    }

    return defsById;
  }

  Future<List<_UnlockedRow>> _loadRows() async {
    // Load unlocked lists + timestamps
    final unlocked = await AchievementsService.getObserverUnlocked(widget.observer);
    final history = await AchievementsService.getObserverHistory(widget.observer);

    final failUnlocked = await AchievementsService.getObserverFailUnlocked(widget.observer);
    final failHistory = await AchievementsService.getObserverFailHistory(widget.observer);

    // Build the authoritative ID -> def map from AchievementsService catalogs
    final defsById = await _buildDefsById();

    final rows = <_UnlockedRow>[];

    void addRows(Iterable<String> ids, Map<String, String> tsMap) {
      for (final id in ids) {
        final ts = tsMap[id];
        if (ts == null || ts.trim().isEmpty) continue;

        final def = defsById[id];

        rows.add(_UnlockedRow(
          id: id,
          unlockedAtIso: ts,
          title: def?.title ?? id,
          description: def?.description ?? 'Unlocked an achievement.',
        ));
      }
    }

    addRows(unlocked, history);
    addRows(failUnlocked, failHistory);

    // Sort newest first
    rows.sort((a, b) => b.unlockedAt.compareTo(a.unlockedAt));
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _refreshLocal,
      child: FutureBuilder<List<_UnlockedRow>>(
        future: _rowsF,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                SizedBox(height: 160),
                Center(child: CircularProgressIndicator()),
              ],
            );
          }

          final rows = snap.data ?? const <_UnlockedRow>[];

          if (rows.isEmpty) {
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: const [
                SizedBox(height: 120),
                Padding(
                  padding: EdgeInsets.all(20),
                  child: Text(
                    'No achievements unlocked yet for this observer.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16),
                  ),
                ),
              ],
            );
          }

          return ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            itemCount: rows.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final r = rows[i];

              return Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFd9ded9),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListTile(
                  leading: const Icon(Icons.emoji_events),
                  title: Text(
                    r.title,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 4),
                      Text(r.description),
                      const SizedBox(height: 6),
                      Text(
                        'Unlocked: ${_formatIso(r.unlockedAtIso)}',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// ---------- Model used only inside this page ----------
class _UnlockedRow {
  final String id;
  final String unlockedAtIso;
  final String title;
  final String description;

  _UnlockedRow({
    required this.id,
    required this.unlockedAtIso,
    required this.title,
    required this.description,
  });

  DateTime get unlockedAt {
    try {
      return DateTime.parse(unlockedAtIso);
    } catch (_) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
  }
}

/// ---------- Formatting ----------
String _formatIso(String iso) {
  try {
    final dt = DateTime.parse(iso).toLocal();
    final yyyy = dt.year.toString().padLeft(4, '0');
    final mm = dt.month.toString().padLeft(2, '0');
    final dd = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mi = dt.minute.toString().padLeft(2, '0');
    return '$yyyy-$mm-$dd $hh:$mi';
  } catch (_) {
    return iso;
  }
}
