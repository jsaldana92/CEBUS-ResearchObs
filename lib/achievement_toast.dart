// lib/achievement_toast.dart
import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'achievements_models.dart';

class AchievementToast {
  static final Queue<AchievementUnlocked> _queue = Queue();
  static bool _showing = false;

  // Optional sound: call setSoundPlayer() once from a page that already has an AudioPlayer
  static AudioPlayer? _soundPlayer;
  static String? _soundAssetPath; // e.g. 'sounds/achievement_unlocked.mp3'

  static void setSoundPlayer(AudioPlayer player, String assetPath) {
    _soundPlayer = player;
    _soundAssetPath = assetPath;
  }

  static void enqueue(BuildContext context, List<AchievementUnlocked> unlocked) {
    if (unlocked.isEmpty) return;
    _queue.addAll(unlocked);
    _pump(context);
  }

  static void _pump(BuildContext context) async {
    if (_showing) return;
    if (_queue.isEmpty) return;

    _showing = true;
    final item = _queue.removeFirst();

    final overlay = Overlay.of(context);
    if (overlay == null) {
      _showing = false;
      return;
    }

    final entry = OverlayEntry(
      builder: (_) => _ToastWidget(item: item),
    );

    overlay.insert(entry);

    // Play sound (best-effort)
    try {
      final p = _soundPlayer;
      final a = _soundAssetPath;
      if (p != null && a != null && a.isNotEmpty) {
        await p.play(AssetSource(a));
      }
    } catch (_) {}

    await Future.delayed(const Duration(seconds: 5));
    entry.remove();

    _showing = false;

    // show next (if any)
    if (_queue.isNotEmpty) {
      _pump(context);
    }
  }
}

class _ToastWidget extends StatefulWidget {
  final AchievementUnlocked item;
  const _ToastWidget({required this.item});

  @override
  State<_ToastWidget> createState() => _ToastWidgetState();
}

class _ToastWidgetState extends State<_ToastWidget> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 260));
    _slide = Tween(begin: const Offset(0, 1.2), end: const Offset(0, 0)).animate(
      CurvedAnimation(parent: _c, curve: Curves.easeOutCubic),
    );
    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final def = widget.item.def;

    return Positioned(
      left: 16,
      right: 16,
      bottom: 24,
      child: SlideTransition(
        position: _slide,
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF1B1B1B),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withOpacity(0.12)),
              boxShadow: [
                BoxShadow(
                  blurRadius: 18,
                  spreadRadius: 0,
                  color: Colors.black.withOpacity(0.35),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFF2E2E2E),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.emoji_events, color: Colors.amber, size: 26),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Achievement Unlocked!',
                        style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        def.title,
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        def.description,
                        style: const TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
