// lib/observation_page.dart
import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'globals.dart' as globals;
import 'main.dart';
import 'dropbox_folder_picker.dart';


class ObservationPage extends StatefulWidget {
  final String groupName;
  const ObservationPage({Key? key, required this.groupName}) : super(key: key);



  @override
  _ObservationPageState createState() => _ObservationPageState();
}

class _ObservationPageState extends State<ObservationPage> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool isCurrentAdLib = false;

  String currentLine = '';
  List<String> displayLog = []; // For combined visual preview only
  List<String> observationLog = [];
  List<String> adLibitumLog = [];
  String? currentTimestamp;

  Timer? _periodicTimer;
  int _playCount = 0;

  Duration _elapsedTime = Duration.zero;
  Timer? _elapsedTimer;

  String? recordedDateAndTime;

  String _formatDateAndTime(DateTime dateTime) {
    return "${_monthName(dateTime.month)} ${dateTime.day}, ${dateTime.year} "
        "${_formatHour(dateTime)}:${_twoDigits(dateTime.minute)}:${_twoDigits(dateTime.second)} "
        "${dateTime.hour >= 12 ? 'PM' : 'AM'}";
  }

  String _twoDigits(int n) => n.toString().padLeft(2, '0');

  String _formatHour(DateTime dt) {
    final h = dt.hour % 12;
    return (h == 0 ? 12 : h).toString();
  }

  String _monthName(int month) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return months[month - 1];
  }


  late final List<String> subjects;


  @override
  void initState() {
    super.initState();
    subjects = [...(globals.groupMembers[widget.groupName] ?? []), 'Inter-G'];
  }

  Map<String, dynamic> behaviors = {
    'Proximity': null,
    'Contact': null,
    'Groom': null,
    'Play': null,
    'Sexual': null,
    'Feed+': ['Solo-Feed', 'Proximity-Feed', 'Contact-Feed', 'Forage'],
    'Share+': ['Active-Share', 'Passive-Share', 'Cofeed', 'Beg'],
    'Inactive': null,
    'Manipulate': null,
    'Locomote': null,
    'Aggress+': ['Aggress', 'Supplant'],
    'Abnormal': null,
    'Ab Lib+': {
      'Non-Contact Aggression': 'NC-Aggress*',
      'Contact Aggression': 'C-Aggress*',
      'Intergroup Aggression': 'Aggress* Inter-G',
      'Submissive': 'Submissive*',
      'Solicit': 'Solicit*',
      'Supplant': 'Supplant*',
      'Intervene': 'Intervene*',
      'Post-Conflict Affiliation': 'PC-Affil*',
      'Sexual': 'Sexual*',
      'Intergroup Sexual': 'Sexual* Inter-G',
      'Beg': 'Beg*',
      'Food Share': 'Food-Share*',
    },
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
        _audioPlayer.play(AssetSource('sounds/completed_ding.mp3'));
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
      } else if (nestedOptions is List<String> || nestedOptions is Map<String, String>) {
        final isAdLib = behavior == 'Ab Lib+';

        String? selected;
        if (nestedOptions is List<String>) {
          selected = await showDialog<String>(
            context: context,
            builder: (_) => SimpleDialog(
              title: Text('Select ${behavior.replaceAll('+', '')} Behavior'),
              children: nestedOptions.map((b) => SimpleDialogOption(
                child: Text(b),
                onPressed: () => Navigator.pop(context, b),
              )).toList(),
            ),
          );
        } else if (nestedOptions is Map<String, String>) {
          selected = await showDialog<String>(
            context: context,
            builder: (_) => SimpleDialog(
              title: Text('Select ${behavior.replaceAll('+', '')} Behavior'),
              children: nestedOptions.entries.map((entry) => SimpleDialogOption(
                child: Text(entry.key),
                onPressed: () => Navigator.pop(context, entry.key),
              )).toList(),
            ),
          );
        }

        if (selected != null) {
          final valueToInsert = (nestedOptions is Map<String, String>)
              ? nestedOptions[selected]!
              : selected;

          setState(() {
            isCurrentAdLib = isAdLib;
            if (currentLine.isEmpty) {
              currentTimestamp = _formatTime(_elapsedTime);
              currentLine = valueToInsert;
            } else {
              currentLine += ' $valueToInsert';
            }
          });
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
    final line = '[$currentTimestamp] $currentLine';

    setState(() {
      if (isCurrentAdLib) {
        adLibitumLog.add(line);
      } else {
        observationLog.add(line);
      }
      displayLog.add(line); // ✅ always add to combined display
      currentLine = '';
      currentTimestamp = null;
      isCurrentAdLib = false;
    });
  }



  void undoLastLine() {
    setState(() {
      if (displayLog.isNotEmpty) {
        final removed = displayLog.removeLast();
        if (observationLog.contains(removed)) {
          observationLog.remove(removed);
        } else if (adLibitumLog.contains(removed)) {
          adLibitumLog.remove(removed);
        }
      }
    });
  }


  String _formatTime(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  String get fullTextLog {
    final previewLine = currentLine.isNotEmpty && currentTimestamp != null
        ? '[$currentTimestamp] $currentLine'
        : null;

    return [...displayLog, if (previewLine != null) previewLine].join('\n');
  }




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
    } catch (e) {
      debugPrint('Dropbox upload failed: $e');
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
        title: Text("Group Scan Obs"),
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              // Start Button
              InkWell(
                onTap: () {
                  _audioPlayer.play(AssetSource('sounds/completed_ding.mp3'));

                  final now = DateTime.now();
                  setState(() {
                    observationLog.clear();
                    adLibitumLog.clear();       // ✅ Clear ad libitum memory
                    displayLog.clear();         // ✅ Clear visual display log
                    currentLine = '';
                    currentTimestamp = null;
                    isCurrentAdLib = false;
                    _elapsedTime = Duration.zero;
                    globals.recordedDateAndTime = _formatDateAndTime(now);
                  });



                  startObservationTimer();
                  startVisualTimer();
                },
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Image.asset(
                      'assets/icon/start_icon.png',
                      width: 60,
                      height: 60,
                    ),
                    Text(
                      'Start',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        shadows: [
                          Shadow(blurRadius: 3, color: Colors.black, offset: Offset(1, 1)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Complete Button
              InkWell(
                onTap: () async {
                  _audioPlayer.play(AssetSource('sounds/completed_yay.mp3'));
                  _periodicTimer?.cancel();
                  _elapsedTimer?.cancel();

                  // File naming
                  final String fileGroup = widget.groupName;
                  final String fileGroupHeader = widget.groupName.toUpperCase();
                  final String fileDate = "${globals.selectedYear ?? 'YYYY'}${(globals.selectedMonth ?? 'MM').padLeft(2, '0')}${(globals.selectedDay ?? 'DD').padLeft(2, '0')}";
                  final String fileTimeSuffix = (globals.selectedTimeOfDay ?? 'TIME').toUpperCase();
                  final filename = "$fileGroup $fileDate $fileTimeSuffix.txt";

// Write to internal storage first
                  final directory = await getApplicationDocumentsDirectory();
                  final filePath = '${directory.path}/$filename';
                  final file = File(filePath);

                  final header = [
                    '# Group: $fileGroupHeader',
                    '# Date and Time: ${globals.recordedDateAndTime ?? ''}',
                    '# Observer: ${globals.selectedExperimenter ?? ''}',
                    '# Estrous: ${globals.selectedEstrous ?? ''}',
                    '# Location: ${globals.selectedLocation ?? ''}',
                    '# Temperature: ${globals.selectedTemperature ?? ''}',
                    '# Weather Condition: ${globals.selectedWeather ?? ''}',
                    '# Fed: ${globals.selectedFed ?? ''}',
                    '# Food in Enclosure: ${globals.selectedFoodPresent ?? ''}',
                    '# Comments: ${globals.selectedComments ?? ''}',
                    '# Data:',
                    '#',
                    'Timestamp IndividualA Behavior IndividualB'
                  ];

                  final dataLines = observationLog.map((line) => line).toList();
                  final ablibLines = ["#", "# Ablib Data:"];
                  ablibLines.addAll(adLibitumLog.map((line) => line));
                  final allContent = [...header, ...dataLines, ...ablibLines].join('\n');
                  await file.writeAsString(allContent); // ✅ Always saves internally

                  // Now ask for Dropbox folder
                  final selectedFolder = await showDialog<String>(
                    context: context,
                    builder: (_) => const DropboxFolderPicker(),
                  );
                  if (selectedFolder == null) return; // User canceled Dropbox but file is already saved

                  // Then upload
                  final dropboxPath = '${selectedFolder.startsWith('/') ? '' : '/'}$selectedFolder/$filename';
                  final success = await uploadFileToDropbox(filePath, dropboxPath);
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(success ? '✅ Uploaded to Dropbox!' : '❌ Upload failed.')),
                  );
                },
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Image.asset(
                      'assets/icon/end_icon.png',
                      width: 60,
                      height: 60,
                    ),
                    Text(
                      'Complete',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        shadows: [
                          Shadow(blurRadius: 3, color: Colors.black, offset: Offset(1, 1)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),


              // Cancel Button
              InkWell(
                onTap: () {
                  _audioPlayer.play(AssetSource('sounds/button_press.mp3'));
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
                              _audioPlayer.play(AssetSource('sounds/trumpet_fail.mp3'));
                              setState(() {
                                observationLog.clear();
                                adLibitumLog.clear();       // ✅ Clear ad libitum memory
                                displayLog.clear();         // ✅ Clear visual display log
                                currentLine = '';
                                currentTimestamp = null;
                                isCurrentAdLib = false;
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
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Image.asset(
                      'assets/icon/cancel_icon.png',
                      width: 60,
                      height: 60,
                    ),
                    Text(
                      'Cancel',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        shadows: [
                          Shadow(blurRadius: 3, color: Colors.black, offset: Offset(1, 1)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
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
                      return ElevatedButton(
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
                          _audioPlayer.play(AssetSource('sounds/enter_sound.mp3'));
                          finalizeCurrentLine();
                        },
                        icon: Icon(Icons.keyboard_return),
                        label: Text("Enter"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                        ),
                      ),

                      //Undo last line button
                      ElevatedButton.icon(
                        onPressed: undoLastLine,
                        icon: Icon(Icons.undo),
                        label: Text("Undo"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                          foregroundColor: Colors.white,
                        ),
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
