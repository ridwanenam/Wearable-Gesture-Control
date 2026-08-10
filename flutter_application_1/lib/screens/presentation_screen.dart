// presentation_screen.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Pustaka bawaan Flutter untuk mengakses Clipboard API (Salin Tautan)
import 'package:provider/provider.dart';
import 'package:shelf/shelf.dart' as shelf;
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter_application_1/controllers/ble_controller.dart';
import 'package:file_picker/file_picker.dart'; 
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';

class PresentationScreen extends StatefulWidget {
  const PresentationScreen({super.key});

  @override
  State<PresentationScreen> createState() => _PresentationScreenState();
}

class _PresentationScreenState extends State<PresentationScreen> {
  bool _isServerActive = false;
  bool _isCurrentlyCapturing = false; // Pengaman agar antrean jepretan tidak menumpuk
  bool _showTemplateMode = true; // true: Menampilkan Slide Template, false: File Presentasi Riil
  final GlobalKey _viewportBoundaryKey = GlobalKey();

  // MANAJEMEN STATE FILE PICKER LOCAL STORAGE (MENGGANTIKAN LINK EMBED)
  String _uploadedFileName = "Belum Ada File Di-upload";
  bool _isFileImported = false;
  int _currentSlideIndex = 1;
  int _totalSlidesCount = 1;

  HttpServer? _httpServer;
  final List<WebSocketChannel> _connectedClients = [];
  
  String _localIpAddress = 'Mencari IP...';
  final int _serverPort = 8080;

  @override
  void initState() {
    super.initState();
    _getIpAddress();
  }

  Future<void> _getIpAddress() async {
    try {
      for (var interface in await NetworkInterface.list()) {
        for (var addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            setState(() { _localIpAddress = addr.address; });
            return;
          }
        }
      }
    } catch (_) {
      setState(() { _localIpAddress = '127.0.0.1'; });
    }
  }

  // REVISI TOTAL: Mengirim Tampilan Live Stream Gambar Viewport HP ke Browser Laptop
  Future<void> _startLocalServer() async {
    if (_isServerActive) return;

    var wsHandler = webSocketHandler((webSocket, dynamic protocol) {
      _connectedClients.add(webSocket);
      // Pemicu awal agar laptop langsung meminta gambar pertama saat terhubung
      webSocket.sink.add("REFRESH");
      
      webSocket.stream.listen(
        (message) {
          // Jika laptop meminta pembaruan gambar frame, kirim ulang capture terbaru
          if (message == "REQUEST_FRAME") {
            _captureAndStreamViewport();
          }
        },
        onDone: () => _connectedClients.remove(webSocket),
        onError: (_) => _connectedClients.remove(webSocket),
      );
    });

    var cascadeHandler = shelf.Cascade().add(wsHandler).add((shelf.Request request) {
      // INTERFACE LAPTOP FINAL: Murni sebagai monitor penerima aliran gambar mentah dari HP Anda
      final htmlContent = '''
      <!DOCTYPE html>
      <html>
      <head>
        <title>GestureSync Live Viewport Stream</title>
        <style>
          body { 
            font-family: system-ui, sans-serif; 
            margin: 0; padding: 0; 
            background: #090D16; 
            display: flex; flex-direction: column; 
            height: 100vh; overflow: hidden; 
          }
          .header { 
            background: white; color: #121417; 
            padding: 10px 24px; display: flex; 
            justify-content: space-between; align-items: center; 
            box-shadow: 0 4px 6px rgba(0,0,0,0.05); 
          }
          .header h2 { margin: 0; font-size: 16px; color: #0052FF; }
          .viewport-container { 
            flex: 1; display: flex; 
            justify-content: center; align-items: center; 
            padding: 16px; overflow: hidden; 
          }
          /* BINGKAI MONITOR UTAMA: Diperbesar proporsional + Disuntikkan Fitur Penajam Piksel */
          #live-stream { 
            width: 100vw;
            height: auto; 
            max-height: 86vh;
            border-radius: 12px; 
            box-shadow: 0 25px 50px -12px rgba(0,0,0,0.5); 
            object-fit: contain; 
            background: #1E293B;

            /* TRIK CSS HACK: Memaksa GPU laptop melakukan penajaman tepi teks dokumen (Anti-Blur) */
            image-rendering: -webkit-optimize-contrast; /* Untuk browser Chrome / Edge / Safari */
            image-rendering: crisp-edges;               /* Untuk browser Firefox */
            image-rendering: pixelated;                 /* Jaminan fallback jika browser lawas */
          }

        </style>
      </head>
      <body>
        <div class="header">
          <h2>GestureSync - Live Screen Mirroring View</h2>
          <div style="font-size: 11px; font-weight: bold; background: #DCFCE7; color: #15803D; padding: 4px 12px; border-radius: 12px;">STREAMING ACTIVE</div>
        </div>
        <div class="viewport-container">
          <!-- Gambar di bawah ini akan diupdate bit-ny secara instan oleh HP Anda -->
          <img id="live-stream" src="" alt="Menunggu Aliran Gambar Viewport HP..."/>
        </div>

        <script>
          const imgStream = document.getElementById('live-stream');
          const ws = new WebSocket('ws://' + window.location.host);
          
          ws.binaryType = "blob"; // Mengonfigurasi socket agar siap menerima file biner gambar
          
          ws.onmessage = function(event) {
            if (event.data instanceof Blob) {
              // Mengubah file biner byte dari HP menjadi tautan gambar lokal di laptop
              const url = URL.createObjectURL(event.data);
              
              // Hapus cache gambar lama agar memori laptop tidak penuh (Anti-Lag)
              const oldSrc = imgStream.src;
              imgStream.src = url;
              if (oldSrc) URL.revokeObjectURL(oldSrc);
              
              // Minta frame gambar baru ke HP setelah frame saat ini sukses digambar (Siklus Lancar)
              setTimeout(() => { ws.send("REQUEST_FRAME"); }, 100);
            } else if (event.data === "REFRESH") {
              ws.send("REQUEST_FRAME");
            }
          };
        </script>
      </body>
      </html>
      ''';
      return shelf.Response.ok(htmlContent, headers: {'content-type': 'text/html'});
    });

    try {
      _httpServer = await io.serve(cascadeHandler.handler, InternetAddress.anyIPv4, _serverPort, shared: true);
      setState(() { _isServerActive = true; });
      _showSnackbar('🌐 PC Sync Server Berhasil Diaktifkan!');
    } catch (e) {
      _showSnackbar('❌ Gangguan Port Jaringan!');
    }
  }


  String? _pdfFilePath; // <--- Untuk menampung alamat path fisik file PDF di storage HP
  PDFViewController? _pdfViewController; // <--- Menyimpan instansiasi pengendali halaman PDF
  
  Future<void> _openNativeFilePicker() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'pptx'],
      );

      if (result != null && result.files.single.path != null) {
        PlatformFile file = result.files.single;

        setState(() {
          _uploadedFileName = file.name;
          _pdfFilePath = file.path; // <--- MEREKAM JALUR PATH FISIK FILE PDF ASLI
          _isFileImported = true;
          _showTemplateMode = false;
          _currentSlideIndex = 1;
        });
        _showSnackbar('📂 Sukses memuat dokumen: ${file.name}');
      } else {
        _showSnackbar('⚠️ Pemilihan file dibatalkan.');
      }
    } catch (e) {
      _showSnackbar('❌ Gagal membuka File Manager: $e');
    }
  }

  void _clearUploadedFile() {
    setState(() {
      _uploadedFileName = "Belum Ada File Di-upload";
      _pdfFilePath = null; // <--- Reset kembali alamat path menjadi null
      _isFileImported = false;
      _totalSlidesCount = 1;
      _currentSlideIndex = 1;
      _showTemplateMode = true;
    });
    _showSnackbar('🗑️ File presentasi dihapus. Kembali ke Slide Template.');
  }

  Future<void> _stopLocalServer() async {
    if (!_isServerActive) return;
    for (var client in _connectedClients) { client.sink.close(); }
    _connectedClients.clear();
    await _httpServer?.close(force: true);
    setState(() { _isServerActive = false; });
  }

  // FUNGSIONAL UTAMA COPY LINK: MENYALIN TAUTAN RIIL KE CLIPBOARD HP (ANDROID 14 COMPATIBLE)
  Future<void> _copyServerLinkToClipboard() async {
    final String serverUrl = "http://$_localIpAddress:$_serverPort";
    await Clipboard.setData(ClipboardData(text: serverUrl)); // Fungsi bawaan tanpa package tambahan
    if (mounted) {
      _showSnackbar('📋 Tautan server "$serverUrl" berhasil disalin ke clipboard!');
    }
  }

  // Modifikasi fungsi pengirim pesan agar memicu capture internal otomatis setiap kali gestur masuk
  void _bridgeGestureToPC(String signal) {
    if (!_isServerActive || _connectedClients.isEmpty) return;
    
    // Kirim sinyal teks murni sebagai pemicu interupsi keyboard laptop
    for (var client in _connectedClients) {
      client.sink.add(signal);
    }
    
    // Memicu pengambilan gambar viewport terbaru secara instan
    Future.delayed(const Duration(milliseconds: 50), () => _captureAndStreamViewport());
  }

Future<void> _captureAndStreamViewport() async {
  // 1. JIKA SERVER MATI ATAU CLIENT KOSONG ATAU SEDANG PROSES JEPRET -> TOLAK!
  if (!_isServerActive || _connectedClients.isEmpty || _isCurrentlyCapturing) return;

  try {
    _isCurrentlyCapturing = true; // Kunci gerbang antrean!

    final RenderRepaintBoundary? boundary = _viewportBoundaryKey.currentContext
        ?.findRenderObject() as RenderRepaintBoundary?;
    
    if (boundary == null) {
      _isCurrentlyCapturing = false;
      return;
    }

    // ATUR PIXEL RATIO AGAR GAMBAR TIDAK BURAM DI LAPTOP (2.0 = 200% DPI)
    ui.Image image = await boundary.toImage(pixelRatio: 2.0); 
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose(); // Langsung bersihkan bitmap dari GPU RAM

    if (byteData != null) {
      final Uint8List pngBytes = byteData.buffer.asUint8List();
      
      for (var client in _connectedClients) {
        client.sink.add(pngBytes);
      }
    }
  } catch (e) {
    debugPrint("Gagal memproses mirroring frame gambar: $e");
  } finally {
    // 2. MUTLAK: Buka kembali gerbang kuncian setelah proses biner selesai 100%
    _isCurrentlyCapturing = false; 
  }
}



  void _showSnackbar(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 2), backgroundColor: const Color(0xFF0052FF)),
    );
  }

  Widget _buildTemplateSlideView() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFE2E8F0),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFCBD5E1), width: 2),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text(
            'SLIDE TEMPLATE',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.blueGrey, letterSpacing: 1.5),
          ),
          const SizedBox(height: 24),
          const Text(
            'WELCOME TO SMART PRESENTATION',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: Color(0xFF0052FF)),
          ),
          const SizedBox(height: 12),
          // MODIFIKASI DINAMIS: Status teks mengikuti kondisi riil jaringan dan file Anda
          Text(
            _isFileImported 
                ? 'STATE: DOCUMENT READY' 
                : _isServerActive 
                    ? 'STATE: SERVER ACTIVE / WAITING FOR FILE' 
                    : 'STATE: WAITING / SERVER OFFLINE',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF1E293B), fontFamily: 'Courier'),
          ),
        ],
      ),
    );
  }

// ============================================================================
// POTONGAN KODE BAGIAN 2 UTUH SAMPAI AKHIR FILE: lib/screens/presentation_screen.dart
// ============================================================================
  void _handleLocalSlideNavigation(String direction) {
    setState(() {
      if (direction == 'NEXT' && _currentSlideIndex < _totalSlidesCount) {
        _currentSlideIndex++;
        // Memicu pengontrol PDF asli untuk lompat ke halaman berikutnya secara otomatis
        _pdfViewController?.setPage(_currentSlideIndex - 1);
      } else if (direction == 'PREV' && _currentSlideIndex > 1) {
        _currentSlideIndex--;
        // Memicu pengontrol PDF asli untuk mundur ke halaman sebelumnya secara otomatis
        _pdfViewController?.setPage(_currentSlideIndex - 1);
      } else if (direction == 'FIRST') {
        _currentSlideIndex = 1;
        _pdfViewController?.setPage(0);
      } else if (direction == 'LAST') {
        _currentSlideIndex = _totalSlidesCount;
        _pdfViewController?.setPage(_totalSlidesCount - 1);
      }
    });
  }

  @override
  void dispose() {
    _httpServer?.close(force: true);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bleController = Provider.of<BLEController>(context);

    // Filter Tab-Aware: Eksekusi interupsi hanya jika tab presentation (index 1) aktif
    if (bleController.currentActiveTab == 1) {
      final String signal = bleController.lastReceivedSignal;
      
      if (signal != "IDLE") {
        _bridgeGestureToPC(signal);

        if (signal == 'NEXT_TAP') {
          _handleLocalSlideNavigation('NEXT');
        } else if (signal == 'PREV_TAP') {
          _handleLocalSlideNavigation('PREV');
        } else if (signal == 'NEXT_FIST') {
          // SINGLE_FIST: Toggle tampilan antara slide dokumen riil dengan template bawaan
          setState(() {
            _showTemplateMode = !_showTemplateMode;
          });
          _showSnackbar(_showTemplateMode ? '📺 Mode Slide Template Aktif' : '📂 Mode Dokumen Impor Aktif');
        } else if (signal == 'PREV_FIST') {
          // DOUBLE_FIST: Lompat instan ke slide pertama atau terakhir
          if (_currentSlideIndex == 1) {
            _handleLocalSlideNavigation('LAST');
          } else {
            _handleLocalSlideNavigation('FIRST');
          }
        }
      }
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: const Text('Smart Presentation', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF121417),
        elevation: 0,
        shape: const Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            // ==========================================
            // PC SYNC SERVER INFO CARD (FUNGSIONAL)
            // ==========================================
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('PC Sync Mode', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      const SizedBox(height: 4),
                      Text(
                        'Server Link: http://$_localIpAddress:$_serverPort',
                        style: const TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      // Tombol salin tautan riil ke sistem clipboard Android
                      IconButton(
                        icon: const Icon(Icons.copy, size: 20, color: Color(0xFF0052FF)),
                        onPressed: _copyServerLinkToClipboard,
                      ),
                      Switch(
                        value: _isServerActive,
                        activeThumbColor: const Color(0xFF0052FF),
                        onChanged: (val) {
                          if (val) { _startLocalServer(); } else { _stopLocalServer(); }
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // ==========================================
            // PRESENTATION FILE UPLOADER CARD (VERSI FIX BUG & TOMBOL X)
            // ==========================================
            GestureDetector(
              onTap: _isFileImported ? null : _openNativeFilePicker, // Klik hanya aktif jika file masih kosong
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _isFileImported ? const Color(0xFF0052FF) : const Color(0xFFE2E8F0),
                    width: _isFileImported ? 1.5 : 1.0,
                  ),
                ),
                child: Column(
                  children: [
                    const Icon(Icons.cloud_upload_outlined, size: 36, color: Color(0xFF0052FF)),
                    const SizedBox(height: 8),
                    const Text('Upload Presentation File (PDF/PPTX)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const Text('Tap to browse from storage', style: TextStyle(color: Colors.grey, fontSize: 11)),
                    const Divider(height: 24, color: Color(0xFFE2E8F0)),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Icon(Icons.picture_as_pdf, color: _isFileImported ? Colors.red : Colors.grey, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _uploadedFileName,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12, 
                                    fontWeight: FontWeight.bold, 
                                    color: _isFileImported ? const Color(0xFF1E293B) : Colors.grey
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        // IMPLEMENTASI TOMBOL X KHUSUS UNTUK RESET GANTI FILE
                        _isFileImported
                            ? IconButton(
                                icon: const Icon(Icons.close, color: Colors.redAccent, size: 18),
                                onPressed: _clearUploadedFile,
                              )
                            : Text(
                                'Slide $_currentSlideIndex of $_totalSlidesCount',
                                style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.bold),
                              ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),

            // ============================================================================
            // PRESENTATION VIEWPORT AREA (VERSI MIRRORING ENGINE: 100% SINKRON KE PC)
            // ============================================================================
            Expanded(
              child: RepaintBoundary(
                key: _viewportBoundaryKey, // <--- KUNCI UTAMA SINKRONISASI CLONING GAMBAR
                child: _showTemplateMode
                    ? _buildTemplateSlideView() // Menampilkan layout template lab di HP
                    : Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          // UBAH: Gunakan warna solid flat (misal hitam atau putih), jangan gunakan gradasi rumit
                          color: Colors.black, 
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ), // BoxDecoration
                        clipBehavior: Clip.antiAlias,                        
                        child: Stack(
                          alignment: Alignment.bottomCenter,
                          children: [
                            // Pemuat berkas PDF asli Anda di HP
                            _pdfFilePath != null
                                ? PDFView(
                                    filePath: _pdfFilePath,
                                    enableSwipe: true,
                                    swipeHorizontal: true,
                                    autoSpacing: true,
                                    pageSnap: true,
                                    defaultPage: _currentSlideIndex - 1,
                                      onViewCreated: (PDFViewController pdfViewController) {
                                        _pdfViewController = pdfViewController;
                                        // Menggantikan Future.delayed statis dengan callback frame resmi Flutter
                                        WidgetsBinding.instance.addPostFrameCallback((_) {
                                          _captureAndStreamViewport();
                                        });
                                      },
                                      onRender: (pages) {
                                        setState(() { _totalSlidesCount = pages ?? 1; });
                                      },
                                      onPageChanged: (page, total) {
                                        setState(() { _currentSlideIndex = (page ?? 0) + 1; });
                                        // Pemicu instan pasca render halaman baru selesai
                                        WidgetsBinding.instance.addPostFrameCallback((_) {
                                          _captureAndStreamViewport();
                                        });
                                      },
                                  )
                                : Container(
                                    color: const Color(0xFF1E293B),
                                    child: const Center(child: Text('Memuat Dokumen...', style: TextStyle(color: Colors.white))),
                                  ),
                            
                            // TOMBOL NAVIGASI MANUAL PANAH SUDAH DIHAPUS TOTAL DI SINI AGAR TAMPILAN BERSIH
                          ],
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 14),

            // ==========================================
            // EMERGENCY PANEL EMBED
            // ==========================================
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              childAspectRatio: 4.0,
              children: [
                _buildTestingButton(context, bleController, 'NEXT_TAP', 'Simulate Slide Next'),
                _buildTestingButton(context, bleController, 'PREV_TAP', 'Simulate Slide Prev'),
                _buildTestingButton(context, bleController, 'NEXT_FIST', 'Simulate Toggle Mode'),
                _buildTestingButton(context, bleController, 'PREV_FIST', 'Simulate Reset Indeks'),
              ],
            ),
          ],
        ),
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
}


