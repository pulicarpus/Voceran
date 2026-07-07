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

  // Controller Fitur: Tambah Profil Paket
  final TextEditingController _newProfileNameController = TextEditingController();
  final TextEditingController _rateLimitController = TextEditingController(text: '1M/1M');
  final TextEditingController _validityController = TextEditingController(text: '2d'); 

  String _statusMessage = '-';
  bool _isLoading = false;

  // Generator kode voucher acak yang aman (5 digit)
  String _generateRandomVoucher() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    Random rand = Random();
    return List.generate(5, (index) => chars[rand.nextInt(chars.length)]).join();
  }

  // VALIDASI FORM UTAMA
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

  // MESIN UTAMA KOMUNIKASI MIKROTIK API VIA RAW SOCKET
  Future<String> _executeMikrotikCommand(List<String> command) async {
    Socket? socket;
    try {
      String ip = _ipController.text.trim();
      String user = _userController.text.trim();
      String pass = _passController.text;

      // Timeout 4 detik agar user tidak menunggu terlalu lama jika IP salah
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

      // Prosedur Login API MikroTik
      sendWord('/login');
      sendWord('=name=$user');
      sendWord('=password=$pass');
      socket.add([0]);
      await socket.flush();

      await Future.delayed(const Duration(milliseconds: 300));

      // Kirim Perintah Utama jika ada
      if (command.isNotEmpty) {
        for (var word in command) {
          sendWord(word);
        }
        socket.add([0]);
        await socket.flush();
        await Future.delayed(const Duration(milliseconds: 300));
      }
      
      return "SUCCESS";
    } catch (e) {
      return "Gagal Koneksi: Router Tidak Merespons / API Nonaktif";
    } finally {
      socket?.destroy();
    }
  }

  // FUNGSI FITUR BARU: Cek & Test Koneksi Langsung ke Router
  Future<void> _testConnection() async {
    if (!_validateConnectionInputs()) return;

    setState(() {
      _isLoading = true;
      _statusMessage = "Sedang mengetes koneksi...";
    });

    // Kita kirim perintah ringan mengambil nama identitas router untuk tes login
    List<String> cmd = ['/system/identity/print'];
    String result = await _executeMikrotikCommand(cmd);

    setState(() {
      _isLoading = false;
    });

    if (result == "SUCCESS") {
      _statusMessage = "STATUS KONEKSI:\nTERHUBUNG DAN SIAP! PROD.";
      _showSnackBar("Koneksi Sukses! MikroTik merespons dengan baik, bos. 🚀", Colors.green);
    } else {
      _statusMessage = "STATUS KONEKSI:\nGAGAL TERHUBUNG!";
      _showSnackBar("Gagal! Cek IP/Password/Port API 8728 di MikroTik.", Colors.redAccent);
    }
  }

  // FUNGSI 1: Cetak Voucher + Set Limit Waktu Penggunaan (Uptime)
  Future<void> _createVoucher(String profileName, String limitUptime) async {
    if (!_validateConnectionInputs()) return;

    setState(() {
      _isLoading = true;
      _statusMessage = "Sedang Mencetak Voucher...";
    });

    String code = _generateRandomVoucher();

    List<String> cmd = [
      '/ip/hotspot/user/add',
      '=name=$code',
      '=password=$code',
      '=profile=$profileName',
      '=limit-uptime=$limitUptime', 
      '=comment=Cetak_App_Android'
    ];

    String result = await _executeMikrotikCommand(cmd);

    setState(() {
      _isLoading = false;
      if (result == "SUCCESS") {
        _statusMessage = "KODE VOUCHER: $code\n(Durasi Sesi: $limitUptime)";
      } else {
        _statusMessage = result;
      }
    });
  }

  // FUNGSI 2: Tambah Profil Paket + Skrip Validasi Masa Aktif (Validity)
  Future<void> _createNewProfile() async {
    if (!_validateConnectionInputs()) return;

    String profName = _newProfileNameController.text.trim();
    String rateLimit = _rateLimitController.text.trim();
    String validity = _validityController.text.trim();

    if (profName.isEmpty || rateLimit.isEmpty || validity.isEmpty) {
      _showSnackBar("Semua kolom profil baru wajib diisi, bos!", Colors.redAccent);
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = "Menyimpan profil baru ke MikroTik...";
    });

    String onLoginScript = 
        ':local u \$"user"; /system scheduler add name=\$u interval=$validity on-event="/ip hotspot user remove [find name=\$u]; /ip hotspot active remove [find user=\$u]; /system scheduler remove [find name=\$u];"';

    List<String> cmd = [
      '/ip/hotspot/user/profile/add',
      '=name=$profName',
      '=shared-users=1',
      '=rate-limit=$rateLimit',
      '=on-login=$onLoginScript'
    ];

    String result = await _executeMikrotikCommand(cmd);

    setState(() {
      _isLoading = false;
      if (result == "SUCCESS") {
        _statusMessage = "PROFIL SUKSES!\nPaket '$profName' Aktif $validity Hari.";
        _newProfileNameController.clear();
        _showSnackBar("Profil '$profName' berhasil ditambahkan!", Colors.green);
      } else {
        _statusMessage = result;
      }
    });
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
                  // CARD 1: PENGATURAN & TOMBOL CEK KONEKSI
                  Card(
                    elevation: 3,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Center(
                            child: Text("PENGATURAN KONEKSI ROUTER", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _ipController,
                            decoration: const InputDecoration(labelText: 'IP / Domain VPN Remote', prefixIcon: Icon(Icons.dns), border: OutlineInputBorder()),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _userController,
                            decoration: const InputDecoration(labelText: 'Username Router', prefixIcon: Icon(Icons.person), border: OutlineInputBorder()),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _passController,
                            obscureText: true,
                            decoration: const InputDecoration(labelText: 'Password Router', prefixIcon: Icon(Icons.lock), border: OutlineInputBorder()),
                          ),
                          const SizedBox(height: 14),
                          
                          // TOMBOL BARU REQUEST USER: CEK KONEKSI
                          ElevatedButton.icon(
                            onPressed: _testConnection,
                            icon: const Icon(Icons.swap_horizontal_circle, color: Colors.white),
                            label: const Text("CEK KONEKSI KE ROUTER", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF3F51B5), // Warna Indigo Informatif
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // MENU UTAMA: CETAK VOUCHER BERDASARKAN WAKTU
                  const Text("CETAK VOUCHER PELANGGAN:", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87)),
                  const SizedBox(height: 8),
                  
                  ElevatedButton.icon(
                    onPressed: () => _createVoucher('Paket_1Jam', '1h'), 
                    icon: const Icon(Icons.bolt, color: Colors.white),
                    label: const Text('1 Jam (Masa Aktif 2 Hari)', style: TextStyle(fontSize: 15, color: Colors.white, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF5722), padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                  ),
                  const SizedBox(height: 8),
                  
                  ElevatedButton.icon(
                    onPressed: () => _createVoucher('Paket_2K', '2h'), 
                    icon: const Icon(Icons.confirmation_number, color: Colors.white),
                    label: const Text('2 Jam (Paket_2K)', style: TextStyle(fontSize: 15, color: Colors.white, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF4CAF50), padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                  ),
                  const SizedBox(height: 8),
                  
                  ElevatedButton.icon(
                    onPressed: () => _createVoucher('Paket_5K', '12h'), 
                    icon: const Icon(Icons.star, color: Colors.white),
                    label: const Text('12 Jam (Paket_5K)', style: TextStyle(fontSize: 15, color: Colors.white, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E88E5), padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                  ),
                  const SizedBox(height: 16),

                  // KOTAK HASIL/OUTPUT VOUCHER
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: const Color(0xFFE3F2FD), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFF90CAF9))),
                    child: Column(
                      children: [
                        const Text("HASIL PEMPROSESAN / KODE VOUCHER", style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF0D47A1), fontSize: 12)),
                        const SizedBox(height: 8),
                        Text(_statusMessage, textAlign: TextAlign.center, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0D47A1))),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // CARD 2: FITUR TAMBAH PROFIL PAKET BARU
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
                              Icon(Icons.add_moderator, color: Colors.orange),
                              SizedBox(width: 8),
                              Text("BUAT PROFIL & VALIDASI MASA AKTIF", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange, fontSize: 14)),
                            ],
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _newProfileNameController,
                            decoration: const InputDecoration(labelText: 'Nama Paket Baru (Contoh: Paket_1Jam)', border: OutlineInputBorder(), isDense: true),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _rateLimitController,
                            decoration: const InputDecoration(labelText: 'Limit Kecepatan (Contoh: 1M/1M)', border: OutlineInputBorder(), isDense: true),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _validityController,
                            decoration: const InputDecoration(
                              labelText: 'Masa Aktif Paket (Contoh: 2d = 2 Hari)', 
                              helperText: 'Catatan: d=Hari, h=Jam (Misal: 2d artinya aktif 2 hari setelah login pertama)',
                              border: OutlineInputBorder(), 
                              isDense: true
                            ),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            onPressed: _createNewProfile,
                            icon: const Icon(Icons.save, color: Colors.white),
                            label: const Text("Simpan Profil Ke MikroTik", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
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