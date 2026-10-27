import 'package:flutter/material.dart';
import 'kopilka_page.dart';

void main() => runApp(const KopilkaApp());

class KopilkaApp extends StatelessWidget {
  const KopilkaApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Копилка',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF397CFF),
        brightness: Brightness.dark,
      ),
      scaffoldBackgroundColor: const Color(0xFF0A1426),
    ),
    home: const KopilkaPage(),
  );
}
