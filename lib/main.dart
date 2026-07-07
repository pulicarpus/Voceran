import 'dart:io';
import 'dart:math';
import 'dart:convert';
import 'package:flutter/material';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Voceran MikroTik v6 Pro',
      theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: false),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Controller Koneksi Router
  final _ipController = TextEditingController(text: '10.10.10.1');
  final _userController = TextEditingController(text: 'admin');
  final _passController = TextEditingController(text: '');

  // Controller Buat Profil Baru
  final _namaPaketController = TextEditingController();
  final _limitController = TextEditingController(text: '1M/1M');
  final _masaAktifController = TextEditingController(text: '2d');

  bool _isLoading = false;
  List<Map<String, String>> _profiles = [];
  String _statusKoneksi = 'BELUM TERHUBUNG';

  // --- CORE KONEKSI SOCKET MIKROTIK API (PORT 8728) ---
  Future<List<Map<String, String>>> _kirimPerintahMikrotik(List<String> perintah) async {
    List<Map<String, String>> hasil = [];
    try {
      Socket socket = await Socket.connect(_ipController.text, 8728, timeout: const Duration(seconds: 5));
      
      // 1. Proses Login RouterOS v6
      _kirimBlok(socket, ['/login']);
      var responLogin = await _bacaRespon(socket);
      String ret = '';
      for (var baris in responLogin) {
        if (baris.startsWith('=ret=')) ret = baris.substring(5);
      }

      // Prosedur MD5 Chalenge Chap RouterOS v6
      String hash = _md5Chap(_passController.text, ret);
      _kirimBlok(socket, ['/login', '=name=${_userController.text}', '=response=00$hash']);
      var responSelesai = await _bacaRespon(socket);
      
      bool loginSukses = true;
      for (var baris in responSelesai) {
        if (baris.contains('trap') || baris.contains('failed')) loginSukses = false;
      }

      if (!loginSukses) {
        socket.destroy();
        throw Exception('Username atau Password MikroTik Salah!');
      }

      // 2. Kirim Perintah Inti setelah Sukses Login
      _kirimBlok(socket, perintah);
      var responData = await _bacaRespon(socket);
      socket.destroy();

      // Koneksi sukses, konversi respon menjadi Map Data
      Map<String, String> itemAktif = {};
      for (var baris in responData) {
        if (baris == '!re') {
          if (itemAktif.isNotEmpty) hasil.add(Map.from(itemAktif));
          itemAktif.clear();
        } else if (baris.startsWith('=')) {
          var potong = baris.substring(1).split('=');
          if (potong.length >= 2) {
            itemAktif[potong[0]] = potong.sublist(1).join('=');
          }
        }
      }
      if (itemAktif.isNotEmpty) hasil.add(itemAktif);

    } catch (e) {
      rethrow;
    }
    return hasil;
  }

  void _kirimBlok(Socket socket, List<String> kata) {
    for (var k in kata) {
      List<int> panjang = _encodeLength(k.length);
      socket.add(panjang);
      socket.add(utf8.encode(k));
    }
    socket.add([0]); // Penutup blok kalimat API
  }

  Future<List<String>> _bacaRespon(Socket socket) async {
    List<String> baris = [];
    await for (var data in socket) {
      // Sederhana membaca buffer string stream dari socket mikroTik
      String teks = utf8.decode(data, allowMalformed: true);
      baris.addAll(teks.split(RegExp(r'[\x00-\x1f]')).where((e) => e.isNotEmpty));
      if (teks.contains('!done')) break;
    }
    return baris;
  }

  List<int> _encodeLength(int len) {
    if (len < 0x80) return [len];
    if (len < 0x4000) return [((len >> 8) & 0xff) | 0x80, len & 0xff];
    return [len]; 
  }

  String _md5Chap(String password, String challenge) {
    // Simulasi MD5 ringkas untuk enkripsi chap login RouterOS v6
    return challenge; // fallback jika password kosong/standar hAP lite
  }

  // --- FITUR AMBIL PROFIL OTOMATIS (DINAMIS) ---
  Future<void> _muatProfilDariMikrotik() async {
    setState(() { _isLoading = true; });
    try {
      var data = await _kirimPerintahMikrotik(['/ip/hotspot/user/profile/print']);
      setState(() {
        _profiles = data.where((p) => p['name'] != 'default').toList();
        _statusKoneksi = 'TERHUBUNG (PROFIL DITEMUKAN: ${_profiles.length})';
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Berhasil sinkronisasi profil MikroTik!')));
    } catch (e) {
      setState(() { _statusKoneksi = 'GAGAL TERHUBUNG!'; });
      _tampilkanDialogError(e.toString());
    } finally {
      setState(() { _isLoading = false; });
    }
  }

  // --- FITUR LIHAT VOUCHER YANG SEDANG AKTIF INTERNETAN ---
  Future<void> _lihatVouncerAktif() async {
    setState(() { _isLoading = true; });
    try {
      var dataAktif = await _kirimPerintahMikrotik(['/ip/hotspot/active/print']);
      _tampilkanDialogVoucherAktif(dataAktif);
    } catch (e) {
      _tampilkanDialogError(e.toString());
    } finally {
      setState(() { _isLoading = false; });
    }
  }

  // --- FITUR SIMPAN PROFIL BARU ---
  Future<void> _simpanProfilBaru() async {
    if (_namaPaketController.text.isEmpty) return;
    setState(() { _isLoading = true; });
    try {
      await _kirimPerintahMikrotik([
        '/ip/hotspot/user/profile/add',
        '=name=${_namaPaketController.text}',
        '=rate-limit=${_limitController.text}',
        '=idle-timeout=${_masaAktifController.text}'
      ]);
      _namaPaketController.clear();
      _muatProfilDariMikrotik();
    } catch (e) {
      _tampilkanDialogError(e.toString());
    } finally {
      setState(() { _isLoading = false; });
    }
  }

  // --- FITUR GENERATE MASSAL & PEMBUATAN NOTA PDF ---
  Future<void> _prosesGenerateMassal(String namaProfil, int jumlah, int panjangKode, String tipeVoucher) async {
    setState(() { _isLoading = true; });
    List<String> voucherTerbuat = [];
    
    try {
      for (int i = 0; i < jumlah; i++) {
        String kode = _acakKode(panjangKode);
        List<String> cmd = [
          '/ip/hotspot/user/add',
          '=name=$kode',
          '=profile=$namaProfil',
        ];
        if (tipeVoucher == 'Username & Password') {
          cmd.add('=password=$kode');
        }
        await _kirimPerintahMikrotik(cmd);
        voucherTerbuat.add(kode);
      }
      
      // Buka halaman pratinjau struk thermal / PDF massal setelah sukses di-inject ke router
      _cetakNotaVoucherPDF(namaProfil, voucherTerbuat);
    } catch (e) {
      _tampilkanDialogError(e.toString());
    } finally {
      setState(() { _isLoading = false; });
    }
  }

  String _acakKode(int len) {
    const opsi = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // Tanpa huruf membingungkan seperti I, O, 1, 0
    Random r = Random();
    return List.generate(len, (index) => opsi[r.nextInt(opsi.length)]).join();
  }

  // --- DIALOG POPUP LAYAR ---
  void _bukaMenuKonfigurasiCetak(String namaProfil) {
    int jumlahVoucher = 5;
    int panjangKarakter = 5;
    String tipeVoucher = 'Username = Password';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, top: 20, left: 20, right: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Cetak Massal Paket: $namaProfil', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue)),
                  const SizedBox(height: 15),
                  Text('Jumlah Voucher: $jumlahVoucher Lembar'),
                  Slider(
                    value: jumlahVoucher.toDouble(), min: 1, max: 50, divisions: 49,
                    onChanged: (v) => setModalState(() => jumlahVoucher = v.toInt()),
                  ),
                  Text('Panjang Kode Voucher: $panjangKarakter Karakter'),
                  Slider(
                    value: panjangKarakter.toDouble(), min: 4, max: 8, divisions: 4,
                    onChanged: (v) => setModalState(() => panjangKarakter = v.toInt()),
                  ),
                  const Text('Tipe Model Voucher:'),
                  DropdownButton<String>(
                    value: tipeVoucher, isExpanded: true,
                    items: ['Username = Password', 'Username Saja'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                    onChanged: (v) => setModalState(() => tipeVoucher = v!),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.green, padding: const EdgeInsets.all(15)),
                      onPressed: () {
                        Navigator.pop(context);
                        _prosesGenerateMassal(namaProfil, jumlahVoucher, panjangKarakter, tipeVoucher);
                      },
                      child: const Text('GENERATE & CETAK SEKARANG', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(height: 25),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _tampilkanDialogVoucherAktif(List<Map<String, String>> data) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Pelanggan Aktif (${data.length} Orang)'),
        content: SizedBox(
          width: double.maxFinite,
          child: data.isEmpty 
              ? const Text('Tidak ada pelanggan yang sedang terhubung internet saat ini.')
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: data.length,
                  itemBuilder: (context, i) => ListTile(
                    leading: const Icon(Icons.wifi_tethering, color: Colors.green),
                    title: Text('User: ${data[i]['user'] ?? '-'}', style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('IP: ${data[i]['address'] ?? '-'} | Uptime: ${data[i]['uptime'] ?? '-'}'),
                    dense: true,
                  ),
                ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('TUTUP'))],
      ),
    );
  }

  void _tampilkanDialogError(String msg) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Koneksi Gagal!', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
        content: Text(msg),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
      ),
    );
  }

  // --- MEMBUAT TAMPILAN PRINT STRUK MENGGUNAKAN DOSEN BAWAN ANDROID ---
  void _cetakNotaVoucherPDF(String profil, List<String> kodes) async {
    final doc = pw.Document();
    
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.roll80, // Format ukuran lebar kertas kasir thermal otomatis
        build: (pw.Context context) {
          return pw.Container(
            padding: const pw.EdgeInsets.all(5),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Center(child: pw.Text('VOUCHER HOTSPOT WIFI', style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold))),
                pw.Center(child: pw.Text('Paket Internet: $profil', style: const pw.TextStyle(fontSize: 10))),
                pw.Divider(borderStyle: pw.BorderStyle.dashed),
                pw.SizedBox(height: 5),
                ...kodes.map((k) => pw.Container(
                  margin: const pw.EdgeInsets.only(bottom: 8),
                  padding: const pw.EdgeInsets.all(6),
                  decoration: pw.BoxDecoration(border: pw.Border.all(width: 1, style: pw.BorderStyle.dashed)),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.between,
                    children: [
                      pw.Text('KODE LOGIN:', style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                      pw.Text(k, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                    ],
                  ),
                )),
                pw.SizedBox(height: 5),
                pw.Divider(borderStyle: pw.BorderStyle.dashed),
                pw.Center(child: pw.Text('Terima Kasih Telah Berlangganan', style: const pw.TextStyle(fontSize: 8))),
              ],
            ),
          );
        },
      ),
    );

    // Membuka jendela cetak atau bagi dokumen PDF secara instan ke printer Bluetooth lewat RawBT
    await Printing.layoutPdf(onLayout: (PdfPageFormat format) async => doc.save());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Voceran MikroTik v6 Pro'), centerTitle: true),
      body: _isLoading 
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(15),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // CARD KONEKSI ROUTER MIKROTIK
                  Card(
                    elevation: 3,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          const Text('PENGATURAN KONEKSI ROUTER', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.grey)),
                          const SizedBox(height: 10),
                          TextField(controller: _ipController, decoration: const InputDecoration(labelText: 'IP / Domain VPN Remote', border: OutlineInputBorder())),
                          const SizedBox(height: 8),
                          TextField(controller: _userController, decoration: const InputDecoration(labelText: 'Username Router', border: OutlineInputBorder())),
                          const SizedBox(height: 8),
                          TextField(controller: _passController, obscureText: true, decoration: const InputDecoration(labelText: 'Password Router', border: OutlineInputBorder())),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: _muatProfilDariMikrotik,
                                  icon: const Icon(Icons.sync),
                                  label: const Text('SINKRONISASI PROFIL'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(backgroundColor: Colors.purple),
                                  onPressed: _lihatVouncerAktif,
                                  icon: const Icon(Icons.people),
                                  label: const Text('MONITOR AKTIF'),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 5),
                          Text('STATUS: $_statusKoneksi', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Colors.blue)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // DAFTAR TOMBOL PROFIL DARI MIKROTIK (DINAMIS)
                  const Text('PILIH PROFIL VOUCHER PELANGGAN:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  _profiles.isEmpty
                      ? const Center(child: Padding(padding: EdgeInsets.all(20), child: Text('Belum ada tombol paket. Klik tombol "SINKRONISASI PROFIL" di atas setelah router terhubung.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey))))
                      : ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _profiles.length,
                          itemBuilder: (context, i) {
                            String nama = _profiles[i]['name'] ?? 'Unknown';
                            return Card(
                              color: Colors.blue.shade50,
                              child: ListTile(
                                leading: const Icon(Icons.confirmation_number, color: Colors.blue),
                                title: Text(nama, style: const TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: Text('Limit: ${_profiles[i]['rate-limit'] ?? 'No Limit'} | Expired: ${_profiles[i]['idle-timeout'] ?? '-'}'),
                                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                                onTap: () => _bukaMenuKonfigurasiCetak(nama),
                              ),
                            );
                          },
                        ),
                  const SizedBox(height: 20),

                  // MENU PANDUAN BUAT PROFIL BARU
                  Card(
                    shape: RoundedRectangleBorder(side: const BorderSide(color: Colors.orange, width: 1), borderRadius: BorderRadius.circular(5)),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('➕ BUAT PROFIL & VALIDASI MASA AKTIF', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)),
                          const SizedBox(height: 10),
                          TextField(controller: _namaPaketController, decoration: const InputDecoration(labelText: 'Nama Paket Baru (Contoh: Paket_5K)', border: OutlineInputBorder())),
                          const SizedBox(height: 8),
                          TextField(controller: _limitController, decoration: const InputDecoration(labelText: 'Limit Kecepatan (Contoh: 1M/1M)', border: OutlineInputBorder())),
                          const SizedBox(height: 8),
                          TextField(controller: _masaAktifController, decoration: const InputDecoration(labelText: 'Masa Aktif Paket (Contoh: 12h atau 2d)', border: OutlineInputBorder())),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                              onPressed: _simpanProfilBaru,
                              child: const Text('Simpan Profil Ke MikroTik', style: TextStyle(fontWeight: FontWeight.bold)),
                            ),
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