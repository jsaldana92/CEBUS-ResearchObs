//lib/terms_of_usage_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

class TermsOfUsePage extends StatelessWidget {
  const TermsOfUsePage({super.key});

  Future<String> loadTerms() async {
    return await rootBundle.loadString('assets/text/terms_of_use.txt');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Terms of Use')),
      body: FutureBuilder<String>(
        future: loadTerms(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          } else if (snapshot.hasError) {
            return const Center(child: Text('Failed to load Terms of Use.'));
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
