import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'mikrotik_api.dart';

class TabVoucher extends StatefulWidget {
  const TabVoucher({super.key});

  @override
  State<TabVoucher> createState() => _TabVoucherState();
}

class _TabVoucherState extends State<TabVoucher> {
  List<Map<String, String>> _allVouchers = [];
  List<String> _listProfilFilter = ['Semua Profil'];
  String _selectedProfilFilter = 'Semua Profil';
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadDaftarVoucher();
  }

  // 1. AMBIL DATA VOUCHER DARI MIKROTIK
  Future<void> _loadDaftarVoucher() async {
    setState(() => _isLoading = true);
    try {
      var res = await MikrotikAPI.run([['/ip/hotspot/user/print']]);
      List<Map<String, String>> tempVouchers = [];
      Map<String, String> currentVoucher = {};
      Set<String> profilesFound = {'Semua Profil'};

      for (var line in res) {
        if (line.startsWith('=.id=')) {
          if (currentVoucher.isNotEmpty) {
            tempVouchers.add(currentVoucher);
            currentVoucher = {};
          }
          currentVoucher['id'] = line.substring(5);
        } else if (line.startsWith('=name=')) {
          currentVoucher['name'] = line.substring(6);
        } else if (line.startsWith('=profile=')) {
          String prof = line.substring(9);
          currentVoucher['profile'] = prof;
          profilesFound.add(prof);
        } else if (line.startsWith('=limit-uptime=')) {
          currentVoucher['limit-uptime'] = line.substring(14);
        } else if (line.startsWith('=comment=')) {
          currentVoucher['comment'] = line.substring(9);
        }
      }

      if (currentVoucher.isNotEmpty) {
        tempVouchers.add(currentVoucher);
      }

      setState(() {
        // Proteksi otomatis: Abaikan user 'default' bawaan sistem MikroTik agar aman dari terhapus
        _allVouchers = tempVouchers.where((v) => v['name'] != 'default').toList();
        _listProfilFilter = profilesFound.toList();
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      _showSnackBar("Gagal memuat voucher: $e", Colors.redAccent);
    }
  }

  // 2. ENGINE PENCETAKAN ULANG PDF (BISA SATUAN / MASSAL)
  Future<void> _cetakUlangPdf(List<Map<String, String>> vouchersToPrint) async {
    final pdf = pw.Document();
    
    pdf.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.symmetric(horizontal: 15, vertical: 15), 
      build: (pw.Context context) {
        return pw.Wrap(
          spacing: 5, runSpacing: 5,
          children: List.generate(vouchersToPrint.length, (index) {
            final v = vouchersToPrint[index];
            String kode = v['name'] ?? '-';
            String uptime = v['limit-uptime'] ?? '-';
            String profil = v['profile'] ?? 'default';

            return pw.Container(
              width: 88, height: 62,
              padding: const pw.EdgeInsets.all(4),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey800, width: 1),
                borderRadius: pw.BorderRadius.circular(4),
              ),
              child: pw.Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text("WIFI HOTSPOT", style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 7)),
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: const pw.BoxDecoration(color: PdfColors.grey200),
                    child: pw.Text(kode, style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 11, color: PdfColors.blue900)),
                  ),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Text("Up: $uptime", style: pw.TextStyle(fontSize: 6, fontWeight: pw.FontWeight.bold)),
                      pw.Text("Profil: $profil", style: const pw.TextStyle(fontSize: 5)),
                    ],
                  ),
                ],
              ),
            );
          }),
        );
      },
    ));

    await Printing.layoutPdf(onLayout: (format) async => pdf.save());
  }

  // 3. FUNGSI HAPUS VOUCHER SATU PER SATU (ECERAN)
  Future<void> _hapusVoucherTunggal(String id, String name) async {
    bool konfirmasi = await _showKonfirmasiDialog(
      "Hapus Eceran",
      "Apakah Bos yakin ingin menghapus voucher dengan kode: $name?",
      okText: "Ya, Hapus",
      okColor: Colors.red,
    );

    if (!konfirmasi) return;

    setState(() => _isLoading = true);
    try {
      var response = await MikrotikAPI.run([
        ['/ip/hotspot/user/remove', '=.id=$id']
      ]);

      if (response.contains("ERROR") || response.contains("!trap")) {
        _showSnackBar("Gagal menghapus voucher $name", Colors.redAccent);
      } else {
        _showSnackBar("Voucher $name berhasil dihapus!", Colors.green);
        _loadDaftarVoucher();
      }
    } catch (e) {
      _showSnackBar("Terjadi kesalahan: $e", Colors.redAccent);
    } final {
      setState(() => _isLoading = false);
    }
  }

  // 4. FUNGSI HAPUS VOUCHER SATU BATCH (MASSAL BERDASARKAN GRUP KOMENTAR)
  Future<void> _hapusVoucherGrup(String commentName, List<Map<String, String>> targets) async {
    bool konfirmasi = await _showKonfirmasiDialog(
      "Hapus Massal Satu Grup",
      "Perhatian Bos!\nSebanyak ${targets.length} voucher di grup '$commentName' akan DISAPU BERSIH secara permanen. Lanjutkan?",
      okText: "Hapus Semua",
      okColor: Colors.red,
    );

    if (!konfirmasi) return;

    setState(() => _isLoading = true);
    try {
      List<List<String>> batchCommand = [];
      for (var voucher in targets) {
        if (voucher['id'] != null) {
          batchCommand.add(['/ip/hotspot/user/remove', '=.id=${voucher['id']}']);
        }
      }

      var response = await MikrotikAPI.run(batchCommand);

      if (response.contains("ERROR") || response.contains("!trap")) {
        _showSnackBar("Beberapa atau seluruh voucher grup gagal dihapus", Colors.redAccent);
      } else {
        _showSnackBar("Sukses! ${targets.length} Voucher grup '$commentName' berhasil dibersihkan!", Colors.green);
      }
      _loadDaftarVoucher();
    } catch (e) {
      _showSnackBar("Terjadi kesalahan sistem: $e", Colors.redAccent);
    } final {
      setState(() => _isLoading = false);
    }
  }

  // HELPER DIALOG KONFIRMASI UNIVERSAL (Bisa Custom Warna & Teks Tombol)
  Future<bool> _showKonfirmasiDialog(
    String title, 
    String message, {
    String okText = "Ya, Proses", 
    Color okColor = Colors.blue
  }) async {
    return await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            content: Text(message),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Batal")),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(okText, style: TextStyle(color: okColor, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ) ??
        false;
  }

  void _showSnackBar(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message, style: const TextStyle(fontWeight: FontWeight.bold)), backgroundColor: color),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Jalankan Filtering Profil
    List<Map<String, String>> filteredList = _allVouchers.where((v) {
      if (_selectedProfilFilter == 'Semua Profil') return true;
      return v['profile'] == _selectedProfilFilter;
    }).toList();

    // Jalankan Pengelompokan berdasarkan Comment (Batch Pembuatan)
    Map<String, List<Map<String, String>>> groupedVouchers = {};
    for (var v in filteredList) {
      String key = v['comment'] ?? 'Dibuat Manual / Tanpa Grup';
      if (!groupedVouchers.containsKey(key)) {
        groupedVouchers[key] = [];
      }
      groupedVouchers[key]!.add(v);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Daftar Voucher", style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadDaftarVoucher,
          )
        ],
      ),
      body: _isLoading && _allVouchers.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // DROPDOWN FILTER BERDASARKAN PROFIL
                Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: DropdownButtonFormField<String>(
                    decoration: const InputDecoration(
                      labelText: "Filter Berdasarkan Profil",
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.filter_list),
                    ),
                    value: _selectedProfilFilter,
                    items: _listProfilFilter.map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
                    onChanged: (v) {
                      setState(() => _selectedProfilFilter = v ?? 'Semua Profil');
                    },
                  ),
                ),
                
                // LIST GRUP VOUCHER DENGAN EXPANSION TILE
                Expanded(
                  child: filteredList.isEmpty
                      ? const Center(child: Text("Tidak ada voucher ditemukan", style: TextStyle(color: Colors.grey)))
                      : RefreshIndicator(
                          onRefresh: _loadDaftarVoucher,
                          child: ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            itemCount: groupedVouchers.keys.length,
                            itemBuilder: (context, index) {
                              String groupKey = groupedVouchers.keys.elementAt(index);
                              List<Map<String, String>> itemsInGroup = groupedVouchers[groupKey]!;

                              return Card(
                                margin: const EdgeInsets.symmetric(vertical: 6),
                                elevation: 2,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                child: ExpansionTile(
                                  leading: const Icon(Icons.folder_shared, color: Colors.deepPurple),
                                  title: Text(
                                    groupKey, 
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)
                                  ),
                                  subtitle: Text("${itemsInGroup.length} Voucher ditemukan"),
                                  trailing: Wrap(
                                    spacing: 0,
                                    crossAxisAlignment: WrapCrossAlignment.center,
                                    children: [
                                      // 1. TOMBOL CETAK SATU GRUP MASSAL (DENGAN POPUP)
                                      IconButton(
                                        icon: const Icon(Icons.print, color: Colors.blueAccent),
                                        tooltip: "Cetak Massal Grup Ini",
                                        onPressed: () async {
                                          bool siapkanPrint = await _showKonfirmasiDialog(
                                            "Konfirmasi Cetak",
                                            "Apakah Bos ingin mencetak semua (${itemsInGroup.length}) voucher di grup '$groupKey'?",
                                            okText: "Cetak",
                                            okColor: Colors.blue,
                                          );
                                          if (siapkanPrint) _cetakUlangPdf(itemsInGroup);
                                        },
                                      ),
                                      // 2. TOMBOL HAPUS SATU GRUP MASSAL (DENGAN POPUP)
                                      IconButton(
                                        icon: const Icon(Icons.delete_sweep, color: Colors.redAccent),
                                        tooltip: "Hapus Masal Grup Ini",
                                        onPressed: () => _hapusVoucherGrup(groupKey, itemsInGroup),
                                      ),
                                      const Icon(Icons.expand_more),
                                    ],
                                  ),
                                  children: itemsInGroup.map((v) {
                                    return ListTile(
                                      leading: const Icon(Icons.vpn_key, color: Colors.orangeAccent),
                                      title: Text(
                                        v['name'] ?? '-',
                                        style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5),
                                      ),
                                      subtitle: Text("Profil: ${v['profile']} | Limit: ${v['limit-uptime'] ?? '-'}"),
                                      // 3. TOMBOL CETAK ECERAN / SATUAN (DENGAN POPUP)
                                      onTap: () async {
                                        bool siapkanPrint = await _showKonfirmasiDialog(
                                          "Cetak Voucher",
                                          "Apakah Bos yakin ingin mencetak voucher: ${v['name']}?",
                                          okText: "Cetak",
                                          okColor: Colors.blue,
                                        );
                                        if (siapkanPrint) _cetakUlangPdf([v]);
                                      },
                                      // 4. TOMBOL HAPUS ECERAN SATUAN VOUCHER (DENGAN POPUP)
                                      trailing: IconButton(
                                        icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 22),
                                        tooltip: "Hapus Voucher Ini",
                                        onPressed: () => _hapusVoucherTunggal(v['id'] ?? '', v['name'] ?? '-'),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              );
                            },
                          ),
                        ),
                ),
              ],
            ),
    );
  }
}