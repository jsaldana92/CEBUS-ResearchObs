// lib/observation_page.dart
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'globals.dart';
import 'main.dart';

class ObservationPage extends StatefulWidget {
  final String groupName;

  ObservationPage({required this.groupName});

  @override
  _ObservationPageState createState() => _ObservationPageState();
}

class _ObservationPageState extends State<ObservationPage> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  String currentLine = '';
  List<String> observationLog = [];
  List<String> adLibitumLog = [];
  String? currentTimestamp;

  Timer? _periodicTimer;
  int _playCount = 0;

  Duration _elapsedTime = Duration.zero;
  Timer? _elapsedTimer;

  late final List<String> subjects;

  @override
  void initState() {
    super.initState();
    subjects = [...(groupMembers[widget.groupName] ?? []), 'Group'];
  }

  Map<String, dynamic> behaviors = {
    'Proximity': null,
    'Contact': null,
    'Groom': null,
    'Play': null,
    'Sexual': null,
    'Feed+': ['Solo-feed', 'Proximity-feed', 'Contact-feed', 'Forage'],
    'Share+': ['Active-share', 'Passive-share', 'Cofeed', 'Beg'],
    'Inactive': null,
    'Manipulate': null,
    'Locomote': null,
    'Aggression+': ['Aggression', 'Supplant'],
    'Abnormal': null,
    'Ab Lib+': [
      'Non-contact aggression',
      'Contact-aggression',
      'Intergroup aggression',
      'Submissive',
      'Solicit',
      'Supplant',
      'Intervene',
      'Post-conflict affiliation',
      'Sexual',
      'Intergroup sexual',
      'Beg',
      'Food share'
    ],
    'Note+': 'text'
  };

  void updateBehaviors(Map<String, dynamic> newBehaviors) {
    setState(() {
      behaviors = newBehaviors;
    });
  }

  void startObservationTimer() {
    _playCount = 0;
    _periodicTimer = Timer.periodic(Duration(minutes: 3), (timer) {
      _playCount += 1;
      if (_playCount >= 10) {
        timer.cancel();
      } else {
        _audioPlayer.play(AssetSource('completed_ding.mp3'));
      }
    });
  }

  void startVisualTimer() {
    _elapsedTime = Duration.zero;
    _elapsedTimer?.cancel();
    _elapsedTimer = Timer.periodic(Duration(seconds: 1), (timer) {
      setState(() {
        _elapsedTime += Duration(seconds: 1);
        if (_elapsedTime >= Duration(minutes: 40)) {
          timer.cancel();
        }
      });
    });
  }

  void addBehavior(String behavior) async {
    if (behavior.endsWith('+')) {
      final nestedOptions = behaviors[behavior];

      if (nestedOptions == 'text') {
        final controller = TextEditingController();
        final result = await showDialog<String>(
          context: context,
          builder: (_) => AlertDialog(
            title: Text('Enter a note'),
            content: TextField(controller: controller, maxLines: 3),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, controller.text),
                child: Text('Save'),
              ),
            ],
          ),
        );
        if (result != null && result.trim().isNotEmpty) {
          addToCurrentLine(result.trim());
        }
      } else if (nestedOptions is List<String>) {
        final selected = await showDialog<String>(
          context: context,
          builder: (_) => SimpleDialog(
            title: Text('Select ${behavior.replaceAll('+', '')} Behavior'),
            children: nestedOptions.map((b) => SimpleDialogOption(
              child: Text(b),
              onPressed: () => Navigator.pop(context, b),
            )).toList(),
          ),
        );

        if (selected != null) {
          final isAdLib = behavior == 'Ab Lib+';
          final displayText = isAdLib ? '*$selected' : selected;
          setState(() {
            if (currentLine.isEmpty) {
              currentTimestamp = _formatTime(_elapsedTime);
              currentLine = displayText;
            } else {
              currentLine += ' $displayText';
            }
          });
          if (isAdLib) adLibitumLog.add('[$currentTimestamp] $selected');
        }
      }
    } else {
      addToCurrentLine(behavior);
    }
  }

  void addToCurrentLine(String word) {
    setState(() {
      if (currentLine.isEmpty) {
        currentTimestamp = _formatTime(_elapsedTime);
        currentLine = word;
      } else {
        currentLine += ' $word';
      }
    });
  }

  void finalizeCurrentLine() {
    if (currentLine.trim().isEmpty || currentTimestamp == null) return;
    setState(() {
      observationLog.add('[$currentTimestamp] $currentLine');
      currentLine = '';
      currentTimestamp = null;
    });
  }

  void undoLastLine() {
    setState(() {
      if (observationLog.isNotEmpty) observationLog.removeLast();
    });
  }

  String _formatTime(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  String get fullTextLog => [...observationLog, if (currentLine.isNotEmpty) currentLine].join('\n');

  Future<void> saveAdLibitumLog() async {
    if (adLibitumLog.isEmpty) return;
    final now = DateTime.now();
    final filename = '${widget.groupName}_${now.toIso8601String().replaceAll(":", "-")}_adlibitum.csv';
    final directory = await getApplicationDocumentsDirectory();
    final filePath = '${directory.path}/$filename';
    final file = File(filePath);
    final content = adLibitumLog.map((line) => '"$line"').join('\n');
    await file.writeAsString(content);
    await uploadFileToDropbox(filePath, '/$filename');
  }

  Future<bool> uploadFileToDropbox(String filePath, String dropboxPath) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('dropbox_access_token');
      if (token == null) return false;
      final fileBytes = await File(filePath).readAsBytes();
      final response = await http.post(
        Uri.parse('https://content.dropboxapi.com/2/files/upload'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/octet-stream',
          'Dropbox-API-Arg': jsonEncode({
            'path': dropboxPath,
            'mode': 'add',
            'autorename': true,
            'mute': false,
          }),
        },
        body: fileBytes,
      );
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  @override
  void dispose() {
    super.dispose();
    final homeState = context.findAncestorStateOfType<HomeScreenState>();
    homeState?.resetObservationInputs();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.groupName),
        actions: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 40,
                  height: 40,
                  child: CircularProgressIndicator(
                    value: _elapsedTime.inSeconds / (30 * 60),
                    strokeWidth: 5,
                    backgroundColor: Colors.grey,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                  ),
                ),
                if (_elapsedTime >= Duration(minutes: 30))
                  Icon(Icons.check, color: Colors.white),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Text(
              _formatTime(_elapsedTime),
              style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
            ),
          ),
          IconButton(
            icon: Icon(Icons.play_arrow, color: Colors.green),
            onPressed: () {
              _audioPlayer.play(AssetSource('completed_ding.mp3'));
              setState(() {
                observationLog.clear();
                currentLine = '';
                currentTimestamp = null;
                _elapsedTime = Duration.zero;
              });
              startObservationTimer();
              startVisualTimer();
            },
          ),
          IconButton(
            icon: Icon(Icons.flag, color: Colors.orange),
            onPressed: () async {
              _audioPlayer.play(AssetSource('completed_yay.mp3'));
              _periodicTimer?.cancel();
              _elapsedTimer?.cancel();
              final now = DateTime.now();
              final filename = '${widget.groupName}_${now.toIso8601String().replaceAll(":", "-")}.csv';
              final directory = await getApplicationDocumentsDirectory();
              final filePath = '${directory.path}/$filename';
              final file = File(filePath);
              final csvContent = observationLog.map((line) => '"$line"').join('\n');
              await file.writeAsString(csvContent);
              await saveAdLibitumLog();
              final success = await uploadFileToDropbox(filePath, '/$filename');
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(success ? '✅ Uploaded to Dropbox!' : '❌ Upload failed.')),
              );
            },
          ),
          IconButton(
            icon: Icon(Icons.close, color: Colors.red),
            tooltip: 'Cancel Observation',
            onPressed: () {
              _audioPlayer.play(AssetSource('button_press.mp3'));
              showDialog(
                context: context,
                builder: (BuildContext context) {
                  return AlertDialog(
                    title: Text("Cancel Observation?"),
                    content: Text("Are you sure you want to cancel this observation and delete this data?"),
                    actions: [
                      TextButton(
                        child: Text("No"),
                        onPressed: () => Navigator.pop(context),
                      ),
                      TextButton(
                        child: Text("Yes"),
                        onPressed: () {
                          _audioPlayer.play(AssetSource('trumpet_fail.mp3'));
                          setState(() {
                            observationLog.clear();
                            currentLine = '';
                            currentTimestamp = null;
                            _elapsedTime = Duration.zero;
                          });
                          _elapsedTimer?.cancel();
                          _periodicTimer?.cancel();
                          Navigator.pop(context);
                        },
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            height: MediaQuery.of(context).size.height * 0.4,
            color: Colors.grey[200],
            padding: EdgeInsets.all(12),
            alignment: Alignment.topLeft,
            child: SingleChildScrollView(
              child: Text(
                fullTextLog,
                style: TextStyle(fontSize: 16),
              ),
            ),
          ),
          Divider(height: 1),
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Subjects", style: TextStyle(fontWeight: FontWeight.bold)),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: subjects.map((s) {
                      return ElevatedButton(
                        onPressed: () => addToCurrentLine(s),
                        child: Text(s),
                      );
                    }).toList(),
                  ),
                  SizedBox(height: 16),
                  Text("Behaviors", style: TextStyle(fontWeight: FontWeight.bold)),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: behaviors.keys.map((b) {
                      return OutlinedButton(
                        onPressed: () => addBehavior(b),
                        child: Text(b),
                      );
                    }).toList(),
                  ),
                  SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      ElevatedButton.icon(
                        onPressed: () {
                          _audioPlayer.play(AssetSource('enter_sound.mp3'));
                          finalizeCurrentLine();
                        },
                        icon: Icon(Icons.keyboard_return),
                        label: Text("Enter"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.undo, color: Colors.red),
                        tooltip: 'Undo Last Line',
                        onPressed: undoLastLine,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          )
        ],
      ),
    );
  }
}
