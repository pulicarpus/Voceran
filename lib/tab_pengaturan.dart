import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'mikrotik_api.dart'; // IMPORT API MIKROTIK UNTUK TES KONEKSI

class TabPengaturan extends StatefulWidget {
  const TabPengaturan({super.key});

  @override
  State<TabPengaturan> createState() => _TabPengaturanState();
}

class _TabPengaturanState extends State<TabPengaturan> {
  final TextEditingController _ipController = TextEditingController();
  final TextEditingController _userController = TextEditingController();
  final TextEditingController _passController = TextEditingController();

  // VARIABEL STATUS KONEKSI INDIKATOR
  bool _isLoadingStatus = false;
  bool _isConnected = false;
  String _statusMessage = "Memeriksa Koneksi...";

  @override
  void initState() {
    super.initState();
    _loadSavedData();
  }

  // Load data lama saat tab dibuka
  void _loadSavedData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _ipController.text = prefs.getString('ip') ?? '10.10.10.1';
      _userController.text = prefs.getString('user') ?? 'admin';
      _passController.text = prefs.getString('pass') ?? '';
    });
    
    // Begitu data terisi, langsung tes koneksi otomatis
    _checkMikrotikConnection();
  }

  // FUNGSI UTAMA CEK KONEKSI KE API MIKROTIK
  Future<void> _checkMikrotikConnection() async {
    if (!mounted) return;
    setState(() {
      _isLoadingStatus = true;
      _statusMessage = "Sedang menghubungkan...";
    });

    try {
      // Mengirimkan perintah paling ringan ke MikroTik untuk tes respon API
      var response = await MikrotikAPI.run([
        ['/system/identity/print']
      ]);

      if (!mounted) return;

      if (response.contains("ERROR") || response.contains("!trap")) {
        setState(() {
          _isConnected = false;
          _statusMessage = "Gagal: Akses API Ditolak";
        });
      } else {
        setState(() {
          _isConnected = true;
          _statusMessage = "Terhubung ke MikroTik";
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isConnected = false;
        _statusMessage = "Terputus / Jaringan Error";
      });
    } finally {
      if (mounted) {
        setState(() => _isLoadingStatus = false);
      }
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ip', _ipController.text);
    await prefs.setString('user', _userController.text);
    await prefs.setString('pass', _passController.text);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Koneksi Router Tersimpan!"))
      );
    }

    // Setelah data baru disimpan, langsung uji coba koneksi ulang
    _checkMikrotikConnection();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Pengaturan Router"), centerTitle: true),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            const Icon(Icons.router, size: 80, color: Colors.blueAccent),
            
            // ================= WIDGET INDIKATOR STATUS KONEKSI =================
            Container(
              margin: const EdgeInsets.only(top: 15, bottom: 25),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: _isLoadingStatus 
                    ? Colors.orange.withOpacity(0.1) 
                    : _isConnected ? Colors.green.withOpacity(0.1) : Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _isLoadingStatus 
                      ? Colors.orange 
                      : _isConnected ? Colors.green : Colors.red,
                  width: 1.5,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_isLoadingStatus)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orange),
                    )
                  else
                    Icon(
                      _isConnected ? Icons.check_circle_rounded : Icons.cancel_rounded,
                      color: _isConnected ? Colors.green : Colors.red,
                      size: 20,
                    ),
                  const SizedBox(width: 8),
                  Text(
                    _statusMessage,
                    style: TextStyle(
                      color: _isLoadingStatus 
                          ? Colors.orange.shade800 
                          : _isConnected ? Colors.green.shade800 : Colors.red.shade800,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            // ===================================================================

            TextField(
              controller: _ipController, 
              decoration: const InputDecoration(labelText: "IP Address", border: OutlineInputBorder(), prefixIcon: Icon(Icons.dns))
            ),
            const SizedBox(height: 15),
            TextField(
              controller: _userController, 
              decoration: const InputDecoration(labelText: "Username API", border: OutlineInputBorder(), prefixIcon: Icon(Icons.person))
            ),
            const SizedBox(height: 15),
            TextField(
              controller: _passController, 
              obscureText: true,
              decoration: const InputDecoration(labelText: "Password API", border: OutlineInputBorder(), prefixIcon: Icon(Icons.lock))
            ),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.save),
                label: const Text("SIMPAN KONEKSI"),
                onPressed: _save,
              ),
            ),
          ],
        ),
      ),
    );
  }
}