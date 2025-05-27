//lib/about_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;


class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  Future<String> loadAboutText() async {
    return await rootBundle.loadString('assets/text/about_researchobs.txt');
  }

  void showPolicyDialog(BuildContext context, String title, String assetPath) async {
    final text = await rootBundle.loadString(assetPath);
    showDialog(
      context: context,
      builder: (BuildContext context) {
        final screenSize = MediaQuery.of(context).size;
        return Dialog(
          insetPadding: EdgeInsets.zero,  // 👈 No forced margin
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Container(
            width: screenSize.width * 0.9,
            height: screenSize.height * 0.9,
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(title,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center),
                const Divider(),
                Expanded(
                  child: SingleChildScrollView(
                    child: Text(text, style: const TextStyle(fontSize: 14)),
                  ),
                ),
                Align(
                  alignment: Alignment.bottomRight,
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
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
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () {
              showPolicyDialog(context, 'Privacy Policy', 'assets/text/privacy_policy.txt');
            },
            child: const Text('Privacy Policy'),
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: () {
              showPolicyDialog(context, 'Terms of Use', 'assets/text/terms_of_use.txt');
            },
            child: const Text('Terms of Use'),
          ),
        ],
      ),
    );
  }
}
