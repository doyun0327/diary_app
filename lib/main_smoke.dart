import 'package:flutter/material.dart';

/// 크래시 진단용. 이 화면만 뜨면 Flutter/서명/기기 문제는 아님.
/// 빌드: flutter build apk --release -t lib/main_smoke.dart
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SmokeApp());
}

class SmokeApp extends StatelessWidget {
  const SmokeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: Color(0xFFFFF8F0),
        body: Center(
          child: Text(
            'SMOKE OK\npageBy 1.0.0+5',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 28, height: 1.4),
          ),
        ),
      ),
    );
  }
}
