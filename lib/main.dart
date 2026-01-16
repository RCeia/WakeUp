import 'package:flutter/material.dart';

void main() {
  runApp(const WakeUpApp());
}

class WakeUpApp extends StatelessWidget {
  const WakeUpApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WakeUp',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const Scaffold(
        body: Center(
          child: Text("WakeUp - Pronto para começar"),
        ),
      ),
    );
  }
}