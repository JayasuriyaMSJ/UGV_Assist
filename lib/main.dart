import 'package:amr_assist/init_dependencies.dart';
import 'package:amr_assist/robot_selector.dart';
import 'package:flutter/material.dart';

void main() async {
  await init_dependencies();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AMR Assist',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color.fromARGB(255, 30, 63, 172),
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: Colors.grey[900],
      ),
      home: const RobotSelector(),
    );
  }
}

