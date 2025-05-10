import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart'; //this is to play audio file
import 'dart:async'; //this is for the timer settings
import 'storage_service.dart'; // this is specifically to call the storage in lib
import 'dropbox_service.dart';


List<String> experimenters = [];
List<String> groupNames = [];
Map<String, List<String>> groupMembers = {};

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await DropboxService.initDropbox(); //needed to call in dropbox services

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
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
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
  void _resetObservationInputs() {
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
                  _resetObservationInputs();
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
                    _resetObservationInputs(); //
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
                    _resetObservationInputs(); // 👈 Add this
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
                    _resetObservationInputs(); // 👈 Add this
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
                    _resetObservationInputs(); // 👈 Add this
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
                    _resetObservationInputs(); // 👈 Add this
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
                    _resetObservationInputs(); // 👈 Add this
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
    //taken out since now we are populating from a global list/ final List<String> subjects = ['Logan', 'Griffin', 'Nkima', 'Mason', 'Liam'];

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
                        _resetObservationInputs();
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

//this is the code for the settings page
class SettingsPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Settings'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Settings',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 16),
            ElevatedButton.icon(
              icon: Icon(Icons.group),
              label: Text('Manage Groups'),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => ManageGroupsPage()),
                );
              },
            ),
            SizedBox(height: 12),
            ElevatedButton.icon(
              icon: Icon(Icons.people_alt),
              label: Text('Edit Group Members'),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => EditGroupMembersPage()),
                );
              },
            ),
            SizedBox(height: 12),
            ElevatedButton.icon(
              icon: Icon(Icons.edit_note),
              label: Text('Edit Experimenters'),
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (context) => EditExperimentersPage()),
                );
              },
            ),
            SizedBox(height: 12),
            ElevatedButton.icon(
              icon: Icon(Icons.cloud_upload),
              label: Text('Log in to Dropbox'),
              onPressed: () async {
                await DropboxService.loginToDropbox();

                final loggedIn = await DropboxService.isLoggedIn();
                final snackBar = SnackBar(
                  content: Text(loggedIn ? '✅ Logged into Dropbox!' : '❌ Dropbox login failed.'),
                );
                ScaffoldMessenger.of(context).showSnackBar(snackBar);
              },
            ),
          ],
        ),
      ),
    );
  }
}

//creates the manage groups page
class ManageGroupsPage extends StatefulWidget {
  @override
  _ManageGroupsPageState createState() => _ManageGroupsPageState();
}

class _ManageGroupsPageState extends State<ManageGroupsPage> {
  final TextEditingController _groupController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Manage Groups')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Current Groups:', style: TextStyle(fontSize: 18)),
            SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                itemCount: groupNames.length,
                itemBuilder: (context, index) {
                  return ListTile(
                    title: Text(groupNames[index]),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(Icons.edit),
                          onPressed: () async {
                            final edited = await _showEditDialog(context, groupNames[index]);
                            if (edited != null && edited.isNotEmpty) {
                              final oldName = groupNames[index];
                              final newName = edited.trim();
                              if (!groupNames.contains(newName)) {
                                setState(() {
                                  groupNames[index] = newName;

                                  // Move associated members to the new key
                                  if (groupMembers.containsKey(oldName)) {
                                    groupMembers[newName] = groupMembers[oldName]!;
                                    groupMembers.remove(oldName);
                                  }
                                });
                                await StorageService.saveList('groupNames', groupNames);
                                await StorageService.saveMap('groupMembers', groupMembers);
                              }
                            }
                          },
                        ),
                        IconButton(
                          icon: Icon(Icons.delete, color: Colors.red),
                          onPressed: () async {
                            final removed = groupNames.removeAt(index);
                            groupMembers.remove(removed);
                            await StorageService.saveList('groupNames', groupNames);
                            await StorageService.saveMap('groupMembers', groupMembers);
                            setState(() {});
                          },
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Divider(),
            TextField(
              controller: _groupController,
              decoration: InputDecoration(labelText: 'Add New Group'),
            ),
            SizedBox(height: 12),
            ElevatedButton(
              child: Text('Add Group'),
              onPressed: () async {
                if (_groupController.text.trim().isNotEmpty) {
                  final newGroup = _groupController.text.trim();
                  if (!groupNames.contains(newGroup)) {
                    setState(() {
                      groupNames.add(newGroup);
                      _groupController.clear();
                    });
                    await StorageService.saveList('groupNames', groupNames);
                    await StorageService.saveMap('groupMembers', groupMembers); // start with empty member list
                  }
                }
              },
            )
          ],
        ),
      ),
    );
  }

  Future<String?> _showEditDialog(BuildContext context, String currentName) async {
    final controller = TextEditingController(text: currentName);
    return showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Edit Group Name'),
          content: TextField(
            controller: controller,
            decoration: InputDecoration(hintText: 'Enter new name'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(context, controller.text), child: Text('Save')),
          ],
        );
      },
    );
  }
}

//creates the manage group members page
class EditGroupMembersPage extends StatefulWidget {
  @override
  _EditGroupMembersPageState createState() => _EditGroupMembersPageState();
}

class _EditGroupMembersPageState extends State<EditGroupMembersPage> {
  String? selectedGroup;
  TextEditingController _membersController = TextEditingController();

  void _loadMembers() {
    if (selectedGroup != null && groupMembers.containsKey(selectedGroup)) {
      _membersController.text = groupMembers[selectedGroup]!.join(', ');
    }
  }

  Future<void> _saveMembers() async {
    if (selectedGroup != null) {
      setState(() {
        groupMembers[selectedGroup!] =
            _membersController.text.split(',').map((e) => e.trim()).toList();
      });

      // Save the updated groupMembers map after the setState
      await StorageService.saveMap('groupMembers', groupMembers);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Members updated')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Edit Group Members')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButton<String>(
              value: selectedGroup,
              hint: Text('Select a group'),
              items: groupNames.map((g) {
                return DropdownMenuItem(
                  value: g,
                  child: Text(g),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  selectedGroup = value;
                  _loadMembers();
                });
              },
            ),
            SizedBox(height: 16),
            TextField(
              controller: _membersController,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: 'Members (comma-separated)',
                border: OutlineInputBorder(),
              ),
            ),
            SizedBox(height: 16),
            ElevatedButton(
              child: Text('Save Members'),
              onPressed: _saveMembers,
            ),
          ],
        ),
      ),
    );
  }
}

//manage experimenters, lets you add, delete, and edit experimenters list
// Add this new page below your existing code
class EditExperimentersPage extends StatefulWidget {
  @override
  _EditExperimentersPageState createState() => _EditExperimentersPageState();
}

class _EditExperimentersPageState extends State<EditExperimentersPage> {
  final TextEditingController _controller = TextEditingController();

  Future<void> _addExperimenter() async {
    final newExp = _controller.text.trim();
    if (newExp.isNotEmpty && !experimenters.contains(newExp)) {
      setState(() {
        experimenters.add(newExp);
        _controller.clear();
      });
      await StorageService.saveList('experimenters', experimenters);
    }
  }

  Future<void> _editExperimenter(int index) async {
    final controller = TextEditingController(text: experimenters[index]);
    final edited = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Edit Experimenter'),
          content: TextField(
            controller: controller,
            decoration: InputDecoration(hintText: 'New name'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(context, controller.text), child: Text('Save')),
          ],
        );
      },
    );
    if (edited != null && edited.trim().isNotEmpty) {
      setState(() {
        experimenters[index] = edited.trim();
      });
      await StorageService.saveList('experimenters', experimenters);
    }
  }

  Future<void> _deleteExperimenter(int index) async {
    setState(() {
      experimenters.removeAt(index);
    });
    await StorageService.saveList('experimenters', experimenters);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Edit Experimenters')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                itemCount: experimenters.length,
                itemBuilder: (context, index) {
                  return ListTile(
                    title: Text(experimenters[index]),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(Icons.edit),
                          onPressed: () => _editExperimenter(index),
                        ),
                        IconButton(
                          icon: Icon(Icons.delete, color: Colors.red),
                          onPressed: () => _deleteExperimenter(index),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Divider(),
            TextField(
              controller: _controller,
              decoration: InputDecoration(labelText: 'Add New Experimenter'),
            ),
            SizedBox(height: 12),
            ElevatedButton(
              onPressed: _addExperimenter,
              child: Text('Add'),
            )
          ],
        ),
      ),
    );
  }
}


//this is the code for the observation page
class ObservationPage extends StatefulWidget {
  final String groupName;

  ObservationPage({required this.groupName});

  @override
  _ObservationPageState createState() => _ObservationPageState();
}

class _ObservationPageState extends State<ObservationPage> {
  final AudioPlayer _audioPlayer = AudioPlayer(); // allows the sounds start, completed, and fail to work
  String currentLine = '';
  List<String> observationLog = [];
  String? currentTimestamp; // Add this to capture the time of first input

  Timer? _periodicTimer; //add these next two lines be able to use the timer
  int _playCount = 0; //this part starts the count at 0 so that one ding is 1 iteration which eventually adds to 10

  Duration _elapsedTime = Duration.zero; //visual timer start at 0:00
  Timer? _elapsedTimer; // tracks elapsed visual time


  void startObservationTimer() { //this is the actual function that edits and starts the timer
    _playCount = 0;

    // Start the periodic timer (every 3 minutes)
    _periodicTimer = Timer.periodic(Duration(minutes: 3), (timer) {
      _playCount += 1;
      if (_playCount >= 10) {
        timer.cancel(); // Stop after 30 minutes (10 * 3min)
      } else {
        _audioPlayer.play(AssetSource('completed_ding.mp3'));
      }
    });
  }

  void startVisualTimer() { //adds a function to start the visual timer
    _elapsedTime = Duration.zero;

    _elapsedTimer?.cancel(); // cancel if previously running

    _elapsedTimer = Timer.periodic(Duration(seconds: 1), (timer) {
      setState(() {
        _elapsedTime += Duration(seconds: 1);

        if (_elapsedTime >= Duration(minutes: 40)) {
          timer.cancel(); // stop the timer after 40 minutes, which is done to allow observes to enter the last lines with the correct timestamps
        }
      });
    });
  }

//this part makes the subjects be dynamic and reflect any edits from the settings page
  late final List<String> subjects;

  @override
  void initState() {
    super.initState();
    subjects = [...(groupMembers[widget.groupName] ?? []), 'Group'];
  }

  final Map<String, List<String>> behaviors = {
    'Movement': ['Inactive', 'Locomote'], //the first is the category under behavior and the text in [ ] is the actual buttons
    'Proximity': ['Proximity', 'Contact'], // here proximity is the category with the proximity and contact buttons
    'Interactions': ['Aggression', 'Groom', 'Play', 'Sexual'],
  };

  void addToCurrentLine(String word) {
    setState(() {
      if (currentLine.isEmpty) {
        // Use elapsed time instead of real timestamp
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
      currentTimestamp = null; // reset after logging
    });
  }

  void undoLastLine() {
    setState(() {
      if (observationLog.isNotEmpty) {
        observationLog.removeLast();
      }
    });
  }

  // Formats the elapsed time into MM:SS format
  String _formatTime(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return '$minutes:$seconds';
  }

  String get fullTextLog {
    return [...observationLog, if (currentLine.isNotEmpty) currentLine].join('\n');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.groupName),
        actions: [
          Row(
            children: [
              // ⏱️ CIRCULAR TIMER ICON + FILL
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
              // ⏱️ TEXT TIME LABEL (e.g., 02:14)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Text(
                  _formatTime(_elapsedTime),
                  style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                ),
              ),

              // ✅ START OBSERVATION (Plays ding + starts timers)
              IconButton(
                icon: Icon(Icons.play_arrow, color: Colors.green),
                tooltip: 'Start Observation',
                onPressed: () {
                  _audioPlayer.play(AssetSource('completed_ding.mp3'));

                  setState(() {
                    observationLog.clear();       // clear previous log
                    currentLine = '';             // clear current line input
                    currentTimestamp = null;      // clear timestamp
                    _elapsedTime = Duration.zero; // reset visual timer to 00:00
                  });

                  startObservationTimer(); // start the 3-minute interval ding logic
                  startVisualTimer();      // visual timer updates every second
                  //Removed(undo if you want this text to be added) addToCurrentLine('ObservationStarted');
                },
              ),

              // ✅ FINISH OBSERVATION (Plays yay + cancels timers)
              IconButton(
                icon: Icon(Icons.flag, color: Colors.orange),
                tooltip: 'Finish Observation',
                onPressed: () {
                  _audioPlayer.play(AssetSource('completed_yay.mp3'));
                  _periodicTimer?.cancel(); // stops 3-min ding timer
                  _elapsedTimer?.cancel();  // stops visual elapsed timer
                  //Removed(undo if you want this text to be added) addToCurrentLine('ObservationFinished');
                },
              ),

              // ❌ CANCEL OBSERVATION (shows a warning)
              IconButton(
                icon: Icon(Icons.close, color: Colors.red),
                tooltip: 'Cancel Observation',
                onPressed: () {
                  _audioPlayer.play(AssetSource('button_press.mp3'));

                  // Show confirmation popup
                  showDialog(
                    context: context,
                    builder: (BuildContext context) {
                      return AlertDialog(
                        title: Text("Cancel Observation?"),
                        content: Text("Are you sure you want to cancel this observation and delete this data?"),
                        actions: [
                          TextButton(
                            child: Text("No"),
                            onPressed: () {
                              Navigator.of(context).pop(); // just close the popup
                            },
                          ),
                          TextButton(
                            child: Text("Yes"),
                            onPressed: () {
                              _audioPlayer.play(AssetSource('trumpet_fail.mp3')); // play fail sound
                              // Clear data, reset timer, close popup
                              setState(() {
                                observationLog.clear();         // clear all lines
                                currentLine = '';               // clear active input
                                currentTimestamp = null;        // clear timestamp
                                _elapsedTime = Duration.zero;   // reset visual timer
                              });
                              _elapsedTimer?.cancel();          // stop visual timer from ticking, so that it stays at 00:00
                              _periodicTimer?.cancel();         // stop 3-minute ding timer
                              Navigator.of(context).pop();       // close the dialog
                            },
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            ],
          )
        ],
      ),
      body: Column(
        children: [
          // Top half: fixed-height text field
          Container(
            height: MediaQuery.of(context).size.height * 0.4,
            color: Colors.grey[200],
            padding: EdgeInsets.all(12),
            alignment: Alignment.topLeft,
            child: SingleChildScrollView(
              child: Text(
                fullTextLog,
                style: TextStyle(fontSize: 16),
                textAlign: TextAlign.left,
              ),
            ),
          ),
          Divider(height: 1),
          // Bottom half: Subjects, Behaviors, Enter + Undo
          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(12),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: MediaQuery.of(context).size.height * 0.3,
                ),
                child: IntrinsicHeight(
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
                      ...behaviors.entries.map((entry) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(entry.key, style: TextStyle(fontStyle: FontStyle.italic)),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: entry.value.map((b) {
                                return OutlinedButton(
                                  onPressed: () => addToCurrentLine(b),
                                  child: Text(b),
                                );
                              }).toList(),
                            ),
                            SizedBox(height: 12),
                          ],
                        );
                      }).toList(),
                      Spacer(),
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
              ),
            ),
          )
        ],
      ),
    );
  }

  //this clears any inputs from the homepage when navigating back to it
  @override
  void dispose() {
    super.dispose();
    final homeState = context.findAncestorStateOfType<_HomeScreenState>();
    homeState?._resetObservationInputs();
  }
}
