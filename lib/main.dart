import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Voceran MikroTik v6 Pro',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primaryColor: const Color(0xFF1976D2),
        scaffoldBackgroundColor: const Color(0xFFF5F7FA),
      ),
      home: const VoucherScreen(),
    );
  }
}

class VoucherScreen extends StatefulWidget {
  const VoucherScreen({Key? key}) : super(key: key);

  @override
  State<VoucherScreen> createState() => _VoucherScreenState();
}

class _VoucherScreenState extends State<VoucherScreen> {
  // Controller Koneksi Router 
  final TextEditingController _ipController = TextEditingController(text: '192.168.88.1');
  final TextEditingController _userController = TextEditingController(text: 'admin');
  final TextEditingController _passController = TextEditingController();

  // Controller Buat Profil Paket Baru
  final TextEditingController _newProfileNameController = TextEditingController();
  final TextEditingController _rateLimitController = TextEditingController(text: '1M/1M');
  final TextEditingController _uptimeLimitController = TextEditingController(text: '1h'); 
  final TextEditingController _validityController = TextEditingController(text: '2d');    

  // DAFTAR PROFIL HOTSPOT DINAMIS (Bisa bertambah otomatis saat bos buat profil baru)
  final List<Map<String, String>> _listProfilHotspot = [
    {'nama': 'Paket_1Jam', 'limit': '1h'},
    {'nama': 'Paket_2Jam', 'limit': '2h'},
  ];

  // State Pilihan Dropdown & Generator
  String? _selectedProfile;
  final TextEditingController _bulkUptimeController = TextEditingController(text: '1h');
  final TextEditingController _bulkQtyController = TextEditingController(text: '5'); 

  String _statusMessage = '-';
  bool _isLoading = false;
  List<String> _lastGeneratedCodes = []; // Menyimpan kode voucher terakhir untuk cetak/PDF

  @override
  void initState() {
    super.initState();
    // Set default awal ke item pertama jika list tidak kosong
    if (_listProfilHotspot.isNotEmpty) {
      _selectedProfile = _listProfilHotspot[0]['nama'];
      _bulkUptimeController.text = _listProfilHotspot[0]['limit']!;
    }
  }

  // Generator acak kode voucher (5 Digit)
  String _generateRandomVoucher() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    Random rand = Random();
    return List.generate(5, (index) => chars[rand.nextInt(chars.length)]).join();
  }

  bool _validateConnectionInputs() {
    if (_ipController.text.trim().isEmpty) {
      _showSnackBar("IP / Domain Router tidak boleh kosong, bos!", Colors.redAccent);
      return false;
    }
    if (_userController.text.trim().isEmpty) {
      _showSnackBar("Username Router tidak boleh kosong, bos!", Colors.redAccent);
      return false;
    }
    return true;
  }

  void _showSnackBar(String message, Color backgroundColor) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: backgroundColor,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // MESIN UTAMA SOKET API MIKROTIK
  Future<String> _executeMikrotikBulkCommands(List<List<String>> sentences) async {
    Socket? socket;
    try {
      String ip = _ipController.text.trim();
      String user = _userController.text.trim();
      String pass = _passController.text;

      socket = await Socket.connect(ip, 8728, timeout: const Duration(seconds: 5));

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

      // Login Prosedur
      sendWord('/login');
      sendWord('=name=$user');
      sendWord('=password=$pass');
      socket.add([0]);
      await socket.flush();
      await Future.delayed(const Duration(milliseconds: 300));

      // Semburkan semua perintah dalam array batch
      for (var command in sentences) {
        for (var word in command) {
          sendWord(word);
        }
        socket.add([0]); 
        await socket.flush();
        await Future.delayed(const Duration(milliseconds: 30));
      }
      
      return "SUCCESS";
    } catch (e) {
      return "Gagal Koneksi: Router Tidak Merespons / API Nonaktif";
    } finally {
      socket?.destroy();
    }
  }

  // FUNGSI 1: Cetak Voucher Massal Berdasarkan Dropdown Terpilih
  Future<void> _generateMassalVouchers() async {
    if (!_validateConnectionInputs()) return;
    if (_selectedProfile == null) {
      _showSnackBar("Silakan pilih atau buat profil terlebih dahulu, bos!", Colors.redAccent);
      return;
    }
    
    int qty = int.tryParse(_bulkQtyController.text.trim()) ?? 5;
    String finalUptime = _bulkUptimeController.text.trim();

    setState(() {
      _isLoading = true;
      _statusMessage = "Sedang menyuntikkan $qty Voucher ke MikroTik...";
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
        '=comment=Massal_App_Android'
      ]);
    }

    String result = await _executeMikrotikBulkCommands(batchCommands);

    setState(() {
      _isLoading = false;
      if (result == "SUCCESS") {
        _lastGeneratedCodes = generatedCodes;
        _statusMessage = "BERHASIL DI-GENERATE MASSAL!\n\nPROFIL: $_selectedProfile\nWAKTU: $finalUptime | JUMLAH: $qty Pcs\n\nKODE VOUCHER:\n${generatedCodes.join('   |   ')}";
        _showSnackBar("Sukses meluncurkan $qty voucher ke hAP lite!", Colors.green);
      } else {
        _statusMessage = result;
      }
    });
  }

  // FUNGSI 2: Buat Profil Baru (Otomatis Tersinkron Masuk Dropdown Atas)
  Future<void> _createNewProfile() async {
    if (!_validateConnectionInputs()) return;

    String profName = _newProfileNameController.text.trim();
    String rateLimit = _rateLimitController.text.trim();
    String uptimeLimit = _uptimeLimitController.text.trim(); 
    String validity = _validityController.text.trim();

    if (profName.isEmpty || rateLimit.isEmpty || uptimeLimit.isEmpty || validity.isEmpty) {
      _showSnackBar("Semua kolom profil baru wajib diisi, bos!", Colors.redAccent);
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = "Menyimpan profil baru ke sistem MikroTik...";
    });

    // Script lock masa aktif otomatis (Mikhmon Style)
    String onLoginScript = 
        ':local u \$"user"; /system scheduler add name=\$u interval=$validity on-event="/ip hotspot user remove [find name=\$u]; /ip hotspot active remove [find user=\$u]; /system scheduler remove [find name=\$u];"';

    List<String> cmd = [
      '/ip/hotspot/user/profile/add',
      '=name=$profName',
      '=shared-users=1',
      '=rate-limit=$rateLimit',
      '=limit-uptime=$uptimeLimit', 
      '=on-login=$onLoginScript'
    ];

    String result = await _executeMikrotikBulkCommands([cmd]);

    setState(() {
      _isLoading = false;
      if (result == "SUCCESS") {
        // RAHASIA UTAMA: Masukkan langsung ke list pilihan dropdown di atas secara real-time
        _listProfilHotspot.add({'nama': profName, 'limit': uptimeLimit});
        
        // Geser pilihan aktif ke profil yang baru dibuat ini
        _selectedProfile = profName;
        _bulkUptimeController.text = uptimeLimit;

        _statusMessage = "PROFIL BARU SUKSES SINKRON!\nPaket '$profName' otomatis masuk ke menu Dropdown di atas.";
        _newProfileNameController.clear();
        _showSnackBar("Profil '$profName' sukses dibuat dan disinkronkan!", Colors.green);
      } else {
        _statusMessage = result;
      }
    });
  }

  // FUNGSI 3: Simulasi Cetak Struktur / Simpan Teks (Bisa di-copy langsung)
  void _printOrSaveAsPdf() {
    if (_lastGeneratedCodes.isEmpty) {
      _showSnackBar("Belum ada voucher yang dicetak untuk disimpan, bos!", Colors.orange);
      return;
    }

    // Membuat format struk siap cetak / siap simpan teks
    StringBuffer buffer = StringBuffer();
    buffer.writeln("=============================");
    buffer.writeln("      STRUK VOUCHER HOTSPOT  ");
    buffer.writeln("=============================");
    buffer.writeln("Profil : $_selectedProfile");
    buffer.writeln("Durasi : ${_bulkUptimeController.text}");
    buffer.writeln("Jumlah : ${_lastGeneratedCodes.length} Lembar");
    buffer.writeln("-----------------------------");
    for (int i = 0; i < _lastGeneratedCodes.length; i++) {
      buffer.writeln("Voucher ${i + 1} : ${_lastGeneratedCodes[i]}");
    }
    buffer.writeln("=============================");
    buffer.writeln(" Terima Kasih - Selamat Mencoba");

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Struk Voucher (Siap Salin/Cetak)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        content: SingleChildScrollView(
          child: SelectableText(buffer.toString(), style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("TUTUP", style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Voceran MikroTik v6 Pro', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: const Color(0xFF1976D2),
        centerTitle: true,
        elevation: 2,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // CARD 1: PENGATURAN KONEKSI ROUTER
                  Card(
                    elevation: 3,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Center(child: Text("KONEKSI ROUTER MIKROTIK", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey))),
                          const SizedBox(height: 12),
                          TextField(controller: _ipController, decoration: const InputDecoration(labelText: 'IP / Domain Router', prefixIcon: Icon(Icons.dns), border: OutlineInputBorder())),
                          const SizedBox(height: 12),
                          TextField(controller: _userController, decoration: const InputDecoration(labelText: 'Username Router', prefixIcon: Icon(Icons.person), border: OutlineInputBorder())),
                          const SizedBox(height: 12),
                          TextField(controller: _passController, obscureText: true, decoration: const InputDecoration(labelText: 'Password Router', prefixIcon: Icon(Icons.lock), border: OutlineInputBorder())),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // CARD 2: GENERATOR MASSAL (Mikhmon Style dengan Sinkronisasi Otomatis)
                  Card(
                    color: Colors.white,
                    elevation: 4,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Colors.green, width: 2)),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: const [
                              Icon(Icons.layers, color: Colors.green),
                              SizedBox(width: 8),
                              Text("GENERATOR VOUCHER MASSAL", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                            ],
                          ),
                          const SizedBox(height: 16),
                          
                          // MENU DROPDOWN LIST PROFIL (SINKRON OTOMATIS)
                          const Text("Pilih Profil dari List:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          const SizedBox(height: 6),
                          DropdownButtonFormField<String>(
                            value: _selectedProfile,
                            decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
                            items: _listProfilHotspot.map((profil) {
                              return DropdownMenuItem<String>(
                                value: profil['nama'],
                                child: Text("${profil['nama']} (Bawaan: ${profil['limit']})"),
                              );
                            }).toList(),
                            onChanged: (value) {
                              setState(() {
                                _selectedProfile = value;
                                var item = _listProfilHotspot.firstWhere((p) => p['nama'] == value);
                                _bulkUptimeController.text = item['limit']!;
                              });
                            },
                          ),
                          const SizedBox(height: 12),
                          
                          // ATUR ULANG WAKTU (LIMIT UPTIME)
                          TextField(
                            controller: _bulkUptimeController,
                            decoration: const InputDecoration(labelText: 'Atur Batas Waktu / Limit Uptime (Misal: 1h, 2h)', border: OutlineInputBorder(), isDense: true),
                          ),
                          const SizedBox(height: 12),
                          
                          // JUMLAH YANG MAU DIBUAT
                          TextField(
                            controller: _bulkQtyController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'Jumlah Voucher Yang Mau Dibuat', border: OutlineInputBorder(), isDense: true, prefixIcon: Icon(Icons.tag)),
                          ),
                          const SizedBox(height: 16),
                          
                          ElevatedButton.icon(
                            onPressed: _generateMassalVouchers,
                            icon: const Icon(Icons.bolt, color: Colors.white),
                            label: const Text("GENERATE MASSAL", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, padding: const EdgeInsets.symmetric(vertical: 14)),
                          )
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // PANEL MONITOR & OPSI SIMPAN / PDF
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: const Color(0xFFE3F2FD), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF90CAF9))),
                    child: Column(
                      children: [
                        const Text("MONITOR DATA HASIL GENERATE", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0D47A1), fontSize: 12)),
                        const SizedBox(height: 8),
                        SelectableText(_statusMessage, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF0D47A1))),
                        const SizedBox(height: 12),
                        if (_lastGeneratedCodes.isNotEmpty)
                          ElevatedButton.icon(
                            onPressed: _printOrSaveAsPdf,
                            icon: const Icon(Icons.picture_as_pdf, color: Colors.white),
                            label: const Text("CETAK / SIMPAN STRUK VOUCHER", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0D47A1)),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // CARD 3: BAGIAN BUAT PROFIL BARU
                  Card(
                    color: Colors.white,
                    elevation: 3,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: const BorderSide(color: Colors.orange, width: 1.5)),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: const [
                              Icon(Icons.add_box, color: Colors.orange),
                              SizedBox(width: 8),
                              Text("BUAT PROFIL BARU (Otomatis Masuk List Atas)", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange, fontSize: 13)),
                            ],
                          ),
                          const SizedBox(height: 12),
                          TextField(controller: _newProfileNameController, decoration: const InputDecoration(labelText: 'Nama Profil Baru (Misal: Paket_3Jam)', border: OutlineInputBorder(), isDense: true)),
                          const SizedBox(height: 12),
                          TextField(controller: _rateLimitController, decoration: const InputDecoration(labelText: 'Kecepatan / Rate Limit (Contoh: 1M/1M)', border: OutlineInputBorder(), isDense: true)),
                          const SizedBox(height: 12),
                          TextField(controller: _uptimeLimitController, decoration: const InputDecoration(labelText: 'Default Uptime (Contoh: 3h)', border: OutlineInputBorder(), isDense: true)),
                          const SizedBox(height: 12),
                          TextField(controller: _validityController, decoration: const InputDecoration(labelText: 'Validasi / Masa Aktif Paket (Contoh: 1d = 1 Hari)', border: OutlineInputBorder(), isDense: true)),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: _createNewProfile,
                            icon: const Icon(Icons.save, color: Colors.white),
                            label: const Text("SIMPAN PROFIL & SINKRONKAN", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, padding: const EdgeInsets.symmetric(vertical: 14)),
                          )
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}