import 'dart:math';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'mikrotik_api.dart';

class TabCetak extends StatefulWidget {
  const TabCetak({super.key});

  @override
  State<TabCetak> createState() => _TabCetakState();
}

class _TabCetakState extends State<TabCetak> {
  List<String> _listProfil = [];
  String? _selectedProfile;
  final TextEditingController _qtyController = TextEditingController(text: '72'); // Default langsung 72 (1 lembar full)
  final TextEditingController _uptimeController = TextEditingController(text: '1h');
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadProfil();
  }

  String _generateKode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    return List.generate(6, (index) => chars[Random().nextInt(chars.length)]).join();
  }

  void _loadProfil() async {
    setState(() => _isLoading = true);
    var res = await MikrotikAPI.run([['/ip/hotspot/user/profile/print']]);
    List<String> temp = [];
    for (var item in res) {
      if (item.startsWith('=name=')) temp.add(item.substring(6));
    }
    setState(() {
      _listProfil = temp;
      _isLoading = false;
    });
  }

  Future<void> _prosesCetakDanSimpan() async {
    int qty = int.tryParse(_qtyController.text) ?? 1;
    String uptimeLimit = _uptimeController.text.trim();
    
    setState(() => _isLoading = true);

    List<List<String>> batchCommands = [];
    List<String> kodeVouchers = [];

    for (int i = 0; i < qty; i++) {
      String kode = _generateKode();
      kodeVouchers.add(kode);

      batchCommands.add([
        '/ip/hotspot/user/add',
        '=name=$kode',
        '=password=$kode',
        '=profile=${_selectedProfile ?? 'default'}',
        '=limit-uptime=$uptimeLimit',
        '=comment=App-${_selectedProfile ?? 'Voucher'}'
      ]);
    }

    var response = await MikrotikAPI.run(batchCommands);
    setState(() => _isLoading = false);

    if (response.contains("ERROR")) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Gagal mendaftarkan ke MikroTik!")),
        );
      }
      return;
    }

    // DESAIN MINI VOUCHER (Muat hingga 72 Voucher per A4)
    final pdf = pw.Document();
    pdf.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 20), // Margin tipis agar muat banyak
      build: (pw.Context context) {
        return pw.Wrap(
          spacing: 5,     // Jarak antar kolom
          runSpacing: 5,  // Jarak antar baris
          children: List.generate(qty, (index) => pw.Container(
            width: 88,    // Ukuran presisi untuk 6 kolom
            height: 62,   // Ukuran presisi untuk 12 baris
            padding: const pw.EdgeInsets.all(4),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey800, width: 1),
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Column(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text("WIFI HOTSPOT", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 7)),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                  child: pw.Text(kodeVouchers[index], style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12, color: PdfColors.blue900)),
                ),
                pw.Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text("Up: $uptimeLimit", style: pw.TextStyle(fontSize: 6, fontWeight: pw.FontWeight.bold)),
                    pw.Text("Profil: ${_selectedProfile ?? 'Def'}", style: const pw.TextStyle(fontSize: 5)),
                  ],
                ),
              ],
            ),
          )),
        );
      },
    ));

    await Printing.layoutPdf(onLayout: (format) async => pdf.save());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Menu Cetak Voucher", style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                children: [
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(labelText: "Pilih Profil", border: OutlineInputBorder()),
                    value: _selectedProfile,
                    items: _listProfil.map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
                    onChanged: (v) => setState(() => _selectedProfile = v),
                  ),
                  const SizedBox(height: 15),
                  TextField(
                    controller: _uptimeController,
                    decoration: const InputDecoration(labelText: "Kuota Waktu / Uptime (Contoh: 1h)", border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 15),
                  TextField(
                    controller: _qtyController,
                    decoration: const InputDecoration(labelText: "Jumlah Voucher", border: OutlineInputBorder()),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 25),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.print),
                      label: const Text("Cetak Sekarang"),
                      onPressed: _selectedProfile == null ? null : _prosesCetakDanSimpan,
                      style: ElevatedButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 15),
                  TextButton(
                    onPressed: _loadProfil,
                    child: const Text("Refresh List Profil", style: TextStyle(color: Colors.deepPurple)),
                  )
                ],
              ),
            ),
    );
  }
}