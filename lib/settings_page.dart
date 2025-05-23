// lib/settings_page.dart
import 'package:flutter/material.dart';
import 'storage_service.dart';
import 'globals.dart';
import 'dropbox_oauth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;


class SettingsPage extends StatefulWidget {
  @override
  _SettingsPageState createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String? dropboxEmail;
  String? dropboxName;

  @override
  void initState() {
    super.initState();
    _loadDropboxAccountInfo();
  }

  Future<void> _loadDropboxAccountInfo() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('dropbox_access_token');
    if (token == null || token.isEmpty) return;

    final response = await http.post(
      Uri.parse('https://api.dropboxapi.com/2/users/get_current_account'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': '',
      },
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      setState(() {
        dropboxEmail = data['email'];
        dropboxName = data['name']['display_name'];
      });
    } else {
      print('Failed to fetch Dropbox account info: ${response.body}');
    }
  }

  Future<void> _logoutDropbox() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('dropbox_access_token');
    setState(() {
      dropboxEmail = null;
      dropboxName = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(24.0),
        children: [
          Text('Settings', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          SizedBox(height: 16),
          ElevatedButton.icon(
            icon: Icon(Icons.group),
            label: Text('Manage Groups'),
            onPressed: () {
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => ManageGroupsPage()));
            },
          ),
          SizedBox(height: 12),
          ElevatedButton.icon(
            icon: Icon(Icons.people_alt),
            label: Text('Edit Group Members'),
            onPressed: () {
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => EditGroupMembersPage()));
            },
          ),
          SizedBox(height: 12),
          ElevatedButton.icon(
            icon: Icon(Icons.edit_note),
            label: Text('Edit Experimenters'),
            onPressed: () {
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => EditExperimentersPage()));
            },
          ),
          SizedBox(height: 12),
          ElevatedButton.icon(
            icon: Icon(Icons.bug_report),
            label: Text('Edit Behaviors'),
            onPressed: () {
              Navigator.of(context).push(MaterialPageRoute(builder: (_) => EditBehaviorsPage()));
            },
          ),
          SizedBox(height: 12),
          ElevatedButton.icon(
            icon: Icon(Icons.cloud_upload),
            label: Text('Log in to Dropbox'),
            onPressed: () async {
              try {
                print('▶️ Starting Dropbox authentication...');
                await DropboxOAuthService.authenticate();
                print('✅ Authentication completed.');
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('✅ Logged into Dropbox!')),
                );
                _loadDropboxAccountInfo();
              } catch (e) {
                print('❌ Dropbox login failed: \$e');
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('❌ Dropbox login failed: \$e')),
                );
              }
            },
          ),
          SizedBox(height: 24),
          if (dropboxName != null && dropboxEmail != null) ...[
            Text('Logged in as:', style: TextStyle(fontWeight: FontWeight.bold)),
            Text('Name: $dropboxName'),
            Text('Email: $dropboxEmail'),
            SizedBox(height: 12),
            ElevatedButton.icon(
              icon: Icon(Icons.logout),
              label: Text('Log out of Dropbox'),
              onPressed: _logoutDropbox,
            ),
          ] else ...[
            Text('No Dropbox user logged in.', style: TextStyle(color: Colors.grey)),
          ]
        ],
      ),
    );
  }
}

class EditBehaviorsPage extends StatefulWidget {
  @override
  _EditBehaviorsPageState createState() => _EditBehaviorsPageState();
}

class _EditBehaviorsPageState extends State<EditBehaviorsPage> {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Edit Behaviors')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ...behaviors.entries.map((entry) {
            final behavior = entry.key;
            final nested = entry.value;
            return Card(
              elevation: 3,
              margin: EdgeInsets.only(bottom: 16),
              child: ExpansionTile(
                title: Text(behavior),
                trailing: behavior != 'Note+'
                    ? IconButton(
                  icon: Icon(Icons.delete, color: Colors.red),
                  onPressed: () {
                    setState(() {
                      behaviors.remove(behavior);
                    });
                  },
                )
                    : null,
                children: [
                  if (nested is List<String>)
                    ...nested.map((sub) => ListTile(
                      title: Text(sub),
                      trailing: IconButton(
                        icon: Icon(Icons.delete, color: Colors.red),
                        onPressed: () {
                          setState(() {
                            nested.remove(sub);
                          });
                        },
                      ),
                    )),
                  if (nested is List<String>)
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: TextButton.icon(
                        icon: Icon(Icons.add),
                        label: Text('Add Sub-behavior'),
                        onPressed: () async {
                          final subController = TextEditingController();
                          final result = await showDialog<String>(
                            context: context,
                            builder: (_) => AlertDialog(
                              title: Text('New Sub-behavior'),
                              content: TextField(controller: subController),
                              actions: [
                                TextButton(
                                  child: Text('Add'),
                                  onPressed: () => Navigator.pop(context, subController.text),
                                )
                              ],
                            ),
                          );
                          if (result != null && result.trim().isNotEmpty) {
                            setState(() {
                              nested.add(result.trim());
                            });
                          }
                        },
                      ),
                    ),
                  if (nested == null)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: TextButton.icon(
                        icon: Icon(Icons.edit),
                        label: Text('Convert to Nested'),
                        onPressed: () {
                          setState(() {
                            behaviors[behavior] = <String>[];
                          });
                        },
                      ),
                    ),
                ],
              ),
            );
          }),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: ElevatedButton.icon(
              icon: Icon(Icons.add),
              label: Text('Add New Behavior'),
              onPressed: () async {
                final controller = TextEditingController();
                final result = await showDialog<String>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: Text('New Behavior'),
                    content: TextField(controller: controller),
                    actions: [
                      TextButton(
                        child: Text('Add'),
                        onPressed: () => Navigator.pop(context, controller.text),
                      )
                    ],
                  ),
                );
                if (result != null && result.trim().isNotEmpty) {
                  setState(() {
                    behaviors[result.trim()] = null;
                  });
                }
              },
            ),
          ),
        ],
      ),
    );
  }
}



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
                    await StorageService.saveMap('groupMembers', groupMembers);
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
