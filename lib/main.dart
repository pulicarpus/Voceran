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
      title: 'MikroTik Voucher & Monitor Pro',
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
  // CONTROLLER PENGATURAN ROUTER (Bisa diubah mandiri oleh tiap Mitra)
  // ---------------------------------------------------------------------------
  final TextEditingController _ipController = TextEditingController(text: '192.168.88.1');
  final TextEditingController _userController = TextEditingController(text: 'admin');
  final TextEditingController _passController = TextEditingController(text: '');

  // ---------------------------------------------------------------------------
  // CONTROLLER GENERATOR VOUCHER (TAB 1)
  // ---------------------------------------------------------------------------
  final TextEditingController _bulkUptimeController = TextEditingController(text: '1h');
  final TextEditingController _bulkQtyController = TextEditingController(text: '9'); 
  String _printFormat = 'A4'; // Pilihan format default: 'A4' atau 'Thermal'

  // ---------------------------------------------------------------------------
  // CONTROLLER BUAT PROFIL BARU (TAB 2)
  // ---------------------------------------------------------------------------
  final TextEditingController _newProfileNameController = TextEditingController();
  final TextEditingController _rateLimitController = TextEditingController(text: '1M/1M');
  final TextEditingController _uptimeLimitController = TextEditingController(text: '1h'); 
  final TextEditingController _validityController = TextEditingController(text: '1d');    

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

  @override
  void initState() {
    super.initState();
    if (_listProfilHotspot.isNotEmpty) {
      _selectedProfile = _listProfilHotspot[0]['nama'];
      _bulkUptimeController.text = _listProfilHotspot[0]['limit']!;
    }
  }

  // ---------------------------------------------------------------------------
  // UTILITY: GENERATOR KODE ACAK 5 DIGIT
  // ---------------------------------------------------------------------------
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
  // MESIN SOKET API MIKROTIK (KIRIM DATA & TERIMA RESPONS BALIK)
  // ---------------------------------------------------------------------------
  Future<List<String>> _communicatorMikrotik(List<List<String>> sentences) async {
    Socket? socket;
    List<String> outputResponse = [];
    try {
      String ip = _ipController.text.trim();
      String user = _userController.text.trim();
      String pass = _passController.text;

      socket = await Socket.connect(ip, 8728, timeout: const Duration(seconds: 4));

      // Fungsi internal pengirim word sesuai regulasi panjang byte MikroTik
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

      // Prosedur Login API
      sendWord('/login');
      sendWord('=name=$user');
      sendWord('=password=$pass');
      socket.add([0]);
      await socket.flush();
      await Future.delayed(const Duration(milliseconds: 300));

      // Eksekusi Kumpulan Blok Perintah
      for (var command in sentences) {
        for (var word in command) {
          sendWord(word);
        }
        socket.add([0]); 
        await socket.flush();
        await Future.delayed(const Duration(milliseconds: 40));
      }

      // Membaca feedback dari MikroTik (Penting untuk menu Monitoring Aktif)
      StringBuffer buffer = StringBuffer();
      await socket.listen((List<int> data) {
        buffer.write(utf8.decode(data, allowMalformed: true));
      }).asFuture().timeout(const Duration(seconds: 2), onTimeout: () {});

      // Memisahkan baris data berdasarkan karakter pemisah biner
      outputResponse = buffer.toString().split('\x00');
      return outputResponse;
    } catch (e) {
      return ["ERROR_KONEKSI"];
    } finally {
      socket?.destroy();
    }
  }

  // ---------------------------------------------------------------------------
  // TAB 1 LOGIC: PROSES MASSAL & PREVIEW LAYOUT PDF (A4 GRID / THERMAL ROLL)
  // ---------------------------------------------------------------------------
  Future<void> _generateMassalVouchers() async {
    int qty = int.tryParse(_bulkQtyController.text.trim()) ?? 5;
    String finalUptime = _bulkUptimeController.text.trim();

    setState(() {
      _isLoading = true;
      _statusMessage = "Sedang memproses pendaftaran voucher massal...";
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
        '=limit-uptime=$finalUptime', 
        '=comment=App_Mitra_Massal'
      ]);
    }

    List<String> response = await _communicatorMikrotik(batchCommands);

    setState(() {
      _isLoading = false;
    });

    if (response.contains("ERROR_KONEKSI")) {
      _statusMessage = "Gagal memproses. Cek kembali parameter IP & Password Router di Tab Pengaturan!";
      _showSnackBar("Koneksi Terputus!", Colors.redAccent);
    } else {
      setState(() {
        _lastGeneratedCodes = generatedCodes;
        _statusMessage = "Berhasil membuat $qty buah voucher paket $_selectedProfile.";
      });
      _showSnackBar("Sukses menyuntikkan voucher!", Colors.green);
      _eksekusiCetakPdf(); // Luncurkan langsung pratinjau cetak dokumen
    }
  }

  Future<void> _eksekusiCetakPdf() async {
    if (_lastGeneratedCodes.isEmpty) return;
    final pdf = pw.Document();

    if (_printFormat == 'A4') {
      // FORMAT KERTAS A4: Grid 3 Kolom Rapi Hemat Kertas
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(15),
          build: (pw.Context context) {
            return pw.GridView(
              crossAxisCount: 3,
              childAspectRatio: 2.2,
              children: _lastGeneratedCodes.map((code) {
                return pw.Container(
                  margin: const pw.EdgeInsets.all(4),
                  padding: const pw.EdgeInsets.all(6),
                  decoration: pw.BoxDecoration(border: pw.Border.all(width: 1, color: PdfColors.black)),
                  child: pw.Column(
                    mainAxisAlignment: pw.MainAxisAlignment.center,
                    children: [
                      pw.Text("MEMBER WI-FI HOTSPOT", style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                      pw.Divider(thickness: 0.5),
                      pw.Text("KODE: $code", style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
                      pw.Text("Durasi: ${_bulkUptimeController.text} (Aktif Saat Login)", style: pw.TextStyle(fontSize: 7)),
                    ],
                  ),
                );
              }).toList(),
            );
          },
        ),
      );
    } else {
      // FORMAT KERTAS THERMAL: Gulungan Panjang 80mm Kebawah Ala Kasir
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.roll80,
          margin: const pw.EdgeInsets.all(10),
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.stretch,
              children: [
                pw.Text("STRUK VOUCHER WIFI", style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold), textAlign: pw.TextAlign.center),
                pw.Text("Paket: $_selectedProfile", style: pw.TextStyle(fontSize: 10), textAlign: pw.TextAlign.center),
                pw.Text("-----------------------------------------", style: pw.TextStyle(fontSize: 10)),
                pw.SizedBox(height: 5),
                pw.ListView.builder(
                  itemCount: _lastGeneratedCodes.length,
                  itemBuilder: (context, index) {
                    return pw.Padding(
                      padding: const pw.EdgeInsets.symmetric(vertical: 4),
                      child: pw.Container(
                        padding: const pw.EdgeInsets.all(6),
                        decoration: pw.BoxDecoration(border: pw.Border.all(style: pw.BorderStyle.dashed)),
                        child: pw.Row(
                          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                          children: [
                            pw.Text("Voucher ${index + 1}:", style: pw.TextStyle(fontSize: 11)),
                            pw.Text(_lastGeneratedCodes[index], style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                pw.SizedBox(height: 8),
                pw.Text("-----------------------------------------", style: pw.TextStyle(fontSize: 10)),
                pw.Text("Simpan struk atau screenshot layar ini.", style: pw.TextStyle(fontSize: 8), textAlign: pw.TextAlign.center),
              ],
            );
          },
        ),
      );
    }

    // Panggil jendela interaktif pratinjau Android OS untuk simpan ke PDF / direct printer
    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => pdf.save());
  }

  // ---------------------------------------------------------------------------
  // TAB 2 LOGIC: BUAT PROFIL HOTSPOT BARU DI ROUTER & RE-SYNC KE DROPDOWN
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

    // Skrip otomatis hapus akun ketika masa aktif habis (Mikhmon Lock System)
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
      _showSnackBar("Gagal membuat profil. Cek koneksi router!", Colors.redAccent);
    } else {
      setState(() {
        // Otomatis disinkronkan ke dropdown menu atas tanpa reload
        _listProfilHotspot.add({'nama': profName, 'limit': uptimeLimit});
        _selectedProfile = profName;
        _bulkUptimeController.text = uptimeLimit;
        _currentIndex = 0; // Tendang otomatis user kembali ke Tab Utama Cetak
      });
      _newProfileNameController.clear();
      _showSnackBar("Profil '$profName' sukses terdaftar & tersinkron!", Colors.green);
    }
  }

  // ---------------------------------------------------------------------------
  // TAB 4 LOGIC: PARSING USER AKTIF SECARA REAL-TIME DARI AKAR SOKET ROUTER
  // ---------------------------------------------------------------------------
  Future<void> _fetchActiveUsersFromRouter() async {
    setState(() {
      _isLoading = true;
      _activeUsersList.clear();
    });

    List<String> command = ['/ip/hotspot/active/print'];
    List<String> rawWords = await _communicatorMikrotik([command]);

    List<Map<String, String>> tempUsers = [];
    String currentUser = '';
    String currentUptime = '';

    // Loop data biner untuk menangkap pasang parameter '=user=' dan '=uptime='
    for (String word in rawWords) {
      if (word.startsWith('=user=')) {
        currentUser = word.replaceAll('=user=', '');
      }
      if (word.startsWith('=uptime=')) {
        currentUptime = word.replaceAll('=uptime=', '');
      }
      // Jika sepasang atribut data user hotspot telah komplit ditemukan
      if (currentUser.isNotEmpty && currentUptime.isNotEmpty) {
        tempUsers.add({'user': currentUser, 'uptime': currentUptime});
        currentUser = '';
        currentUptime = '';
      }
    }

    setState(() {
      _isLoading = false;
      _activeUsersList = tempUsers;
    });

    if (rawWords.contains("ERROR_KONEKSI")) {
      _showSnackBar("Gagal mengambil monitoring data. Cek koneksi!", Colors.redAccent);
    } else {
      _showSnackBar("Data user aktif diperbarui!", Colors.blue);
    }
  }

  // ---------------------------------------------------------------------------
  // ENGINE VIEW SWITCHER (NAVIGASI 4 TAB UTAMA)
  // ---------------------------------------------------------------------------
  Widget _buildActiveTabContent() {
    switch (_currentIndex) {
      case 0:
        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text("GENERATE MASSAL & PRATINJAU PDF", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
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
                        items: _listProfilHotspot.map((p) => DropdownMenuItem(value: p['nama'], child: Text("${p['nama']} (Bawaan: ${p['limit']})"))).toList(),
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
                      TextField(controller: _bulkQtyController, keyboardType: TextInputType.number, decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true)),
                      const SizedBox(height: 20),
                      
                      // PILIHAN FORMAT UKURAN KERTAS CETAK
                      const Text("Pilih Ukuran Output Cetakan:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                      Row(
                        children: [
                          Expanded(
                            child: RadioListTile<String>(
                              title: const Text("Kertas A4 Grid", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
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
                        label: const Text("PROSES & BUKA PRATINJAU PDF", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.green[700], padding: const EdgeInsets.symmetric(vertical: 14)),
                      )
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
        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text("BUAT PROFIL PAKET BARU", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
              const SizedBox(height: 12),
              Card(
                elevation: 3,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(controller: _newProfileNameController, decoration: const InputDecoration(labelText: 'Nama Profil Paket (Misal: Paket_3Jam)', border: OutlineInputBorder(), isDense: true)),
                      const SizedBox(height: 12),
                      TextField(controller: _rateLimitController, decoration: const InputDecoration(labelText: 'Batas Kecepatan (Misal: 1M/1M, 512k/1M)', border: OutlineInputBorder(), isDense: true)),
                      const SizedBox(height: 12),
                      TextField(controller: _uptimeLimitController, decoration: const InputDecoration(labelText: 'Kuota Durasi Pakai (Misal: 3h)', border: OutlineInputBorder(), isDense: true)),
                      const SizedBox(height: 12),
                      TextField(controller: _validityController, decoration: const InputDecoration(labelText: 'Masa Aktif Kedaluwarsa (Misal: 1d = 1 Hari, 7d = 7 Hari)', border: OutlineInputBorder(), isDense: true)),
                      const SizedBox(height: 20),
                      ElevatedButton.icon(
                        onPressed: _createNewProfile,
                        icon: const Icon(Icons.cloud_upload, color: Colors.white),
                        label: const Text("SIMPAN KE MIKROTIK & SINKRONKAN", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.orange[800], padding: const EdgeInsets.symmetric(vertical: 14)),
                      )
                    ],
                  ),
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
              const Text("KONFIGURASI PARAMETER ROUTER MITRA", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
              const SizedBox(height: 12),
              Card(
                elevation: 3,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text("Ubah parameter di bawah ini sesuai dengan IP Jaringan Lokal atau Domain VPN Remote di masing-masing lokasi tempat mitra berada.", style: TextStyle(fontSize: 12, color: Colors.grey)),
                      const SizedBox(height: 14),
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
      case 3:
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text("USER HOTSPOT AKTIF (ONLINE)", style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
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
                              subtitle: Text("Uptime: ${_activeUsersList[index]['uptime']!}", style: const TextStyle(fontSize: 12, color: Colors.green, fontWeight: FontWeight.w600)),
                            ),
                          );
                        },
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
        title: const Text('MikroTik Voucher Manager Pro', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 17)),
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
                  Text("Sedang memproses perintah ke MikroTik...", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                ],
              ),
            ) 
          : _buildActiveTabContent(),
          
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _currentIndex,
        selectedItemColor: const Color(0xFF1E3A8A),
        unselectedItemColor: Colors.grey,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
          // Jikalau user membuka Tab 4, picu mesin langsung melakukan fetching data
          if (index == 3) {
            _fetchActiveUsersFromRouter();
          }
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.confirmation_number), label: 'Voucher'),
          BottomNavigationBarItem(icon: Icon(Icons.add_box), label: 'Profil'),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Router'),
          BottomNavigationBarItem(icon: Icon(Icons.monitor_heart), label: 'Aktif'),
        ],
      ),
    );
  }
}