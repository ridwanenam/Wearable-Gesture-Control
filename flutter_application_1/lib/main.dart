// main.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_application_1/controllers/ble_controller.dart';
import 'package:flutter_application_1/screens/main_navigation.dart';

void main() {
  // Memastikan sistem framework Flutter terikat sempurna sebelum menjalankan aplikasi
  WidgetsFlutterBinding.ensureInitialized();
  
  runApp(
    // Membungkus aplikasi dengan MultiProvider agar state BLEController bersifat global
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => BLEController()),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GestureSync Wearable App',
      debugShowCheckedModeBanner: false,
      
      // Konfigurasi tema global agar serasi dengan skema mockup figma Anda
      theme: ThemeData(
        useMaterial3: true, // Ramah target Android API 34 secara bawaan
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0052FF),
          primary: const Color(0xFF0052FF),
          surface: const Color(0xFFF8F9FA),
        ),
        scaffoldBackgroundColor: const Color(0xFFF8F9FA),
        fontFamily: 'Sans-Serif', // Menggunakan font bawaan sistem yang bersih
      ),
      
      // Mengarahkan langsung ke halaman struktur navigasi utama
      home: const MainNavigation(),
    );
  }
}
