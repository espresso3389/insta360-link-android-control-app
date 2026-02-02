import "package:flutter/material.dart";

import "src/tracking_page.dart";

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const TrackerApp());
}

class TrackerApp extends StatelessWidget {
  const TrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "Insta360 Link Face Tracker",
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF0E7A6D)),
        useMaterial3: true,
      ),
      home: const TrackingPage(),
    );
  }
}
