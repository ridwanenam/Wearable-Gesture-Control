// dashboard_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_application_1/controllers/ble_controller.dart';

// Widget pembantu untuk menghitung mundur durasi waktu secara real-time (Figma Style)
class TimeAgoText extends StatefulWidget {
  final DateTime timestamp;
  const TimeAgoText({super.key, required this.timestamp});

  @override
  State<TimeAgoText> createState() => _TimeAgoTextState();
}

class _TimeAgoTextState extends State<TimeAgoText> {
  Timer? _timer;
  String _timeAgo = '0.00s ago';

  @override
  void initState() {
    super.initState();
    _updateTime();
    // Mengupdate teks setiap 100 milidetik demi akurasi telemetri impulsif
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) => _updateTime());
  }

  void _updateTime() {
    if (!mounted) return;
    final diff = DateTime.now().difference(widget.timestamp);
    setState(() {
      if (diff.inSeconds < 1) {
        double secs = diff.inMilliseconds / 1000;
        _timeAgo = '${secs.toStringAsFixed(2)}s ago';
      } else {
        _timeAgo = '${diff.inSeconds}s ago';
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      _timeAgo,
      style: const TextStyle(color: Colors.grey, fontSize: 12, fontFamily: 'Courier'),
    );
  }
}



class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  // Notifier untuk menampung sisa detik pencarian perangkat
  final ValueNotifier<int> _scanCountdown = ValueNotifier<int>(10);
  Timer? _countdownTimer;

  void _startUiCountdown() {
    _countdownTimer?.cancel();
    _scanCountdown.value = 10; // Reset ke angka awal 10 detik
    
    // REVISI DI SINI: Ubah dari seconds: 10 menjadi seconds: 1
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_scanCountdown.value > 0) {
        _scanCountdown.value--; // Ini akan berkurang lancar: 9, 8, 7... setiap 1 detik
      } else {
        timer.cancel();
      }
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _scanCountdown.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bleController = Provider.of<BLEController>(context);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text(
          'GestureSync',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: bleController.isConnected ? Colors.green : Colors.red,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  bleController.isConnected ? 'Active' : 'Offline',
                  style: TextStyle(
                    color: bleController.isConnected ? Colors.green : Colors.red,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          )
        ],
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF121417),
        elevation: 0,
        shape: const Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'BLUETOOTH CONNECTION',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 0.5),
            ),
            const SizedBox(height: 8),
            


            // CARD STATUS KONEKSI (VERSI COUNTDOWN REAL-TIME)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: bleController.isConnected
                              ? const Color(0xFF0052FF).withValues(alpha: 0.1)
                              : Colors.grey.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.bluetooth,
                          color: bleController.isConnected ? const Color(0xFF0052FF) : Colors.grey,
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Arduino Nano RP2040',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                            const SizedBox(height: 2),
                            // Widget ValueListenableBuilder untuk menggerakkan angka hitung mundur tanpa lag
                            ValueListenableBuilder<int>(
                              valueListenable: _scanCountdown,
                              builder: (context, secondsLeft, child) {
                                return Text(
                                  bleController.isConnected
                                      ? 'CONNECTED'
                                      : bleController.isScanning
                                          ? 'Scanning... (${secondsLeft}s)' // Angka akan berubah 10, 9, 8...
                                          : 'DISCONNECTED',
                                  style: TextStyle(
                                    color: bleController.isConnected
                                        ? Colors.green
                                        : bleController.isScanning
                                            ? Colors.orange
                                            : Colors.grey,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: OutlinedButton(
                      onPressed: bleController.isScanning
                          ? null
                          : () {
                              if (bleController.isConnected) {
                                bleController.disconnectDevice();
                              } else {
                                // Memicu pewaktu hitung mundur lokal 10 detik di UI
                                _startUiCountdown();
                                bleController.startBLEScan();
                              }
                            },
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                          color: bleController.isConnected ? Colors.redAccent : const Color(0xFF0052FF),
                        ),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      child: Text(
                        bleController.isConnected
                            ? 'Disconnect'
                            : bleController.isScanning
                                ? 'SCANNING...'
                                : 'Connect Device',
                        style: TextStyle(
                          color: bleController.isConnected ? Colors.redAccent : const Color(0xFF0052FF),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),





            const SizedBox(height: 24),
            const Text(
              'LIVE TELEMETRY',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 0.5),
            ),
            const SizedBox(height: 8),

            // AREA LIVE STREAM GESTUR (FIGMA STYLE WITH TIME AGO)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Incoming Signal Stream',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0052FF).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.fiber_manual_record, color: Color(0xFF0052FF), size: 10),
                            SizedBox(width: 4),
                            Text(
                              'LIVE',
                              style: TextStyle(color: Color(0xFF0052FF), fontSize: 10, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 24, color: Color(0xFFE2E8F0)),
                  
                  bleController.telemetryLogs.isEmpty
                      ? const SizedBox(
                          height: 120,
                          child: Center(
                            child: Text(
                              'No micro-gesture detected yet.',
                              style: TextStyle(color: Colors.grey, fontSize: 13),
                            ),
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: bleController.telemetryLogs.length,
                          itemBuilder: (context, index) {
                            // Membalik index agar data mikro-gestur terbaru berada di baris teratas figma
                            final log = bleController.telemetryLogs[
                                bleController.telemetryLogs.length - 1 - index];
                            
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6.0),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    log.signal,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF0052FF),
                                      fontFamily: 'Courier',
                                      fontSize: 14,
                                    ),
                                  ),
                                  TimeAgoText(timestamp: log.timestamp),
                                ],
                              ),
                            );
                          },
                        ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            const Text(
              'INTERNAL SYSTEM LOGS (DEBUG CONSOLE)',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 0.5),
            ),
            const SizedBox(height: 8),

            // KOTAK KONSOL STATUS SYSTEM & TIMEOUT SCANNING
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B), // Warna Slate Gelap khas terminal lab
                  borderRadius: BorderRadius.circular(8),
                ),
                child: bleController.systemLogs.isEmpty
                    ? const Text(
                        'System idle. Press Connect to test timeout handler.',
                        style: TextStyle(color: Colors.white60, fontSize: 12, fontFamily: 'Courier'),
                      )
                    : ListView.builder(
                        reverse: true, // Log terbaru bergulir otomatis ke bawah terminal
                        itemCount: bleController.systemLogs.length,
                        itemBuilder: (context, index) {
                          final sysMsg = bleController.systemLogs[
                              bleController.systemLogs.length - 1 - index];
                          
                          Color msgColor = Colors.white.withValues(alpha: 0.8);
                          if (sysMsg.contains('[SUCCESS]')) msgColor = Colors.greenAccent;
                          if (sysMsg.contains('[WARN]')) msgColor = Colors.amberAccent;
                          if (sysMsg.contains('[ERROR]')) msgColor = Colors.redAccent;

                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2.0),
                            child: Text(
                              sysMsg,
                              style: TextStyle(color: msgColor, fontSize: 11, fontFamily: 'Courier'),
                            ),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

