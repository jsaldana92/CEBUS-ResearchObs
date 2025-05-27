import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

class AboutPage extends StatelessWidget {
  const AboutPage({super.key}); // ✅ Fixes the weak warning

  Future<String> loadAboutText() async {
    return await rootBundle.loadString('assets/text/about_researchobs.txt');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: true,
        title: const Text(''),
      ),
      body: ListView(
        padding: const EdgeInsets.all(24.0),
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              return Center(
                child: Image.asset(
                  'assets/images/about_logo.png',
                  width: constraints.maxWidth * 0.8,
                  fit: BoxFit.contain,
                ),
              );
            },
          ),
          const SizedBox(height: 24),
          FutureBuilder<String>(
            future: loadAboutText(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              } else if (snapshot.hasError) {
                return const Text('Error loading About text.');
              } else {
                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFd9ded9),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    snapshot.data ?? '',
                    style: const TextStyle(fontSize: 16),
                    textAlign: TextAlign.left,
                  ),
                );
              }
            },
          ),
        ],
      ),
    );
  }
}
