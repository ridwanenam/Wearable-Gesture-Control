// camera_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'package:camera/camera.dart';
import 'package:gal/gal.dart';
import 'dart:io';
import 'package:flutter_application_1/controllers/ble_controller.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> with WidgetsBindingObserver {
  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  bool _isCameraInitialized = false;
  
  // State manajemen fitur baru (Kombinasi Kamera & Video)
  bool _isPhotoMode = true; // true: PHOTO, false: VIDEO
  bool _isRecordingVideo = false;
  Timer? _recordingTimer; // Import 'dart:async' otomatis atau gunakan library bawaan
  int _recordingSeconds = 0;
  bool _isProcessingMedia = false;
  String? _lastCapturedMediaPath;


  // Batasan batasan elektrik Zoom level
  double _currentZoomLevel = 1.0;
  double _maxZoomLevel = 5.0;
  double _minZoomLevel = 1.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras.isNotEmpty) {
        _cameraController = CameraController(
          _cameras.first,
          ResolutionPreset.medium,
          enableAudio: true, // Diaktifkan karena sekarang mendukung rekam video
        );

        await _cameraController!.initialize();
        if (!mounted) return;

        // Mengambil batas kapabilitas zoom asli hardware HP Anda
        _maxZoomLevel = await _cameraController!.getMaxZoomLevel();
        _minZoomLevel = await _cameraController!.getMinZoomLevel();

        setState(() {
          _isCameraInitialized = true;
        });
      }
    } catch (e) {
      debugPrint("Gagal inisialisasi hardware kamera: $e");
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final CameraController? camera = _cameraController;
    if (camera == null || !camera.value.isInitialized) return;
    if (state == AppLifecycleState.inactive) {
      camera.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initializeCamera();
    }
  }

  // Logika Eksekusi Fitur Rana Foto/Video Terpadu
  Future<void> _triggerShutterAction() async {
    if (_cameraController == null || !_cameraController!.value.isInitialized || _isProcessingMedia) {
      return;
    }

    if (_isPhotoMode) {
      // 1. MODE FOTO (SINGLE_TAP)
      try {
        setState(() { _isProcessingMedia = true; });
        final XFile imageFile = await _cameraController!.takePicture();
        await Gal.putImage(imageFile.path); // Sinkronisasi Galeri
        setState(() {
          _lastCapturedMediaPath = imageFile.path;
          _isProcessingMedia = false;
        });
        _showSnackbar('📸 Gesture Captured! Foto tersimpan ke galeri.');
      } catch (e) {
        setState(() { _isProcessingMedia = false; });
        debugPrint("Gagal ambil foto: $e");
      }
    } else {
      // 2. MODE VIDEO ON/OFF (SINGLE_TAP)
      if (!_isRecordingVideo) {
        // Mulai Merekam
        try {
          await _cameraController!.startVideoRecording();
          setState(() { 
            _isRecordingVideo = true; 
            _recordingSeconds = 0; // Reset ke 0 tiap mulai rekam
          });
          
          // Jalankan Timer hitungan detik
          _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
            setState(() {
              _recordingSeconds++;
            });
          });

          _showSnackbar('🎥 Video recording started...');
        } catch (e) {
          debugPrint("Gagal rekam video: $e");
        }
      } else {
        // Berhenti Merekam + Simpan ke Galeri
        try {
          setState(() { _isProcessingMedia = true; });
          
          // Hentikan fungsi loop timer
          _recordingTimer?.cancel(); 

          final XFile videoFile = await _cameraController!.stopVideoRecording();
          await Gal.putVideo(videoFile.path); // Sinkronisasi Galeri Video
          setState(() {
            _isRecordingVideo = false;
            _lastCapturedMediaPath = videoFile.path;
            _isProcessingMedia = false;
            _recordingSeconds = 0; // Bersihkan data durasi
          });
          _showSnackbar('✅ Video berhasil disimpan ke galeri.');
        } catch (e) {
          _recordingTimer?.cancel(); // Pengaman jika terjadi error saat stop
          setState(() { _isRecordingVideo = false; _isProcessingMedia = false; });
          debugPrint("Gagal stop video: $e");
        }
      }
    }
  }

  // Fungsi mengubah level perbesaran lensa secara halus (SINGLE_FIST / DOUBLE_FIST)
  Future<void> _setZoom(bool zoomIn) async {
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;
    
    double targetZoom = _currentZoomLevel + (zoomIn ? 0.5 : -0.5);
    if (targetZoom > _maxZoomLevel) targetZoom = _maxZoomLevel;
    if (targetZoom < _minZoomLevel) targetZoom = _minZoomLevel;

    try {
      await _cameraController!.setZoomLevel(targetZoom);
      setState(() {
        _currentZoomLevel = targetZoom;
      });
    } catch (e) {
      debugPrint("Gagal mengatur zoom: $e");
    }
  }

  void _showSnackbar(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2), backgroundColor: const Color(0xFF0052FF)),
    );
  }

@override
void dispose() {
  _recordingTimer?.cancel(); // <--- WAJIB DI SINI (Sebelum super.dispose)
  WidgetsBinding.instance.removeObserver(this); //
  _cameraController?.dispose(); //
  super.dispose(); // <--- WAJIB DI BARIS PALING AKHIR
}

  @override
  Widget build(BuildContext context) {
    // Mendengarkan data interupsi mikro-gestur secara real-time dari BLEController
    final bleController = Provider.of<BLEController>(context);

    // Filter Tab-Aware: Eksekusi interupsi gestur hanya jika tab camera (index 2) sedang aktif
    if (bleController.currentActiveTab == 2) {
      final String signal = bleController.lastReceivedSignal;
      
      if (signal != "IDLE") {
        // Menangani Logika Eksekusi Fitur 2 (Smart Camera) Sesuai Tabel Pemetaan Anda
        if (signal == 'NEXT_TAP') {
          // SINGLE_TAP: Ambil Foto / On-Off Video
          Future.delayed(Duration.zero, () => _triggerShutterAction());
        } else if (signal == 'PREV_TAP') {
          // DOUBLE_TAP: Ganti Mode (Foto <-> Video)
          setState(() {
            _isPhotoMode = !_isPhotoMode;
          });
          _showSnackbar(_isPhotoMode ? '🔄 Switched to PHOTO Mode' : '🔄 Switched to VIDEO Mode');
        } else if (signal == 'NEXT_FIST') {
          // SINGLE_FIST: Zoom In
          _setZoom(true);
        } else if (signal == 'PREV_FIST') {
          // DOUBLE_FIST: Zoom Out
          _setZoom(false);
        }
      }
    }

    return Scaffold(
      backgroundColor: const Color(0xFF121417),
      appBar: AppBar(
        title: const Text(
          'Smart Camera Controller',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF121417),
        elevation: 0,
      ),
      body: Column(
        children: [
          // ==========================================
          // CUSTOM CAMERA HUD / VIEWFINDER AREA
          // ==========================================
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  width: double.infinity,
                  color: Colors.black,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      _isCameraInitialized
                          ? SizedBox.expand(
                              child: CameraPreview(_cameraController!),
                            )
                          : const Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  CircularProgressIndicator(color: Color(0xFF0052FF)),
                                  SizedBox(height: 12),
                                  Text(
                                    'Memuat Sensor Kamera...',
                                    style: TextStyle(color: Colors.white70, fontSize: 13),
                                  ),
                                ],
                              ),
                            ),

                      // Overlay Grafis Grid Finder
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.15),
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),

                      // Indikator Status Memproses Media (Loading Shutter/Saving)
                      if (_isProcessingMedia)
                        Container(
                          color: Colors.black45,
                          child: const Center(
                            child: CircularProgressIndicator(color: Colors.amber),
                          ),
                        ),

                      // INDIKATOR ZOOM LEVEL CURRENT (FIGMA LOOK)
                      Positioned(
                        bottom: 16,
                        right: 16,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${_currentZoomLevel.toStringAsFixed(1)}x',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12, fontFamily: 'Courier'),
                          ),
                        ),
                      ),

                      // Teks Petunjuk Kontrol Gestur di Atas Layar HUD
                      Positioned(
                        top: 16,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: _isRecordingVideo ? Colors.red : (bleController.isConnected ? Colors.green : Colors.grey),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _isRecordingVideo
                                    ? 'REC  ${_formatDuration(_recordingSeconds)}' // Menampilkan durasi real-time jika merekam
                                    : (_isPhotoMode ? 'MODE: PHOTO' : 'MODE: VIDEO'),
                                style: const TextStyle(
                                  color: Colors.white, 
                                  fontSize: 11, 
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'Courier', // Menggunakan font mono agar lebar angka stabil saat berubah
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ==========================================
          // BOTTOM HUD CONTROLLER (GALLERY SYNC DISPLAY)
          // ==========================================
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(24),
                topRight: Radius.circular(24),
              ),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Komponen Integrasi Galeri: Menampilkan Thumbnail Media Terakhir
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE2E8F0), width: 1.5),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: _lastCapturedMediaPath != null
                          ? (_isPhotoMode 
                              ? Image.file(File(_lastCapturedMediaPath!), fit: BoxFit.cover)
                              : const Icon(Icons.video_library, color: Color(0xFF0052FF), size: 24))
                          : const Icon(Icons.photo_library, color: Colors.grey, size: 24),
                    ),

                    // Tombol Shutter Manual Aplikasi (Alternatif Fisik HUD)
                    GestureDetector(
                      onTap: _triggerShutterAction,
                      child: Container(
                        height: 64,
                        width: 64,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _isPhotoMode ? const Color(0xFF0052FF) : Colors.redAccent, 
                            width: 4
                          ),
                        ),
                        padding: const EdgeInsets.all(4),
                        child: Container(
                          decoration: BoxDecoration(
                            color: _isPhotoMode ? const Color(0xFF0052FF) : Colors.redAccent,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),

                    // Indikator Aksi Teks Peta Gestur Bawah
                    Text(
                      _isPhotoMode ? 'PHOTO' : 'VIDEO',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey, letterSpacing: 1.0),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // ==========================================
                // EMERGENCY / TESTING PANEL (RELOCATED HERE)
                // ==========================================
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 6,
                  crossAxisSpacing: 6,
                  childAspectRatio: 4.2,
                  children: [
                    _buildTestingButton(context, bleController, 'NEXT_TAP', 'Simulate Shutter Action'),
                    _buildTestingButton(context, bleController, 'PREV_TAP', 'Simulate Toggle Mode'),
                    _buildTestingButton(context, bleController, 'NEXT_FIST', 'Simulate Zoom In'),
                    _buildTestingButton(context, bleController, 'PREV_FIST', 'Simulate Zoom Out'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTestingButton(
    BuildContext context, 
    BLEController controller, 
    String signalValue, 
    String label,
  ) {
    return ElevatedButton(
      onPressed: () => controller.injectSimulatedSignal(signalValue),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.amber.withValues(alpha: 0.15),
        foregroundColor: Colors.amber.shade900,
        elevation: 0,
        side: BorderSide(color: Colors.amber.shade400, width: 1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(signalValue, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
          Text(label, style: const TextStyle(fontSize: 8, color: Colors.black54)),
        ],
      ),
    );
  }
  String _formatDuration(int totalSeconds) {
    final int minutes = totalSeconds ~/ 60;
    final int seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}


