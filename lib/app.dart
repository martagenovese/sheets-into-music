import 'package:flutter/material.dart';
import 'package:sheets_into_music/src/ui/home_page.dart';

/// Root app widget and app-level theme configuration.
class SheetToSoundApp extends StatelessWidget {
  const SheetToSoundApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Sheets Into Music',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const HomePage(),
    );
  }
}
