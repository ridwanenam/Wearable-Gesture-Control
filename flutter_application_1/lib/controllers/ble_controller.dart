// ble_controller.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'dart:io' show Platform;
import 'package:permission_handler/permission_handler.dart';


// Model data terstruktur khusus untuk meniru tampilan log telemetri figma
class TelemetryLog {
  final String signal;
  final DateTime timestamp;
  TelemetryLog({required this.signal, required this.timestamp});
}

class BLEController with ChangeNotifier {
  // State dasar koneksi BLE
  bool _isConnected = false;
  bool _isScanning = false;
  String _lastReceivedSignal = "IDLE";
  
  // Array terstruktur baru untuk melacak riwayat mikro-gestur secara real-time
  final List<TelemetryLog> _telemetryLogs = [];
  final List<String> _systemLogs = []; // Untuk mencatat pesan error/start sistem

  // Bluetooth internal properties ramah versi 1.31.15
  BluetoothDevice? _targetDevice;
  BluetoothCharacteristic? _targetCharacteristic;
  StreamSubscription<List<int>>? _valueSubscription;
  Timer? _scanTimeoutTimer; // Timer internal untuk mengunci timeout pemindaian

  // Properti krusial pembatas fitur (Anti-Tabrakan Antar Halaman)
  int _currentActiveTab = 0; // 0: Dashboard, 1: Presentation, 2: Camera

  final String _targetDeviceName = "Wearable_Gesture_Controller";
  
  // UUID Layan dan Karakteristik khusus untuk transmisi data gestur RP2040
  final String _serviceUuid = "4fafc201-1fb5-459e-8fcc-c5c9c331914b";
  final String _characteristicUuid = "beb5483e-36e1-4688-b7f5-ea07361b26a8";
  
  // Getters publik untuk dikonsumsi widget UI (Provider)
  bool get isConnected => _isConnected;
  bool get isScanning => _isScanning;
  List<TelemetryLog> get telemetryLogs => _telemetryLogs;
  List<String> get systemLogs => _systemLogs;
  int get currentActiveTab => _currentActiveTab;

  // Setter untuk memberi tahu controller posisi tab yang sedang dibuka user
  void setActiveTab(int index) {
    _currentActiveTab = index;
    notifyListeners();
  }

  // Getter reaktif: mendistribusikan sinyal hanya jika tab pengeksekusi sesuai
  String get lastReceivedSignal {
    String currentSignal = _lastReceivedSignal;
    if (_lastReceivedSignal != "IDLE") {
      _lastReceivedSignal = "IDLE"; // Langsung reset demi mencegah multi-trigger
    }
    return currentSignal;
  }

  // Setter manual untuk kebutuhan tombol testing darurat per halaman
  set lastReceivedSignal(String value) {
    _lastReceivedSignal = value;
  }

  // Fungsi mencatat interupsi sinyal masuk terstruktur
  void addTelemetryLog(String signalValue) {
    _telemetryLogs.add(TelemetryLog(
      signal: signalValue,
      timestamp: DateTime.now(),
    ));
    
    // Batasi riwayat maksimal 5 baris teratas seperti pada figma mockup
    if (_telemetryLogs.length > 5) {
      _telemetryLogs.removeAt(0);
    }
    notifyListeners();
  }

  // Fungsi mencatat log sistem internal aplikasi
  void addSystemLog(String message) {
    String timeStr = DateTime.now().toString().split(' ').last.substring(0, 8);
    _systemLogs.add("[$timeStr] $message");
    if (_systemLogs.length > 20) {
      _systemLogs.removeAt(0);
    }
    notifyListeners();
  }

  Future<void> startBLEScan() async {
    if (_isScanning || _isConnected) return;

    // =========================================================================
    // PROTECTION: Paksa Minta Izin Lokasi & Nearby Devices (Wajib untuk rilis APK Android 14)
    // =========================================================================
    if (Platform.isAndroid) {
      Map<Permission, PermissionStatus> statuses = await [
        Permission.location,
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
      ].request();

      if (statuses[Permission.location] != PermissionStatus.granted ||
          statuses[Permission.bluetoothScan] != PermissionStatus.granted ||
          statuses[Permission.bluetoothConnect] != PermissionStatus.granted) {
        addSystemLog("[ERROR] Izin Bluetooth/Lokasi Ditolak oleh Sistem HP!");
        notifyListeners();
        return; 
      }
    }
    // =========================================================================

    _isScanning = true;
    _systemLogs.clear();
    _telemetryLogs.clear();
    addSystemLog("[START] Mencari perangkat '$_targetDeviceName'...");
    notifyListeners();

    // Mengaktifkan pewaktu 10 detik guna menghindari pemindaian tanpa akhir
    _scanTimeoutTimer?.cancel();
    _scanTimeoutTimer = Timer(const Duration(seconds: 10), () async {
      if (_isScanning && !_isConnected) {
        await FlutterBluePlus.stopScan();
        _isScanning = false;
        addSystemLog("[WARN] Perangkat tidak ditemukan. Menghentikan pencarian.");
        notifyListeners();
      }
    });

    try {
      await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));

      // REVISI TOTAL BLOK LISTEN SCAN RESULTS PADA PAGE 4:
      FlutterBluePlus.scanResults.listen((results) async {
        for (ScanResult r in results) {
          
          // UBAH LOGIKA DI SINI: Deteksi kesamaan UUID Layanan di dalam daftar paket iklan
          bool hasTargetService = r.advertisementData.serviceUuids.any(
            (uuid) => uuid.toString().toLowerCase() == _serviceUuid.toLowerCase()
          );

          // Filter cadangan: jika UUID cocok ATAU nama teksnya sesuai
          if (hasTargetService || r.device.platformName == _targetDeviceName || r.advertisementData.advName == _targetDeviceName) {
            _scanTimeoutTimer?.cancel(); 
            await FlutterBluePlus.stopScan();
            _isScanning = false;
            addSystemLog("[FOUND] Arduino Terdeteksi via UUID! Mengoneksikan...");
            notifyListeners();
            _connectToDevice(r.device);
            break;
          }
        }
      });
    } catch (e) {
      _scanTimeoutTimer?.cancel();
      _isScanning = false;
      addSystemLog("[ERROR] Gagal memindai: $e");
      notifyListeners();
    }
  }

Future<void> _connectToDevice(BluetoothDevice device) async {
  try {
    _targetDevice = device;
    
    // 1. Lakukan koneksi dasar dengan timeout pengaman
    await _targetDevice!.connect(autoConnect: false).timeout(const Duration(seconds: 5));
    
    _isConnected = true;
    addSystemLog("[SUCCESS] Terhubung ke $_targetDeviceName!");
    notifyListeners();

    // =========================================================================
    // SOLUSI PENYEBAB 3: Negosiasi MTU Khusus Android API 34 (Wajib sebelum Discover)
    // =========================================================================
    try {
      if (Platform.isAndroid) {
        addSystemLog("[MTU] Menegosiasikan ukuran paket data (MTU)...");
        await _targetDevice!.requestMtu(512); // Membuka jalur data maksimal agar tidak tersedak
        await Future.delayed(const Duration(milliseconds: 500)); // Beri jeda hardware untuk bernapas
      }
    } catch (mtuError) {
      debugPrint("Gagal request MTU (Aman untuk dilewati): $mtuError");
    }

    // 2. Ambil daftar layanan dari Arduino Nano RP2040
    addSystemLog("[DISCOVER] Membaca struktur UUID layanan...");
    List<BluetoothService> services = await _targetDevice!.discoverServices();
    
    for (BluetoothService service in services) {
      // PAKSA TO LOWERCASE AGAR COCOK DENGAN FORMAT ARDUINO
      if (service.uuid.toString().toLowerCase() == _serviceUuid.toLowerCase()) { 
        for (BluetoothCharacteristic characteristic in service.characteristics) {
          // PAKSA TO LOWERCASE JUGA DI SINI
          if (characteristic.uuid.toString().toLowerCase() == _characteristicUuid.toLowerCase()) { 
            _targetCharacteristic = characteristic;
            
            // 3. Daftarkan listener notifikasi aliran data biner dari Arduino
            await _targetCharacteristic!.setNotifyValue(true);
            
            // Bersihkan langganan lama jika ada untuk mencegah memori bocor
            await _valueSubscription?.cancel();
            
            _valueSubscription = _targetCharacteristic!.onValueReceived.listen((value) {
              String receivedString = utf8.decode(value).trim();
              if (receivedString.isNotEmpty) {
                if (_currentActiveTab != 0) { 
                  _lastReceivedSignal = receivedString; 
                }
                addTelemetryLog(receivedString);
                notifyListeners(); // Pastikan UI ter-update saat data masuk!
              }
            });
            
            addSystemLog("[READY] Handshake UUID Sukses. Menunggu gestur...");
            notifyListeners();
            return;
          }
        }
      }
    }
    
    // Jika loop selesai tapi UUID tidak cocok
    addSystemLog("[WARN] Terhubung, tetapi UUID Layanan/Karakteristik tidak cocok!");
    
  } catch (e) {
    _isConnected = false;
    addSystemLog("[ERROR] Gagal menyambungkan: $e");
    notifyListeners();
  }
}


  // Fungsi injeksi terpadu untuk tombol simulasi darurat per halaman
  void injectSimulatedSignal(String signalValue) {
    // Sinyal hanya masuk ke filter eksekusi jika pengguna tidak sedang di dashboard (tab 0)
    if (_currentActiveTab != 0) {
      _lastReceivedSignal = signalValue;
    }
    addTelemetryLog(signalValue);
  }

  // Memutuskan hubungan koneksi bluetooth secara total dan bersih
  Future<void> disconnectDevice() async {
    _scanTimeoutTimer?.cancel();
    await _valueSubscription?.cancel();
    _valueSubscription = null;
    
    if (_targetCharacteristic != null) {
      try { await _targetCharacteristic!.setNotifyValue(false); } catch (_) {}
      _targetCharacteristic = null;
    }

    if (_targetDevice != null) {
      try { await _targetDevice!.disconnect(); } catch (_) {}
      _targetDevice = null;
    }

    _isConnected = false;
    _isScanning = false;
    _lastReceivedSignal = "IDLE";
    addSystemLog("[OFFLINE] Koneksi diputus total.");
    notifyListeners();
  }

  @override
  void dispose() {
    _scanTimeoutTimer?.cancel();
    _valueSubscription?.cancel();
    super.dispose();
  }
}
