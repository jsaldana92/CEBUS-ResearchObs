import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart'; //this is to play audio file
import 'storage_service.dart'; // this is specifically to call the storage in lib
import 'globals.dart';
import 'settings_page.dart';
import 'observation_page.dart';






void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  experimenters = await StorageService.loadList('experimenters');

  experimenters = await StorageService.loadList('experimenters');
  if (experimenters.isEmpty && !(await StorageService.hasKey('experimenters'))) {
    experimenters = ['JS', 'MHB', 'GH', 'SS', 'PP'];
    await StorageService.saveList('experimenters', experimenters);
  }

  groupNames = await StorageService.loadList('groupNames');
  if (groupNames.isEmpty) {
    groupNames = ['Logan', 'Griffin', 'Nkima', 'Mason', 'Liam', 'Attila'];
    await StorageService.saveList('groupNames', groupNames);
  }

  groupMembers = await StorageService.loadMap('groupMembers');
  if (groupMembers.isEmpty) {
    groupMembers = {
      'Logan': ['Logan', 'Ivory', 'Ira', 'Paddy', 'Irene', 'Ingrid'],
      'Griffin': ['Griffin', 'Lily', 'Lexi', 'Wren', 'Widget'],
      'Nkima': ['Nkima', 'Nala', 'Gambit', 'Lychee'],
      'Mason': ['Mason', 'Gonzo', 'Gretel', 'Beeker', 'Benny', 'Bias', 'Bailey'],
      'Liam': ['Liam', 'Isabelle', 'Applesauce', 'Scarlett'],
      'Attila': ['Attila', 'Albert'],
    };
    await StorageService.saveMap('groupMembers', groupMembers);
  }

  runApp(ResearchObsApp());
}


class ResearchObsApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ResearchObs',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: HomeScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}


class HomeScreen extends StatefulWidget {
  @override
  HomeScreenState createState() => HomeScreenState();
}

class HomeScreenState extends State<HomeScreen> {
  final AudioPlayer _audioPlayer = AudioPlayer(); // enables sound in home screen

  //this set of code is needed to call later on pop ups that rely on internal lists or boolean factors (yes/no)
  List<String> selectedExperimenters = [];
  String? selectedLocation;
  String? temperatureF;
  bool? isFed;
  bool? isFoodPresent;
  List<String> estrousSubjects = [];
  String? observationComment;

//allows the reset of the pop ups if this code is called
  void resetObservationInputs() {
    setState(() {
      selectedExperimenters.clear();
      selectedLocation = null;
      temperatureF = null;
      isFed = null;
      isFoodPresent = null;
      estrousSubjects.clear();
      observationComment = null;
    });
  }



  // First dialog: experimenter checkboxes
  void _showExperimenterDialog(BuildContext context, String groupName) {
    selectedExperimenters.clear();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: Icon(Icons.close),
                onPressed: () {
                  resetObservationInputs();
                  Navigator.of(context).popUntil((route) => route.isFirst);
                },
              ),
              Flexible(
                child: Text(
                  "Who is conducting the observation?",
                  style: TextStyle(fontSize: 16),
                  overflow: TextOverflow.visible,
                  softWrap: true,
                ),
              ),
              SizedBox(width: 48), // placeholder for symmetry
            ],
          ),
          content: SizedBox(
            height: 200,
            child: StatefulBuilder(
              builder: (BuildContext context, StateSetter setDialogState) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          children: experimenters.map((exp) {
                            return CheckboxListTile(
                              title: Text(exp),
                              value: selectedExperimenters.contains(exp),
                              onChanged: (bool? checked) {
                                setDialogState(() {
                                  if (checked == true) {
                                    selectedExperimenters.add(exp);
                                  } else {
                                    selectedExperimenters.remove(exp);
                                  }
                                });
                              },
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                    SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        child: Text("Next"),
                        onPressed: selectedExperimenters.isNotEmpty
                            ? () {
                          Navigator.of(context).pop();
                          _showLocationDialog(context, groupName);
                        }
                            : null,
                      ),
                    )
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  // Proceed to next dialog after experimenters selected, this is the location (inside or outside pop-up)
  void _showLocationDialog(BuildContext context, String groupName) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                  icon: Icon(Icons.close),
                  onPressed: () {
                    resetObservationInputs(); //
                    Navigator.of(context).popUntil((route) => route.isFirst);
                  }
              ),
              Text("Location"),
              SizedBox(width: 48), // placeholder for X alignment
            ],
          ),
          content: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.5, // 50% of screen height
            ),
            child: StatefulBuilder(
              builder: (BuildContext context, StateSetter setDialogState) {
                return Column(
                  children: [
                    ListTile(
                      title: Text("Inside"),
                      leading: Radio<String>(
                        value: "Inside",
                        groupValue: selectedLocation,
                        onChanged: (value) {
                          setDialogState(() {
                            selectedLocation = value!;
                          });
                        },
                      ),
                    ),
                    ListTile(
                      title: Text("Outside"),
                      leading: Radio<String>(
                        value: "Outside",
                        groupValue: selectedLocation,
                        onChanged: (value) {
                          setDialogState(() {
                            selectedLocation = value!;
                          });
                        },
                      ),
                    ),
                    SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        child: Text("Next"),
                        onPressed: selectedLocation != null
                            ? () {
                          Navigator.of(context).pop();
                          _showTemperatureDialog(context, groupName);
                        }
                            : null,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

//proceeds to the next pop up where temperature is input
  void _showTemperatureDialog(BuildContext context, String groupName) {
    TextEditingController _tempController = TextEditingController();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                  icon: Icon(Icons.close),
                  onPressed: () {
                    resetObservationInputs(); // 👈 Add this
                    Navigator.of(context).popUntil((route) => route.isFirst);
                  }
              ),
              Text("Temperature (°F)"),
              SizedBox(width: 48),
            ],
          ),
          content: TextField(
            controller: _tempController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              hintText: "Enter temperature",
            ),
          ),
          actions: [
            TextButton(
              child: Text("Next"),
              onPressed: () {
                if (_tempController.text.isNotEmpty) {
                  setState(() {
                    temperatureF = _tempController.text;
                  });
                  Navigator.of(context).pop();
                  _showFedDialog(context, groupName); //links to the next pop up (fed or not?)
                }
              },
            ),
          ],
        );
      },
    );
  }

  //next pop up where fed or not is asked
  void _showFedDialog(BuildContext context, String groupName) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                  icon: Icon(Icons.close),
                  onPressed: () {
                    resetObservationInputs(); // 👈 Add this
                    Navigator.of(context).popUntil((route) => route.isFirst);
                  }
              ),
              Text("Fed?"),
              SizedBox(width: 48),
            ],
          ),
          content: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.5, // 50% of screen height
            ),
            child: StatefulBuilder(
              builder: (BuildContext context, StateSetter setDialogState) {
                return Column(
                  children: [
                    ListTile(
                      title: Text("Yes"),
                      leading: Radio<bool>(
                        value: true,
                        groupValue: isFed,
                        onChanged: (value) {
                          setDialogState(() {
                            isFed = value!;
                          });
                        },
                      ),
                    ),
                    ListTile(
                      title: Text("No"),
                      leading: Radio<bool>(
                        value: false,
                        groupValue: isFed,
                        onChanged: (value) {
                          setDialogState(() {
                            isFed = value!;
                          });
                        },
                      ),
                    ),
                    SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        child: Text("Next"),
                        onPressed: isFed != null
                            ? () {
                          Navigator.of(context).pop();
                          _showFoodPresenceDialog(context, groupName);
                        }
                            : null,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  //starts next pop up, food in the enclosure or not
  void _showFoodPresenceDialog(BuildContext context, String groupName) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                  icon: Icon(Icons.close),
                  onPressed: () {
                    resetObservationInputs(); // 👈 Add this
                    Navigator.of(context).popUntil((route) => route.isFirst);
                  }
              ),
              Text("Food in the Enclosure?"),
              SizedBox(width: 48),
            ],
          ),
          content: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.5, // 50% of screen height
            ),
            child: StatefulBuilder(
              builder: (BuildContext context, StateSetter setDialogState) {
                return Column(
                  children: [
                    ListTile(
                      title: Text("Yes"),
                      leading: Radio<bool>(
                        value: true,
                        groupValue: isFoodPresent,
                        onChanged: (value) {
                          setDialogState(() {
                            isFoodPresent = value!;
                          });
                        },
                      ),
                    ),
                    ListTile(
                      title: Text("No"),
                      leading: Radio<bool>(
                        value: false,
                        groupValue: isFoodPresent,
                        onChanged: (value) {
                          setDialogState(() {
                            isFoodPresent = value!;
                          });
                        },
                      ),
                    ),
                    SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        child: Text("Next"),
                        onPressed: isFoodPresent != null
                            ? () {
                          Navigator.of(context).pop();
                          _showEstrousDialog(context, groupName);
                        }
                            : null,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  //adds the Estrus pop-up
  void _showEstrousDialog(BuildContext context, String groupName) {
    estrousSubjects.clear();
    final List<String> members = groupMembers[groupName] ?? [];

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                  icon: Icon(Icons.close),
                  onPressed: () {
                    resetObservationInputs(); // 👈 Add this
                    Navigator.of(context).popUntil((route) => route.isFirst);
                  }
              ),
              Text("Anyone in estrous?"),
              SizedBox(width: 48),
            ],
          ),
          content: SizedBox(
            height: 250,
            child: StatefulBuilder(
              builder: (BuildContext context, StateSetter setDialogState) {
                return Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          children: members.map((name) {
                            return CheckboxListTile(
                              title: Text(name),
                              value: estrousSubjects.contains(name),
                              onChanged: (bool? checked) {
                                setDialogState(() {
                                  if (checked == true) {
                                    estrousSubjects.add(name);
                                  } else {
                                    estrousSubjects.remove(name);
                                  }
                                });
                              },
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                    SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        child: Text("Next"),
                        onPressed: () {
                          Navigator.of(context).pop();
                          _showCommentDialog(context, groupName);
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  //adds the next pop up, "any other comments"
  void _showCommentDialog(BuildContext context, String groupName) {
    TextEditingController _commentController = TextEditingController();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                  icon: Icon(Icons.close),
                  onPressed: () {
                    resetObservationInputs(); // 👈 Add this
                    Navigator.of(context).popUntil((route) => route.isFirst);
                  }
              ),
              Text("Any other comments?"),
              SizedBox(width: 48),
            ],
          ),
          content: TextField(
            controller: _commentController,
            maxLines: 4,
            decoration: InputDecoration(
              hintText: "Enter any notes here...",
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              child: Text("Go to New Observation"),
              onPressed: () {
                setState(() {
                  observationComment = _commentController.text;
                });
                Navigator.of(context).pop();

                // Go to ObservationPage
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => ObservationPage(groupName: groupName),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }


  @override
  Widget build(BuildContext context) {

    return Scaffold(
      appBar: AppBar(
        title: Text('ResearchObs'),
      ),
      body: Stack(
        children: [
          // Main scrollable content in the center
          SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Welcome to ResearchObs!',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Choose a group:',
                    style: TextStyle(fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 24),
                  ...groupNames.map((name) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6.0),
                    child: ElevatedButton(
                      onPressed: () {
                        _audioPlayer.play(AssetSource('button_press.mp3'));
                        resetObservationInputs();
                        _showExperimenterDialog(context, name);
                      },
                      child: Text(name),
                      style: ElevatedButton.styleFrom(
                        minimumSize: Size(double.infinity, 48),
                      ),
                    ),
                  )),
                  SizedBox(height: 80), // extra space to prevent overlap with FAB
                ],
              ),
            ),
          ),

          // Settings button in bottom-right corner
          Positioned(
            bottom: 16,
            right: 16,
            child: FloatingActionButton(
              heroTag: 'settingsBtn',
              backgroundColor: Colors.black,
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => SettingsPage()),
                );
                setState(() {}); // Refreshes the state after returning
              },
              child: Icon(Icons.settings, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}



