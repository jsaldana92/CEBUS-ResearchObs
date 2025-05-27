//lib/privacy_policy_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});

  Future<String> loadPrivacyPolicy() async {
    return await rootBundle.loadString('assets/text/privacy_policy.txt');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy Policy')),
      body: FutureBuilder<String>(
        future: loadPrivacyPolicy(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return const Center(child: Text('Failed to load Privacy Policy.'));
          } else {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: SingleChildScrollView(
                child: Text(snapshot.data ?? '', style: const TextStyle(fontSize: 16)),
              ),
            );
          }
        },
      ),
    );
  }
}
