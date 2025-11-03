import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:permission_handler/permission_handler.dart';
import 'firebase_options.dart';
import 'screens/home_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Request sensor permissions at app launch
  await _requestPermissions();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MainApp());
}

Future<void> _requestPermissions() async {
  print('🔐 Requesting sensor permissions at app launch...');

  // Request all necessary permissions
  final permissions = [
    Permission.sensors,
    Permission.location,
    Permission.locationAlways,
  ];

  for (final permission in permissions) {
    final status = await permission.request();
    print('📱 ${permission.toString()}: ${status.name}');
  }

  print('✅ Permission request completed');
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: HomePage(),
    );
  }
}