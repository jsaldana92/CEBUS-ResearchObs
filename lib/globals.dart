library globals;

List<String> experimenters = [];
List<String> groupNames = [];
Map<String, List<String>> groupMembers = {};

// Collected popup data
String? selectedTimeOfDay;
String? selectedYear;
String? selectedMonth;
String? selectedDay;

List<String> selectedExperimenters = [];       // for checkbox UI
String? selectedExperimenter;                  // for export string

String? selectedLocation;
String? selectedTemperature;
String? selectedWeather;
String? selectedFed;
String? selectedFoodPresent;

List<String> estrousSubjects = [];             // for checkbox UI
String? selectedEstrous;

String? selectedComments;
String? recordedDateAndTime;
