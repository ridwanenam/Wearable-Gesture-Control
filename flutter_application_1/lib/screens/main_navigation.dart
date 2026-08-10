// main_navigation.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_application_1/controllers/ble_controller.dart';
import 'package:flutter_application_1/screens/dashboard_screen.dart';
import 'package:flutter_application_1/screens/presentation_screen.dart';
import 'package:flutter_application_1/screens/camera_screen.dart';

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _selectedIndex = 0;

  // Menyimpan daftar halaman ke dalam array konstan
  final List<Widget> _screens = const [
    DashboardScreen(),
    PresentationScreen(),
    CameraScreen(),
  ];

  void _onItemTapped(int index, BLEController bleController) {
    setState(() {
      _selectedIndex = index;
    });
    // MENYUNTIKKAN STATE INDEX AKTIF KE CONTROLLER (ANTI-TABRAKAN FITUR)
    // 0: Dashboard (Fitur mati), 1: Presentation (Hanya presentasi aktif), 2: Camera (Hanya kamera aktif)
    bleController.setActiveTab(index);
  }

  @override
  Widget build(BuildContext context) {
    // Membaca ketersediaan BLEController di tingkat navigasi
    final bleController = Provider.of<BLEController>(context, listen: false);

    return Scaffold(
      // Menggunakan IndexedStack agar status WebView dan inisialisasi Kamera 
      // tidak ter-reset atau hancur saat Anda berpindah tab menu navigasi
      body: IndexedStack(
        index: _selectedIndex,
        children: _screens,
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(
            top: BorderSide(color: Color(0xFFE2E8F0), width: 1),
          ),
        ),
        child: BottomNavigationBar(
          currentIndex: _selectedIndex,
          onTap: (index) => _onItemTapped(index, bleController),
          backgroundColor: Colors.white,
          selectedItemColor: const Color(0xFF0052FF), // Biru aksen utama
          unselectedItemColor: const Color(0xFF718096), // Abu-abu netral
          selectedFontSize: 12,
          unselectedFontSize: 12,
          type: BottomNavigationBarType.fixed,
          elevation: 0,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.dashboard_outlined),
              activeIcon: Icon(Icons.dashboard),
              label: 'Dashboard',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.slideshow_outlined),
              activeIcon: Icon(Icons.slideshow),
              label: 'Presentation',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.camera_alt_outlined),
              activeIcon: Icon(Icons.camera_alt),
              label: 'Smart Camera',
            ),
          ],
        ),
      ),
    );
  }
}
