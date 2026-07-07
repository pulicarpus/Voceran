import 'package:flutter/material.dart';
import 'package:router_os_client/router_os_client.dart';
import 'dart:math';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Voceran MikroTik',
      theme: ThemeData(
        useMaterial3: true,
        primarySwatch: Colors.blue,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
      ),
      home: const VoucherScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class VoucherScreen extends StatefulWidget {
  const VoucherScreen({super.key});

  @override
  State<VoucherScreen> createState() => _VoucherScreenState();
}

class _VoucherScreenState extends State<VoucherScreen> {
  final _ipController = TextEditingController(text: "192.168.88.1");
  final _userController = TextEditingController(text: "admin");
  final _passController = TextEditingController();
  String _hasilVoucher = "-";
  bool _isLoading = false;

  @override
  void dispose() {
    _ipController.dispose();
    _userController.dispose();
    _passController.dispose();
    super.dispose();
  }

  String generateCode() {
    // Karakter acak yang aman (menghindari angka 0/1 dan huruf O/I supaya tidak membingungkan pembeli)
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    return List.generate(5, (index) => chars[Random().nextInt(chars.length)]).join();
  }

  Future<void> buatVoucher(String profil, String limitWaktu) async {
    if (_ipController.text.isEmpty || _userController.text.isEmpty) {
      showSnippet("IP dan Username tidak boleh kosong, bos!");
      return;
    }

    setState(() {
      _isLoading = true;
      _hasilVoucher = "Memproses...";
    });

    String kode = generateCode();
    
    // Inisialisasi client berdasarkan package router_os_client terbaru
    final client = RouterOSClient(
      address: _ipController.text.trim(),
      user: _userController.text.trim(),
      password: _passController.text,
      useSsl: false,
    );

    try {
      // 1. Lakukan login koneksi socket ke MikroTik
      bool isConnected = await client.login();
      
      if (!isConnected) {
        throw Exception("Gagal login ke MikroTik! Periksa username/password router, atau pastikan port API (8728) di Winbox sudah aktif.");
      }

      // 2. Jalankan perintah talk() untuk mendaftarkan user hotspot baru ke MikroTik v6
      await client.talk([
        '/ip/hotspot/user/add',
        '=name=$kode',
        '=password=$kode',
        '=profile=$profil',
        '=limit-uptime=$limitWaktu'
      ]);
      
      setState(() {
        _hasilVoucher = kode;
      });
      showSnippet("Sukses membuat voucher: $kode!");
      
    } catch (e) {
      showSnippet("Error: ${e.toString()}");
      setState(() { 
        _hasilVoucher = "-"; 
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void showSnippet(String pesan) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(pesan),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Voceran MikroTik v6', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.blue[800],
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Card Pengaturan Koneksi Router
              Card(
                elevation: 3,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      const Text(
                        "PENGATURAN KONEKSI ROUTER",
                        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _ipController,
                        decoration: const InputDecoration(
                          labelText: 'IP / Domain VPN Remote',
                          prefixIcon: Icon(Icons.router),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _userController,
                        decoration: const InputDecoration(
                          labelText: 'Username Router',
                          prefixIcon: Icon(Icons.person),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _passController,
                        decoration: const InputDecoration(
                          labelText: 'Password Router',
                          prefixIcon: Icon(Icons.lock),
                          border: OutlineInputBorder(),
                        ),
                        obscureText: true,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              
              // Bagian Tombol Pilihan Paket Jualan
              const Text(
                'PILIH PAKET VOUCHER:', 
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black87),
              ),
              const SizedBox(height: 8),
              
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green[600],
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: _isLoading ? null : () => buatVoucher('Paket_2K', '02:00:00'),
                child: const Text(
                  '2 Jam (Paket_2K)', 
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 12),
              
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue[700],
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: _isLoading ? null : () => buatVoucher('Paket_5K', '12:00:00'),
                child: const Text(
                  '12 Jam (Paket_5K)', 
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(height: 24),
              
              // Tampilan Hasil Voucher Untuk Pembeli
              Card(
                color: Colors.blue[50],
                shape: RoundedRectangleBorder(
                  side: BorderSide(color: Colors.blue[200]!, width: 2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    children: [
                      Text(
                        'KODE VOUCHER PELANGGAN', 
                        style: TextStyle(fontSize: 14, color: Colors.blue[900], fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 12),
                      _isLoading 
                          ? const CircularProgressIndicator()
                          : Text(
                              _hasilVoucher, 
                              style: TextStyle(
                                fontSize: 40, 
                                fontWeight: FontWeight.bold, 
                                letterSpacing: 4, 
                                color: Colors.blue[900],
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
    );
  }
}
