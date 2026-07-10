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
  final TextEditingController _qtyController = TextEditingController(text: '10');
  bool _isLoading = false;

  // Generator Kode Voucher unik
  String _generateKode() {
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    return List.generate(6, (index) => chars[Random().nextInt(chars.length)]).join();
  }

  // Ambil profil dari MikroTik
  void _loadProfil() async {
    setState(() => _isLoading = true);
    var res = await MikrotikAPI.run("10.10.10.1", "admin", "", [['/ip/hotspot/user/profile/print']]);
    List<String> temp = [];
    for (var item in res) {
      if (item.startsWith('=name=')) temp.add(item.substring(6));
    }
    setState(() {
      _listProfil = temp;
      _isLoading = false;
    });
  }

  // Desain PDF Elegan
  Future<void> _cetakPdf() async {
    final pdf = pw.Document();
    int qty = int.tryParse(_qtyController.text) ?? 1;

    pdf.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      build: (pw.Context context) {
        return pw.Wrap(
          spacing: 15, runSpacing: 15,
          children: List.generate(qty, (index) => pw.Container(
            width: 160, height: 80,
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.blueGrey700, width: 1.5),
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Column(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              children: [
                pw.Text("WIFI HOTSPOT", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9)),
                pw.SizedBox(height: 5),
                pw.Text(_generateKode(), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 18, color: PdfColors.blue900)),
                pw.SizedBox(height: 5),
                pw.Text("Profil: ${_selectedProfile ?? 'Default'}", style: const pw.TextStyle(fontSize: 7)),
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
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        children: [
          const Text("Menu Cetak Voucher", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 20),
          DropdownButtonFormField<String>(
            decoration: const InputDecoration(labelText: "Pilih Profil", border: OutlineInputBorder()),
            value: _selectedProfile,
            items: _listProfil.map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
            onChanged: (v) => setState(() => _selectedProfile = v),
          ),
          const SizedBox(height: 15),
          TextField(controller: _qtyController, decoration: const InputDecoration(labelText: "Jumlah Voucher", border: OutlineInputBorder())),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.print),
              label: const Text("Cetak Sekarang"),
              onPressed: _selectedProfile == null ? null : _cetakPdf,
            ),
          ),
          TextButton(onPressed: _loadProfil, child: const Text("Refresh List Profil"))
        ],
      ),
    );
  }
}