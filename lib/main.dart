import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'screens/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
  } catch (_) {
    // Firebase init failure must not block the app — the WebView handles auth
  }
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Color(0xFF2E6DD4),
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Color(0xFF2E6DD4),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const SoocherDoctorApp());
}

class SoocherDoctorApp extends StatelessWidget {
  const SoocherDoctorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Soocher Doctor',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2E6DD4),
        ),
        useMaterial3: true,
      ),
      home: const SplashScreen(),
    );
  }
}
