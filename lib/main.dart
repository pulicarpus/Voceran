import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MikroTik Voucher Master',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primaryColor: const Color(0xFF1E3A8A),
        scaffoldBackgroundColor: const Color(0xFFF8FAFC),
        fontFamily: 'sans-serif',
      ),
      home: const MainNavigationScreen(),
    );
  }
}

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({Key? key}) : super(key: key);

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;
  bool _isLoading = false;
  String _statusMessage = 'Sistem Siap Digunakan.';

  // ---------------------------------------------------------------------------
  // CONTROLLER PENGATURAN ROUTER
  // ---------------------------------------------------------------------------
  final TextEditingController _ipController = TextEditingController(text: '192.168.88.1');
  final TextEditingController _userController = TextEditingController(text: 'admin');
  final TextEditingController _passController = TextEditingController(text: '');

  // ---------------------------------------------------------------------------
  // CONTROLLER GENERATOR VOUCHER (TAB 1)
  // ---------------------------------------------------------------------------
  final TextEditingController _bulkUptimeController = TextEditingController(text: '1h');
  final TextEditingController _bulkQtyController = TextEditingController(text: '9'); 
  String _printFormat = 'A4'; 

  // ---------------------------------------------------------------------------
  // CONTROLLER BUAT PROFIL BARU (TAB 3)
  // ---------------------------------------------------------------------------
  final TextEditingController _newProfileNameController = TextEditingController();
  final TextEditingController _rateLimitController = TextEditingController(text: '1M/1M');
  final TextEditingController _uptimeLimitController = TextEditingController(text: '1h'); 
  final TextEditingController _validityController = TextEditingController(text: '1d');    

  // ---------------------------------------------------------------------------
  // CONTROLLER PENCARIAN VOUCHER (TAB 2)
  // ---------------------------------------------------------------------------
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";

  // ---------------------------------------------------------------------------
  // DATA STATE APLIKASI
  // ---------------------------------------------------------------------------
  final List<Map<String, String>> _listProfilHotspot = [
    {'nama': 'Paket_1Jam', 'limit': '1h'},
    {'nama': 'Paket_2Jam', 'limit': '2h'},
  ];
  String? _selectedProfile = 'Paket_1Jam';
  List<String> _lastGeneratedCodes = [];
  List<Map<String, String>> _activeUsersList = [];
  List<Map<String, String>> _allVouchersList = [];

  @override
  void initState() {
    super.initState();
    if (_listProfilHotspot.isNotEmpty) {
      _selectedProfile = _listProfilHotspot[0]['nama'];
      _bulkUptimeController.text = _listProfilHotspot[0]['limit']!;
    }
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });
  }

  String _generateRandomVoucher() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    Random rand = Random();
    return List.generate(5, (index) => chars[rand.nextInt(chars.length)]).join();
  }

  void _showSnackBar(String text, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text, style: const TextStyle(fontWeight: FontWeight.bold)), backgroundColor: color),
    );
  }

  // ---------------------------------------------------------------------------
  // FITUR: TOMBOL PING LANGSUNG KE PORT API MIKROTIK
  // ---------------------------------------------------------------------------
  Future<void> _testMikrotikConnection() async {
    setState(() {
      _isLoading = true;
    });

    try {
      String ip = _ipController.text.trim();
      final socket = await Socket.connect(ip, 8728, timeout: const Duration(seconds: 4));
      socket.destroy(); 

      setState(() {
        _isLoading = false;
        _statusMessage = "Koneksi ke MikroTik ($ip) SUKSES!";
      });
      _showSnackBar("⚡ KONEKSI SUKSES! HP Bos sudah terhubung ke MikroTik.", Colors.green);
    } catch (e) {
      setState(() {
        _isLoading = false;
        _statusMessage = "Koneksi GAGAL! Router tidak merespon.";
      });
      _showSnackBar("❌ KONEKSI GAGAL! Aktifkan Service API (8728) di MikroTik/Cek Wi-Fi.", Colors.red);
    }
  }

  // ---------------------------------------------------------------------------
  // ENGIN SOKET API MIKROTIK
  // ---------------------------------------------------------------------------
  Future<List<String>> _communicatorMikrotik(List<List<String>> sentences) async {
    Socket? socket;
    List<String> outputResponse = [];
    try {
      String ip = _ipController.text.trim();
      String user = _userController.text.trim();
      String pass = _passController.text;

      socket = await Socket.connect(ip, 8728, timeout: const Duration(seconds: 4));

      void sendWord(String word) {
        List<int> bytes = utf8.encode(word);
        int len = bytes.length;
        if (len < 128) {
          socket!.add([len]);
        } else if (len < 16384) {
          int eLen = len | 0x8000;
          socket!.add([(eLen >> 8) & 0xFF, eLen & 0xFF]);
        }
        socket!.add(bytes);
      }

      sendWord('/login');
      sendWord('=name=$user');
      sendWord('=password=$pass');
      socket.add([0]);
      await socket.flush();
      await Future.delayed(const Duration(milliseconds: 300));

      for (var command in sentences) {
        for (var word in command) {
          sendWord(word);
        }
        socket.add([0]); 
        await socket.flush();
        await Future.delayed(const Duration(milliseconds: 40));
      }

      StringBuffer buffer = StringBuffer();
      await socket.listen((List<int> data) {
        buffer.write(utf8.decode(data, allowMalformed: true));
      }).asFuture().timeout(const Duration(seconds: 2), onTimeout: () {});

      outputResponse = buffer.toString().split('\x00');
      return outputResponse;
    } catch (e) {
      return ["ERROR_KONEKSI"];
    } finally {
      socket?.destroy();
    }
  }

  // ---------------------------------------------------------------------------
  // TAB 1: GENERATE & VALIDASI INPUT
  // ---------------------------------------------------------------------------
  Future<void> _generateMassalVouchers() async {
    String qtyText = _bulkQtyController.text.trim();
    String uptimeText = _bulkUptimeController.text.trim();

    if (qtyText.isEmpty) {
      _showSnackBar("Gagal: Jumlah cetak voucher tidak boleh kosong!", Colors.orange[800]!);
      return;
    }
    int? qty = int.tryParse(qtyText);
    if (qty == null || qty <= 0) {
      _showSnackBar("Gagal: Jumlah cetak harus berupa angka bulat di atas 0!", Colors.orange[800]!);
      return;
    }
    if (uptimeText.isEmpty) {
      _showSnackBar("Gagal: Batasan durasi (uptime) wajib diisi (Contoh: 1h)!", Colors.orange[800]!);
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = "Sedang menyuntikkan data voucher massal...";
      _lastGeneratedCodes.clear();
    });

    List<String> generatedCodes = [];
    List<List<String>> batchCommands = [];

    for (int i = 0; i < qty; i++) {
      String code = _generateRandomVoucher();
      generatedCodes.add(code);

      batchCommands.add([
        '/ip/hotspot/user/add',
        '=name=$code',
        '=password=$code',
        '=profile=$_selectedProfile',
        '=limit-uptime=$uptimeText', 
        '=comment=App_Mitra_Massal'
      ]);
    }

    List<String> response = await _communicatorMikrotik(batchCommands);

    setState(() {
      _isLoading = false;
    });

    if (response.contains("ERROR_KONEKSI")) {
      _statusMessage = "Koneksi terputus! Periksa IP & Password Router di Tab Pengaturan.";
      _showSnackBar("Gagal koneksi ke Router!", Colors.red);
    } else {
      setState(() {
        _lastGeneratedCodes = generatedCodes;
        _statusMessage = "Berhasil membuat $qty voucher. Pratinjau PDF terbuka.";
      });
      _showSnackBar("Sukses mendaftarkan voucher!", Colors.green);
      _eksekusiCetakPdf();
    }
  }

  // ---------------------------------------------------------------------------
  // 🛠️ UPDATE: ENGINE LAYOUT CETAK PDF (GRID DIPERKECIL & DIHEMAT)
  // ---------------------------------------------------------------------------
  Future<void> _eksekusiCetakPdf() async {
    if (_lastGeneratedCodes.isEmpty) return;
    final pdf = pw.Document();

    if (_printFormat == 'A4') {
      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(12), // Margin lembaran sedikit dipersempit
          build: (pw.Context context) {
            return [
              pw.Wrap(
                spacing: 4,    // Jarak spasi horizontal antar kotak dipersempit
                runSpacing: 4, // Jarak spasi vertikal antar baris dipersempit
                children: _lastGeneratedCodes.map((code) {
                  return pw.Container(
                    width: 92, // Diperkecil dari sebelumnya 130
                    height: 48, // Diperkecil dari sebelumnya 65
                    padding: const pw.EdgeInsets.all(3),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(width: 0.6, color: PdfColors.black),
                      borderRadius: const pw.BorderRadius.all(pw.Radius.circular(3)),
                    ),
                    child: pw.Column(
                      mainAxisAlignment: pw.MainAxisAlignment.center,
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        pw.Text("WIFI HOTSPOT", style: pw.TextStyle(fontSize: 5.5, fontWeight: pw.FontWeight.bold, letterSpacing: 0.3)),
                        pw.Container(margin: const pw.EdgeInsets.symmetric(vertical: 1.5), height: 0.4, color: PdfColors.grey400),
                        pw.Text(code, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, letterSpacing: 0.8)),
                        pw.SizedBox(height: 1),
                        pw.Text("Durasi: ${_bulkUptimeController.text}", style: pw.TextStyle(fontSize: 5, color: PdfColors.grey700)),
                      ],
                    ),
                  );
                }).toList(),
              )
            ];
          },
        ),
      );
    } else {
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.roll80,
          margin: const pw.EdgeInsets.all(10),
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                pw.Text("STRUK VOUCHER WIFI", style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.center),
                pw.Text("-----------------------------------------", style: pw.TextStyle(fontSize: 10)),
                pw.ListView.builder(
                  itemCount: _lastGeneratedCodes.length,
                  itemBuilder: (context, index) {
                    return pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(vertical: 3),
                      child: pw.Row(
                        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                        children: [
                          pw.Text("Voucher ${index + 1}:", style: pw.TextStyle(fontSize: 11)),
                          pw.Text(_lastGeneratedCodes[index], style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                        ],
                      ),
                    );
                  },
                ),
                pw.Text("-----------------------------------------", style: pw.TextStyle(fontSize: 10)),
              ],
            );
          },
        ),
      );
    }

    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => pdf.save());
  }

  // ---------------------------------------------------------------------------
  // TAB 2: MEKANISME MEMBACA SEMUA VOUCHER YANG SUDAH DIBUAT
  // ---------------------------------------------------------------------------
  Future<void> _fetchAllVouchersFromRouter() async {
    setState(() {
      _isLoading = true;
      _allVouchersList.clear();
    });

    List<String> command = ['/ip/hotspot/user/print'];
    List<String> rawWords = await _communicatorMikrotik([command]);

    List<Map<String, String>> tempVouchers = [];
    Map<String, String> currentItem = {};

    for (String word in rawWords) {
      if (word == '!re') {
        if (currentItem.containsKey('name')) {
          tempVouchers.add(Map.from(currentItem));
        }
        currentItem.clear();
      } else if (word.startsWith('=name=')) {
        currentItem['name'] = word.substring(6);
      } else if (word.startsWith('=profile=')) {
        currentItem['profile'] = word.substring(9);
      } else if (word.startsWith('=limit-uptime=')) {
        currentItem['limit'] = word.substring(14);
      }
    }
    if (currentItem.containsKey('name')) {
      tempVouchers.add(Map.from(currentItem));
    }

    setState(() {
      _isLoading = false;
      _allVouchersList = tempVouchers;
    });

    if (rawWords.contains("ERROR_KONEKSI")) {
      _showSnackBar("Gagal sinkronisasi data voucher!", Colors.redAccent);
    }
  }

  // ---------------------------------------------------------------------------
  // TAB 3: LOGIC BUAT PROFIL BARU
  // ---------------------------------------------------------------------------
  Future<void> _createNewProfile() async {
    String profName = _newProfileNameController.text.trim();
    String rateLimit = _rateLimitController.text.trim();
    String uptimeLimit = _uptimeLimitController.text.trim(); 
    String validity = _validityController.text.trim();

    if (profName.isEmpty || rateLimit.isEmpty || uptimeLimit.isEmpty || validity.isEmpty) {
      _showSnackBar("Lengkapi seluruh form pembuatan profil!", Colors.orange);
      return;
    }

    setState(() {
      _isLoading = true;
    });

    String onLoginScript = 
        ':local u \$"user"; /system scheduler add name=\$u interval=$validity on-event="/ip hotspot user remove [find name=\$u]; /ip hotspot active remove [find user=\$u]; /system scheduler remove [find name=\$u];"';

    List<String> command = [
      '/ip/hotspot/user/profile/add',
      '=name=$profName',
      '=shared-users=1',
      '=rate-limit=$rateLimit',
      '=limit-uptime=$uptimeLimit', 
      '=on-login=$onLoginScript'
    ];

    List<String> response = await _communicatorMikrotik([command]);

    setState(() {
      _isLoading = false;
    });

    if (response.contains("ERROR_KONEKSI")) {
      _showSnackBar("Gagal membuat profil. Cek koneksi!", Colors.redAccent);
    } else {
      setState(() {
        _listProfilHotspot.add({'nama': profName, 'limit': uptimeLimit});
        _selectedProfile = profName;
        _bulkUptimeController.text = uptimeLimit;
        _currentIndex = 0; 
      });
      _newProfileNameController.clear();
      _showSnackBar("Profil baru sukses disinkronkan!", Colors.green);
    }
  }

  // ---------------------------------------------------------------------------
  // TAB 4: MENGAMBIL USER ONLINE AKTIF
  // ---------------------------------------------------------------------------
  Future<void> _fetchActiveUsersFromRouter() async {
    setState(() {
      _isLoading = true;
      _activeUsersList.clear();
    });

    List<String> command = ['/ip/hotspot/active/print'];
    List<String> rawWords = await _communicatorMikrotik([command]);

    List<Map<String, String>> tempUsers = [];
    Map<String, String> currentActive = {};

    for (String word in rawWords) {
      if (word == '!re') {
        if (currentActive.containsKey('user')) {
          tempUsers.add(Map.from(currentActive));
        }
        currentActive.clear();
      } else if (word.startsWith('=user=')) {
        currentActive['user'] = word.substring(6);
      } else if (word.startsWith('=uptime=')) {
        currentActive['uptime'] = word.substring(8);
      }
    }
    if (currentActive.containsKey('user')) {
      tempUsers.add(Map.from(currentActive));
    }

    setState(() {
      _isLoading = false;
      _activeUsersList = tempUsers;
    });
  }

  // ---------------------------------------------------------------------------
  // ENGINE VIEW SWITCHER (5 TAB UTAMA)
  // ---------------------------------------------------------------------------
  Widget _buildActiveTabContent() {
    switch (_currentIndex) {
      case 0:
        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text("GENERATE MASSAL VOUCHER", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Card(
                elevation: 3,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text("Pilih Profil:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        value: _selectedProfile,
                        decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12)),
                        items: _listProfilHotspot.map((p) => DropdownMenuItem(value: p['nama'], child: Text("${p['nama']} (${p['limit']})"))).toList(),
                        onChanged: (v) {
                          setState(() {
                            _selectedProfile = v;
                            var item = _listProfilHotspot.firstWhere((element) => element['nama'] == v);
                            _bulkUptimeController.text = item['limit']!;
                          });
                        },
                      ),
                      const SizedBox(height: 16),
                      const Text("Ubah Batas Waktu / Uptime:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 6),
                      TextField(controller: _bulkUptimeController, decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true)),
                      const SizedBox(height: 16),
                      const Text("Jumlah Cetak (Qty Lembar):", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      const SizedBox(height: 6),
                      TextField(controller: _bulkQtyController, keyboardType: TextInputType.number, decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true, hintText: 'Masukkan jumlah angka')),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Expanded(
                            child: RadioListTile<String>(
                              title: const Text("Kertas A4", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                              value: 'A4', groupValue: _printFormat, onChanged: (v) => setState(() => _printFormat = v!),
                            ),
                          ),
                          Expanded(
                            child: RadioListTile<String>(
                              title: const Text("Thermal 80mm", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                              value: 'Thermal', groupValue: _printFormat, onChanged: (v) => setState(() => _printFormat = v!),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: _generateMassalVouchers,
                        icon: const Icon(Icons.picture_as_pdf, color: Colors.white),
                        label: const Text("PROSES & CETAK VOUCHER", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.green[700], padding: const EdgeInsets.symmetric(vertical: 14)),
                      ),
                      const SizedBox(height: 10),
                      ElevatedButton.icon(
                        onPressed: _testMikrotikConnection,
                        icon: const Icon(Icons.router, color: Colors.white),
                        label: const Text("CEK KONEKSI KE MIKROTIK", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, padding: const EdgeInsets.symmetric(vertical: 14)),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(8)),
                child: Text(_statusMessage, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600), textAlign: TextAlign.center),
              )
            ],
          ),
        );
      case 1:
        List<Map<String, String>> filteredVouchers = _allVouchersList.where((v) {
          return v['name']!.toLowerCase().contains(_searchQuery);
        }).toList();

        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("DATA VOUCHER DI MIKROTIK", style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                  IconButton(icon: const Icon(Icons.refresh, color: Colors.green), onPressed: _fetchAllVouchersFromRouter)
                ],
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _searchController,
                decoration: const InputDecoration(labelText: 'Cari Kode Voucher...', prefixIcon: Icon(Icons.search), border: OutlineInputBorder(), isDense: true),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: filteredVouchers.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Icon(Icons.badge_outlined, size: 48, color: Colors.grey),
                            SizedBox(height: 8),
                            Text("Tidak ada data voucher ditemukan.", style: TextStyle(color: Colors.grey, fontSize: 13)),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: filteredVouchers.length,
                        itemBuilder: (context, index) {
                          String codeName = filteredVouchers[index]['name'] ?? 'Unknown';
                          String profName = filteredVouchers[index]['profile'] ?? '-';
                          String limitTime = filteredVouchers[index]['limit'] ?? 'Unlimited';
                          return Card(
                            elevation: 1.5,
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            child: ListTile(
                              leading: const CircleAvatar(backgroundColor: Colors.teal, child: Icon(Icons.vpn_key, color: Colors.white, size: 16)),
                              title: Text("KODE: $codeName", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, letterSpacing: 0.5)),
                              subtitle: Text("Paket: $profName  |  Limit: $limitTime", style: const TextStyle(fontSize: 12, color: Colors.black54)),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      case 2:
        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text("BUAT PROFIL PAKET BARU", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Card(
                elevation: 3,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(controller: _newProfileNameController, decoration: const InputDecoration(labelText: 'Nama Profil Paket', border: OutlineInputBorder(), isDense: true)),
                      const SizedBox(height: 12),
                      TextField(controller: _rateLimitController, decoration: const InputDecoration(labelText: 'Batas Kecepatan (Contoh: 1M/1M)', border: OutlineInputBorder(), isDense: true)),
                      const SizedBox(height: 12),
                      TextField(controller: _uptimeLimitController, decoration: const InputDecoration(labelText: 'Kuota Durasi Pakai (Contoh: 3h)', border: OutlineInputBorder(), isDense: true)),
                      const SizedBox(height: 12),
                      TextField(controller: _validityController, decoration: const InputDecoration(labelText: 'Masa Aktif Kedaluwarsa (Contoh: 1d)', border: OutlineInputBorder(), isDense: true)),
                      const SizedBox(height: 20),
                      ElevatedButton.icon(
                        onPressed: _createNewProfile,
                        icon: const Icon(Icons.cloud_upload, color: Colors.white),
                        label: const Text("SIMPAN PROFIL KE ROUTER", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.orange[800], padding: const EdgeInsets.symmetric(vertical: 14)),
                      )
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      case 3:
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("USER HOTSPOT ONLINE AKTIF", style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                  IconButton(icon: const Icon(Icons.sync, color: Colors.blue), onPressed: _fetchActiveUsersFromRouter)
                ],
              ),
              const SizedBox(height: 10),
              Expanded(
                child: _activeUsersList.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: const [
                            Icon(Icons.people_outline, size: 48, color: Colors.grey),
                            SizedBox(height: 8),
                            Text("Tidak ada user aktif atau belum direfresh.", style: TextStyle(color: Colors.grey, fontSize: 13)),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: _activeUsersList.length,
                        itemBuilder: (context, index) {
                          return Card(
                            elevation: 1.5,
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            child: ListTile(
                              leading: const CircleAvatar(backgroundColor: Colors.blue, child: Icon(Icons.wifi, color: Colors.white, size: 18)),
                              title: Text(_activeUsersList[index]['user']!, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                              subtitle: Text("Uptime Terpakai: ${_activeUsersList[index]['uptime']!}", style: const TextStyle(fontSize: 12, color: Colors.green, fontWeight: FontWeight.w600)),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      case 4:
        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text("KONFIGURASI PARAMETER ROUTER MITRA", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Card(
                elevation: 3,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(controller: _ipController, decoration: const InputDecoration(labelText: 'IP Router / Host VPN Remote', prefixIcon: Icon(Icons.dns), border: OutlineInputBorder(), isDense: true)),
                      const SizedBox(height: 12),
                      TextField(controller: _userController, decoration: const InputDecoration(labelText: 'Username API Router', prefixIcon: Icon(Icons.person), border: OutlineInputBorder(), isDense: true)),
                      const SizedBox(height: 12),
                      TextField(controller: _passController, obscureText: true, decoration: const InputDecoration(labelText: 'Password API Router', prefixIcon: Icon(Icons.lock), border: OutlineInputBorder(), isDense: true)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      default:
        return const SizedBox();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MikroTik Voucher Manager Pro', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 16)),
        backgroundColor: const Color(0xFF1E3A8A),
        centerTitle: true,
        elevation: 1,
      ),
      body: _isLoading 
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Color(0xFF1E3A8A)),
                  SizedBox(height: 14),
                  Text("Berkomunikasi dengan MikroTik...", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey, fontSize: 13)),
                ],
              ),
            ) 
          : _buildActiveTabContent(),
          
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _currentIndex,
        selectedItemColor: const Color(0xFF1E3A8A),
        unselectedItemColor: Colors.grey,
        selectedLabelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
        unselectedLabelStyle: const TextStyle(fontSize: 11),
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
          if (index == 1) {
            _fetchAllVouchersFromRouter();
          }
          if (index == 3) {
            _fetchActiveUsersFromRouter();
          }
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.confirmation_number), label: 'Cetak'),
          BottomNavigationBarItem(icon: Icon(Icons.view_list), label: 'Daftar'),
          BottomNavigationBarItem(icon: Icon(Icons.add_box), label: 'Profil'),
          BottomNavigationBarItem(icon: Icon(Icons.monitor_heart), label: 'Aktif'),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Router'),
        ],
      ),
    );
  }
}