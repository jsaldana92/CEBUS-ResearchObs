import 'package:flutter/material.dart';
import 'package:audioplayers/audioplayers.dart'; //this is to play audio file
import 'storage_service.dart'; // this is specifically to call the storage in lib
import 'globals.dart' as globals;
import 'settings_page.dart';
import 'observation_page.dart';
import 'storage_page.dart';
import 'navigation_helpers.dart';







void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  globals.experimenters = await StorageService.loadList('experimenters');

  globals.experimenters = await StorageService.loadList('experimenters');
  if (globals.experimenters.isEmpty && !(await StorageService.hasKey('experimenters'))) {
    globals.experimenters = ['JS', 'MHB', 'GH', 'SS', 'PP'];
    await StorageService.saveList('experimenters', globals.experimenters);
  }

  globals.groupNames = await StorageService.loadList('groupNames');
  if (globals.groupNames.isEmpty) {
    globals.groupNames = ['Logan', 'Griffin', 'Nkima', 'Mason', 'Liam', 'Attila'];
    await StorageService.saveList('groupNames', globals.groupNames);
  }

  globals.groupMembers = await StorageService.loadMap('groupMembers');
  if (globals.groupMembers.isEmpty) {
    globals.groupMembers = {
      'Logan': ['Logan', 'Ivory', 'Ira', 'Paddy', 'Irene', 'Ingrid'],
      'Griffin': ['Griffin', 'Lily', 'Lexi', 'Wren', 'Widget'],
      'Nkima': ['Nkima', 'Nala', 'Gambit', 'Lychee'],
      'Mason': ['Mason', 'Gonzo', 'Gretel', 'Beeker', 'Benny', 'Bias', 'Bailey'],
      'Liam': ['Liam', 'Isabelle', 'Applesauce', 'Scarlett'],
      'Attila': ['Attila', 'Albert'],
    };
    await StorageService.saveMap('groupMembers', globals.groupMembers);
  }

  runApp(ResearchObsApp());
}


class ResearchObsApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ResearchObs',
      theme: ThemeData(
        appBarTheme: AppBarTheme(
          backgroundColor: Color(0xFF3c563d),
          elevation: 0,
          iconTheme: IconThemeData(color: Colors.black), // <-- Customize icon color
          titleTextStyle: TextStyle(color: Colors.blue, fontSize: 20), // <-- Title text color
        ),
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: Color(0xFF8eaf8c), // edit this to change all the backgrounds for all pages (https://htmlcolorcodes.com/)
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
  List<String> selectedExperimenters = []; // used for checkbox selection
  List<String> estrousSubjects = [];       // used for checkbox selection

//allows the reset of the pop ups if this code is called
  void resetObservationInputs() {
    setState(() {
      globals.selectedTimeOfDay = null;
      globals.selectedYear = null;
      globals.selectedMonth = null;
      globals.selectedDay = null;
      globals.selectedExperimenter = null;
      globals.selectedLocation = null;
      globals.selectedTemperature = null;
      globals.selectedWeather = null;
      globals.selectedFed = null;
      globals.selectedFoodPresent = null;
      globals.selectedEstrous = null;
      globals.selectedComments = null;
      globals.recordedDateAndTime = null;
      selectedExperimenters.clear();
      estrousSubjects.clear();
    });
  }




  // First dialog: experimenter checkboxes
  // Proceed to next dialog after experimenters selected, this is the location (time of day pop-up)
  void _showTimeOfDayDialog(BuildContext context, String groupName) {
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
              Text("What time is it?"),
              SizedBox(width: 48),
            ],
          ),
          content: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.20,
            ),
            child: StatefulBuilder(
              builder: (BuildContext context, StateSetter setDialogState) {
                return Column(
                  children: [
                    ListTile(
                      title: Text("AM"),
                      leading: Radio<String>(
                        value: 'AM',
                        groupValue: globals.selectedTimeOfDay,
                        onChanged: (value) {
                          setDialogState(() {
                            globals.selectedTimeOfDay = value;
                            globals.selectedTimeOfDay = value;
                          });
                        },
                      ),
                    ),
                    ListTile(
                      title: Text("PM"),
                      leading: Radio<String>(
                        value: 'PM',
                        groupValue: globals.selectedTimeOfDay,
                        onChanged: (value) {
                          setDialogState(() {
                            globals.selectedTimeOfDay = value;
                          });
                        },
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: globals.selectedTimeOfDay != null
                            ? () {
                          Navigator.of(context).pop();
                          _showDateDialog(context, groupName);
                        }
                            : null,
                        child: Text("Next"),
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

  void _showDateDialog(BuildContext context, String groupName) {
    final TextEditingController yearController = TextEditingController();
    final TextEditingController monthController = TextEditingController();
    final TextEditingController dayController = TextEditingController();

    bool isValidDate(String y, String m, String d) {
      return y.length == 4 && m.length == 2 && d.length == 2;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setDialogState) {
            void checkAndProceed() {
              final y = yearController.text;
              final m = monthController.text.padLeft(2, '0');
              final d = dayController.text.padLeft(2, '0');

              if (isValidDate(y, m, d)) {
                setState(() {
                  globals.selectedYear = y;
                  globals.selectedMonth = m;
                  globals.selectedDay = d;

                  globals.selectedYear = y;
                  globals.selectedMonth = m;
                  globals.selectedDay = d;
                });
                Navigator.of(context).pop();
                _showExperimenterDialog(context, groupName);
              }
            }

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
                  Text("What is today's date?"),
                  SizedBox(width: 48),
                ],
              ),
              content: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.30,
                ),
                child: Column(
                  children: [
                    TextField(
                      controller: yearController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: "Year (e.g. 2025)"),
                      onChanged: (_) => setDialogState(() {}),
                    ),
                    TextField(
                      controller: monthController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: "Month (e.g. 05)"),
                      onChanged: (_) => setDialogState(() {}),
                    ),
                    TextField(
                      controller: dayController,
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(labelText: "Day (e.g. 02)"),
                      onChanged: (_) => setDialogState(() {}),
                    ),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: isValidDate(
                            yearController.text,
                            monthController.text.padLeft(2, '0'),
                            dayController.text.padLeft(2, '0'))
                            ? checkAndProceed
                            : null,
                        child: Text("Next"),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }


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
                          children: globals.experimenters.map((exp) {
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
                          globals.selectedExperimenter = selectedExperimenters.join(', ');
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



  // proceed to the location pop-up
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
              maxHeight: MediaQuery.of(context).size.height * 0.20, // 20% of screen height
            ),
            child: StatefulBuilder(
              builder: (BuildContext context, StateSetter setDialogState) {
                return Column(
                  children: [
                    ListTile(
                      title: Text("Inside"),
                      leading: Radio<String>(
                        value: "Inside",
                        groupValue: globals.selectedLocation,
                        onChanged: (value) {
                          setDialogState(() {
                            globals.selectedLocation = value!;
                            globals.selectedLocation = value;
                          });
                        },
                      ),
                    ),
                    ListTile(
                      title: Text("Outside"),
                      leading: Radio<String>(
                        value: "Outside",
                        groupValue: globals.selectedLocation,
                        onChanged: (value) {
                          setDialogState(() {
                            globals.selectedLocation = value!;
                          });
                        },
                      ),
                    ),
                    SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        child: Text("Next"),
                        onPressed: globals.selectedLocation != null
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
                    resetObservationInputs();
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
                    globals.selectedTemperature = _tempController.text;
                  });
                  Navigator.of(context).pop();
                  _showWeatherConditionDialog(context, groupName); //links to the next pop up (fed or not?)
                }
              },
            ),
          ],
        );
      },
    );
  }

  // starts weather condition pop up
  void _showWeatherConditionDialog(BuildContext context, String groupName) {
    TextEditingController _weatherController = TextEditingController();

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
              Text("Weather condition (optional)"),
              SizedBox(width: 48),
            ],
          ),
          content: TextField(
            controller: _weatherController,
            decoration: InputDecoration(
              hintText: "e.g. Sunny, Cloudy, Raining",
            ),
          ),
          actions: [
            TextButton(
              child: Text("Next"),
              onPressed: () {
                setState(() {
                  globals.selectedWeather = _weatherController.text.trim();
                });
                Navigator.of(context).pop();
                _showFedDialog(context, groupName);
              },
            ),
          ],
        );
      },
    );
  }

  //next pop up where fed or not is asked
  void _showFedDialog(BuildContext context, String groupName) {
    bool? isFed;

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
              Text("Fed?"),
              SizedBox(width: 48),
            ],
          ),
          content: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.20, // ✅ added
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
                            globals.selectedFed = 'Yes';
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
                            globals.selectedFed = 'No';
                          });
                        },
                      ),
                    ),
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
    bool? isFoodPresent;

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
              Text("Food in the Enclosure?"),
              SizedBox(width: 48),
            ],
          ),
          content: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.20, // ✅ added
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
                            globals.selectedFoodPresent = 'Yes';
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
                            globals.selectedFoodPresent = 'No';
                          });
                        },
                      ),
                    ),
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
    final List<String> members = globals.groupMembers[groupName] ?? [];

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
                                  globals.selectedEstrous = estrousSubjects.join(', ');
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
                  globals.selectedComments = _commentController.text.trim();
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
        backgroundColor: Colors.transparent, // 👈 override to transparent
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Text(''), // leave blank if you want no text
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
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final screenWidth = constraints.maxWidth;
                      return Image.asset(
                        'assets/images/welcome_logo.png',
                        width: constraints.maxWidth * 0.8,
                        fit: BoxFit.contain,
                      );
                    },
                  ),
                  SizedBox(height: 16),
                  Text(
                    'Choose a group:',
                    style: TextStyle(fontSize: 16),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 24),
                  ...globals.groupNames.map((name) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6.0),
                    child: ElevatedButton(
                      onPressed: () {
                        _audioPlayer.play(AssetSource('sounds/button_press.mp3'));
                        resetObservationInputs();
                        _showTimeOfDayDialog(context, name);
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
        ],
      ),
      bottomNavigationBar: BottomAppBar(
        elevation: 0,
        color: Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Storage Button
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () async {
                  await Navigator.of(context).push(
                    createSlideRoute(StoragePage(), fromLeft: false),
                  );
                },
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Image.asset(
                      'assets/icon/storage_icon.png',
                      width: 60,
                      height: 60,
                    ),
                    Text(
                      'Storage',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        shadows: [
                          Shadow(
                            blurRadius: 3,
                            color: Colors.black,
                            offset: Offset(1, 1),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Settings Button
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () async {
                  await Navigator.of(context).push(
                    createSlideRoute(SettingsPage(), fromLeft: false),
                  );
                  setState(() {});
                },
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Image.asset(
                      'assets/icon/settings_icon.png',
                      width: 60,
                      height: 60,
                    ),
                    Text(
                      'Settings',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        shadows: [
                          Shadow(
                            blurRadius: 3,
                            color: Colors.black,
                            offset: Offset(1, 1),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

