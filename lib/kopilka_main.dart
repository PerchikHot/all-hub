import 'package:flutter/material.dart';
import 'kopilka_page.dart';

void main() => runApp(const KopilkaApp());

class KopilkaApp extends StatelessWidget {
  const KopilkaApp({super.key});

  @override
  Widget build(BuildContext context) {
    const background = Color(0xFF081323);
    const panel = Color(0xFF142844);
    const accent = Color(0xFF68C5FF);
    final colors = ColorScheme.fromSeed(
      seedColor: accent, brightness: Brightness.dark,
      surface: panel,
    );
    return MaterialApp(
      title: 'Копилка',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorScheme: colors,
        scaffoldBackgroundColor: background,
        appBarTheme: const AppBarTheme(
          backgroundColor: background,
          surfaceTintColor: Colors.transparent,
        ),
        cardTheme: CardThemeData(
          color: panel,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Color(0xFF2C5279)),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF192E4B),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(15),
            borderSide: BorderSide.none,
          ),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: accent,
          foregroundColor: background,
        ),
      ),
      home: const KopilkaPage(),
    );
  }
}
