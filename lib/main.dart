import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:crypto/crypto.dart'; // Wajib pasang crypto: ^3.0.3 di pubspec.yaml
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

void main() {
  runApp(const VoceranApp());
}

class VoceranApp extends StatelessWidget {
  const VoceranApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Voceran MikroTik v6 Pro',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: const Color(0xFFF5F5F5),
      ),
      home: const VoceranHomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class VoceranHomePage extends StatefulWidget {
  const VoceranHomePage({Key? key}) : super(key: key);

  @override
  State<VoceranHomePage> createState() => _VoceranHomePageState();
}

class _VoceranHomePageState extends State<VoceranHomePage> {
  // Controller Input Router
  final TextEditingController _ipController = TextEditingController(text: '10.10.10.1');
  final TextEditingController _usernameController = TextEditingController(text: 'admin');
  final TextEditingController _passwordController = TextEditingController(text: '');

  // Controller Buat Paket Baru
  final TextEditingController _packageNameController = TextEditingController();
  final TextEditingController _limitController = TextEditingController(text: '1M/1M');
  final TextEditingController _quotaUptimeController = TextEditingController(text: '1h'); // Kuota internetan
  final TextEditingController _validityController = TextEditingController(text: '2d');     // Masa aktif kalender

  String _connectionStatus = "Belum terhubung ke router.";
  bool _isConnected = false;
  List<String> _voucherProfiles = [];

  // ==================== MIKROTIK CORE NETWORK PROTOCOL ====================

  String _md5Chap(String password, String challengeHex) {
    List<int> challengeBytes = [];
    for (int i = 0; i < challengeHex.length; i += 2) {
      challengeBytes.add(int.parse(challengeHex.substring(i, i + 2), radix: 16));
    }
    List<int> passwordBytes = utf8.encode(password);
    List<int> buffer = [0] + passwordBytes + challengeBytes;
    
    return '00' + md5.convert(buffer).toString();
  }

  List<int> _encodeLength(int length) {
    if (length < 0x80) {
      return [length];
    } else if (length < 0x4000) {
      length |= 0x8000;
      return [(length >> 8) & 0xFF, length & 0xFF];
    }
    return [length];
  }

  void _writeWord(Socket socket, String word) {
    List<int> wordBytes = utf8.encode(word);
    socket.add(_encodeLength(wordBytes.length));
    socket.add(wordBytes);
  }

  Future<List<String>> _sendMikrotikCommand(List<String> sentences) async {
    Socket? socket;
    List<String> responseWords = [];
    
    try {
      String ip = _ipController.text.trim();
      int port = 8728;
      
      if (ip.contains(':')) {
        List<String> parts = ip.split(':');
        ip = parts[0];
        port = int.parse(parts[1]);
      }

      socket = await Socket.connect(ip, port, timeout: const Duration(seconds: 7));
      
      _writeWord(socket, '/login');
      _writeWord(socket, '');

      await for (var data in socket) {
        String dataStr = utf8.decode(data, allowMalformed: true);
        responseWords.addAll(dataStr.split('\n'));
        if (dataStr.contains('!done') || dataStr.contains('!trap')) break;
      }

      String challenge = "";
      for (String word in responseWords) {
        if (word.contains('=ret=')) {
          challenge = word.split('=ret=')[1].trim();
        }
      }

      if (challenge.isEmpty) {
        throw Exception("Gagal mendapatkan kode enkripsi (Challenge) dari MikroTik!");
      }

      responseWords.clear();
      String hashedPass = _md5Chap(_passwordController.text, challenge);

      _writeWord(socket, '/login');
      _writeWord(socket, '=name=${_usernameController.text}');
      _writeWord(socket, '=response=$hashedPass');
      _writeWord(socket, '');

      await for (var data in socket) {
        String dataStr = utf8.decode(data, allowMalformed: true);
        responseWords.addAll(dataStr.split('\n'));
        if (dataStr.contains('!done') || dataStr.contains('!trap')) break;
      }

      bool loginSuccess = false;
      for (String word in responseWords) {
        if (word.contains('!done')) loginSuccess = true;
        if (word.contains('!trap')) {
          throw Exception("Username atau Password MikroTik Salah!");
        }
      }

      if (!loginSuccess) throw Exception("Koneksi ditolak oleh Router!");

      responseWords.clear();
      for (String sentence in sentences) {
        _writeWord(socket, sentence);
      }
      _writeWord(socket, '');

      await for (var data in socket) {
        String dataStr = utf8.decode(data, allowMalformed: true);
        responseWords.addAll(dataStr.split('\n'));
        if (dataStr.contains('!done') || dataStr.contains('!trap')) break;
      }

      await socket.flush();
      return responseWords;

    } finally {
      socket?.destroy();
    }
  }

  // ==================== OPERASI LOGIKA BUSINESS (SINKRON & SIMPAN) ====================

  Future<void> _sinkronisasiProfil() async {
    setState(() {
      _connectionStatus = "Sedang menghubungkan...";
    });

    try {
      List<String> rawReply = await _sendMikrotikCommand(['/ip/hotspot/user/profile/print']);
      List<String> profilesFound = [];

      for (String word in rawReply) {
        if (word.contains('=name=')) {
          String name = word.split('=name=')[1].split('\t')[0].replaceAll('\r', '').trim();
          if (name != 'default') {
            profilesFound.add(name);
          }
        }
      }

      setState(() {
        _voucherProfiles = profilesFound;
        _isConnected = true;
        _connectionStatus = "STATUS: TERHUBUNG KE MIKROTIK!";
      });

    } catch (e) {
      setState(() {
        _isConnected = false;
        _connectionStatus = "STATUS: GAGAL TERHUBUNG!";
      });
      _showErrorDialog(e.toString().replaceAll("Exception: ", ""));
    }
  }

  Future<void> _simpanProfilBaru() async {
    if (!_isConnected) {
      _showErrorDialog("Koneksi terputus! Silakan klik SINKRONISASI PROFIL terlebih dahulu.");
      return;
    }

    String namaPaket = _packageNameController.text.trim();
    String limit = _limitController.text.trim();
    String kuotaWaktu = _quotaUptimeController.text.trim().toLowerCase();
    String masaAktifKalender = _validityController.text.trim().toLowerCase();

    // Validasi Input Kosong
    if (namaPaket.isEmpty || limit.isEmpty || kuotaWaktu.isEmpty || masaAktifKalender.isEmpty) {
      _showErrorDialog("Semua kolom input tambah profil wajib diisi bray, tidak boleh ada yang kosong!");
      return;
    }

    // Validasi Format Waktu MikroTik (Regex Engine)
    final RegExp mikrotikTimeRegex = RegExp(r'^(\d+[smhd])+$');
    if (!mikrotikTimeRegex.hasMatch(kuotaWaktu) || !mikrotikTimeRegex.hasMatch(masaAktifKalender)) {
      _showErrorDialog("Format penulisan waktu salah! Wajib gunakan angka + kode waktu MikroTik (s/m/h/d).\n\nContoh:\n• Kuota: 1h (1 Jam)\n• Masa Aktif: 2d (2 Hari)");
      return;
    }

    // ENGINE UTAMA MIKHMON SCRIPT (Dipasang di on-login profile MikroTik)
    // Berfungsi membuat Scheduler dinamis agar voucher otomatis terhapus dalam 'X' Hari sejak pertama kali login.
    String mikhmonScript = 
        ':local u "\$user"; '
        ':if ([/system scheduler find name=\$u] = "") do={ '
        '/system scheduler add name=\$u start-date=[/system clock get date] start-time=[/system clock get time] interval=$masaAktifKalender on-event="/ip hotspot user remove [find name=\$u]; /system scheduler remove [find name=\$u];" '
        '}';

    try {
      // Eksekusi pembuatan profil ke MikroTik API
      await _sendMikrotikCommand([
        '/ip/hotspot/user/profile/add',
        '=name=$namaPaket',
        '=rate-limit=$limit',
        '=limit-uptime=$kuotaWaktu', // Mengunci durasi total internetan (bisa dicicil)
        '=on-login=$mikhmonScript',  // Mengunci masa tenggang kalender (pemicu hangus otomatis)
        '=idle-timeout=5m',          // Jika 5 menit HP tidak ada aktifitas, otomatis log-out biar kuota irit
        '=status-autorefresh=1m'
      ]);

      _packageNameController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Profil Paket '$namaPaket' Berhasil Dibuat!")),
      );
      
      _sinkronisasiProfil();

    } catch (e) {
      _showErrorDialog(e.toString().replaceAll("Exception: ", ""));
    }
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Sistem Notifikasi", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("OK", style: TextStyle(fontWeight: FontWeight.bold)),
          )
        ],
      ),
    );
  }

  // ==================== GENERATE & LAYOUT PDF VOUCHER ====================
  Future<void> _cetakVoucherDummy(String namaProfil) async {
    final pdf = pw.Document();
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Container(
            padding: const pw.EdgeInsets.all(10),
            child: pw.Column(
              children: [
                pw.Text("VOCERAN MIKROTIK V6 PRO", style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 10),
                pw.Divider(),
                pw.SizedBox(height: 10),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text("Paket Hotspot:"),
                    pw.Text(namaProfil, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  ],
                ),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text("Kode Voucher:"),
                    pw.Text("VCHR-${DateTime.now().millisecond}", style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => pdf.save());
  }

  // ==================== INTERFACE TAMPILAN WIDGET UI ====================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Voceran MikroTik v6 Pro', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.blue,
        centerTitle: true,
        elevation: 2,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // KOTAK 1: SETTING ROUTER
            Card(
              elevation: 3,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
              child: Padding(
                padding: const EdgeInsets.all(14.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const Text("PENGATURAN KONEKSI ROUTER", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                    const SizedBox(height: 10),
                    TextField(controller: _ipController, decoration: const InputDecoration(labelText: 'IP / Domain VPN Remote', border: OutlineInputBorder(), isDense: true)),
                    const SizedBox(height: 10),
                    TextField(controller: _usernameController, decoration: const InputDecoration(labelText: 'Username Router', border: OutlineInputBorder(), isDense: true)),
                    const SizedBox(height: 10),
                    TextField(controller: _passwordController, obscureText: true, decoration: const InputDecoration(labelText: 'Password Router', border: OutlineInputBorder(), isDense: true)),
                    const SizedBox(height: 15),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)), padding: const EdgeInsets.symmetric(vertical: 12)),
                            onPressed: _sinkronisasiProfil,
                            icon: const Icon(Icons.sync, size: 18),
                            label: const Text("SINKRONISASI PROFIL", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF9C27B0), foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)), padding: const EdgeInsets.symmetric(vertical: 12)),
                            onPressed: () {},
                            icon: const Icon(Icons.people, size: 18),
                            label: const Text("MONITOR AKTIF", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(_connectionStatus, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: _connectionStatus.contains("TERHUBUNG KE") ? Colors.blue : Colors.red)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 15),

            // SEKSI 2: TOMBOL TOMBOL CETAK VOUCHER
            const Text("PILIH PROFIL VOUCHER PELANGGAN:", style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black)),
            const SizedBox(height: 8),
            _voucherProfiles.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    child: Text("Belum ada tombol paket. Klik tombol \"SINKRONISASI PROFIL\" di atas setelah router terhubung.", style: TextStyle(color: Colors.grey, fontSize: 12), textAlign: TextAlign.center),
                  )
                : Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _voucherProfiles.map((profile) {
                      return ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4))),
                        onPressed: () => _cetakVoucherDummy(profile),
                        child: Text(profile, style: const TextStyle(fontWeight: FontWeight.bold)),
                      );
                    }).toList(),
                  ),
            const SizedBox(height: 15),

            // KOTAK 3: FITUR TAMBAH PROFIL BARU + ENGINE VALIDASI MIKHMON
            Card(
              elevation: 3,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
              side: const BorderSide(color: Colors.orange, width: 1),
              child: Padding(
                padding: const EdgeInsets.all(14.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("➕ BUAT PROFIL & LOGIKA MASA AKTIF", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.orange)),
                    const SizedBox(height: 12),
                    TextField(controller: _packageNameController, decoration: const InputDecoration(labelText: 'Nama Paket Baru (Contoh: Paket_1Jam)', border: OutlineInputBorder(), isDense: true)),
                    const SizedBox(height: 10),
                    TextField(controller: _limitController, decoration: const InputDecoration(labelText: 'Limit Kecepatan (Contoh: 1M/1M)', border: OutlineInputBorder(), isDense: true)),
                    const SizedBox(height: 10),
                    TextField(controller: _quotaUptimeController, decoration: const InputDecoration(labelText: 'Kuota Internet / Limit Uptime (Contoh: 1h)', border: OutlineInputBorder(), isDense: true)),
                    const SizedBox(height: 10),
                    TextField(controller: _validityController, decoration: const InputDecoration(labelText: 'Masa Berlaku Voucher / Validity (Contoh: 2d)', border: OutlineInputBorder(), isDense: true)),
                    const SizedBox(height: 15),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)), padding: const EdgeInsets.symmetric(vertical: 12)),
                        onPressed: _simpanProfilBaru,
                        child: const Text("Simpan Profil Ke MikroTik", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      ),
                    ),
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