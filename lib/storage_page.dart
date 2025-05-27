// lib/storage_page.dart
import 'package:flutter/material.dart';
import 'globals.dart';
import 'group_storage_page.dart';

class StoragePage extends StatelessWidget {
  const StoragePage({super.key}); // Fixes the warning and supports future performance
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: true,
        title: Text(''), //text left blank to prevent Storage from being shown twice
      ),
      body: ListView(
        padding: const EdgeInsets.all(24.0),
        children: [
          Text(
            'Storage',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 16),
          Text(
            'Select a group to view stored observations:',
            style: TextStyle(fontSize: 16),
          ),
          SizedBox(height: 16),
          ...groupNames.map(
              (group) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 6.0),
                child: ElevatedButton.icon(
                  icon: Icon(Icons.folder_open),
                  label: Text(group),
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => GroupStoragePage(groupName: group),
                      ),
                    );
                  },
                ),
              ),
          ),
        ],
      ),
    );
  }
}