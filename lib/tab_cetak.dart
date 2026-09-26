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
  final TextEditingController _qtyController =
      TextEditingController(text: '72');

  final TextEditingController _uptimeController =
      TextEditingController(text: '1h');

  final Random _random = Random();

  List<String> _listProfil = [];
  String? _selectedProfile;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadProfil();
  }

  @override
  void dispose() {
    _qtyController.dispose();
    _uptimeController.dispose();
    super.dispose();
  }

  String _generateKode() {
    const chars =
        'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

    return List.generate(
      6,
      (_) => chars[_random.nextInt(chars.length)],
    ).join();
  }

  Future<void> _loadProfil() async {
    if (_isLoading) return;

    if (mounted) {
      setState(() => _isLoading = true);
    }

    try {
      final response = await MikrotikAPI.run([
        ['/ip/hotspot/user/profile/print'],
      ]);

      if (!mounted) return;

      if (_isErrorResponse(response)) {
        setState(() => _isLoading = false);

        _showSnackBar(
          'Gagal memuat profil: '
          '${_extractRouterMessage(response)}',
          Colors.redAccent,
        );

        return;
      }

      final profiles = <String>[];
      final seen = <String>{};

      for (final line in response) {
        if (!line.startsWith('=name=')) {
          continue;
        }

        final name = line.substring(6).trim();

        if (name.isEmpty || seen.contains(name)) {
          continue;
        }

        seen.add(name);
        profiles.add(name);
      }

      profiles.sort(
        (a, b) => a.toLowerCase().compareTo(
              b.toLowerCase(),
            ),
      );

      var selected = _selectedProfile;

      if (selected == null ||
          !profiles.contains(selected)) {
        selected = profiles.isEmpty
            ? null
            : profiles.first;
      }

      setState(() {
        _listProfil = profiles;
        _selectedProfile = selected;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() => _isLoading = false);

      _showSnackBar(
        'Gagal memuat profil: $e',
        Colors.redAccent,
      );
    }
  }

  Future<void> _prosesCetakDanSimpan() async {
    if (_isLoading) return;

    final qty = int.tryParse(
          _qtyController.text.trim(),
        ) ??
        0;

    final uptimeLimit =
        _uptimeController.text.trim();

    final profile = _selectedProfile?.trim();

    if (profile == null || profile.isEmpty) {
      _showSnackBar(
        'Pilih profil terlebih dahulu.',
        Colors.orange,
      );
      return;
    }

    if (qty < 1) {
      _showSnackBar(
        'Jumlah voucher minimal 1.',
        Colors.orange,
      );
      return;
    }

    if (qty > 1000) {
      _showSnackBar(
        'Jumlah voucher maksimal 1000 per batch.',
        Colors.orange,
      );
      return;
    }

    if (uptimeLimit.isEmpty) {
      _showSnackBar(
        'Kuota waktu / uptime tidak boleh kosong.',
        Colors.orange,
      );
      return;
    }

    final kodeVouchers = <String>[];
    final generated = <String>{};

    while (kodeVouchers.length < qty) {
      final kode = _generateKode();

      if (generated.add(kode)) {
        kodeVouchers.add(kode);
      }
    }

    final batchCommands = <List<String>>[];

    for (final kode in kodeVouchers) {
      batchCommands.add([
        '/ip/hotspot/user/add',
        '=name=$kode',
        '=password=$kode',
        '=profile=$profile',
        '=limit-uptime=$uptimeLimit',
        '=comment=App-$profile',
      ]);
    }

    if (!mounted) return;

    setState(() => _isLoading = true);

    try {
      final response = await MikrotikAPI.run(
        batchCommands,
      );

      if (!mounted) return;

      if (_isErrorResponse(response)) {
        _showSnackBar(
          'Gagal mendaftarkan voucher: '
          '${_extractRouterMessage(response)}',
          Colors.redAccent,
          seconds: 5,
        );
        return;
      }

      await _cetakPdf(
        kodeVouchers,
        uptimeLimit,
        profile,
      );
    } catch (e) {
      if (mounted) {
        _showSnackBar(
          'Terjadi kesalahan saat membuat voucher: $e',
          Colors.redAccent,
          seconds: 5,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _cetakPdf(
    List<String> kodeVouchers,
    String uptimeLimit,
    String profile,
  ) async {
    if (kodeVouchers.isEmpty) return;

    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(
          horizontal: 15,
          vertical: 15,
        ),
        build: (pw.Context context) {
          return pw.Wrap(
            spacing: 5,
            runSpacing: 5,
            children: List.generate(
              kodeVouchers.length,
              (index) {
                return pw.Container(
                  width: 88,
                  height: 62,
                  padding: const pw.EdgeInsets.all(4),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(
                      color: PdfColors.grey800,
                      width: 1,
                    ),
                    borderRadius:
                        pw.BorderRadius.circular(4),
                  ),
                  child: pw.Column(
                    mainAxisAlignment:
                        pw.MainAxisAlignment
                            .spaceBetween,
                    children: [
                      pw.Text(
                        'WIFI HOTSPOT',
                        style: pw.TextStyle(
                          fontWeight:
                              pw.FontWeight.bold,
                          fontSize: 7,
                        ),
                      ),
                      pw.Container(
                        padding:
                            const pw.EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 1,
                        ),
                        decoration:
                            const pw.BoxDecoration(
                          color: PdfColors.grey200,
                        ),
                        child: pw.Text(
                          kodeVouchers[index],
                          style: pw.TextStyle(
                            fontWeight:
                                pw.FontWeight.bold,
                            fontSize: 11,
                            color:
                                PdfColors.blue900,
                          ),
                        ),
                      ),
                      pw.Row(
                        mainAxisAlignment:
                            pw.MainAxisAlignment
                                .spaceBetween,
                        children: [
                          pw.Text(
                            'Up: $uptimeLimit',
                            style: pw.TextStyle(
                              fontSize: 6,
                              fontWeight:
                                  pw.FontWeight.bold,
                            ),
                          ),
                          pw.Text(
                            'Profil: $profile',
                            style:
                                const pw.TextStyle(
                              fontSize: 5,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (format) async => pdf.save(),
    );
  }

  bool _isErrorResponse(List<String> response) {
    return response.contains('ERROR') ||
        response.contains('!trap') ||
        response.contains('!fatal');
  }

  String _extractRouterMessage(
    List<String> response,
  ) {
    for (final line in response) {
      if (line.startsWith('=message=')) {
        return line.substring(9);
      }
    }

    for (final line in response) {
      if (line.startsWith('=category=')) {
        return 'RouterOS category: '
            '${line.substring(10)}';
      }
    }

    return 'RouterOS tidak memberikan detail error.';
  }

  void _showSnackBar(
    String message,
    Color color, {
    int seconds = 3,
  }) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: color,
        duration: Duration(seconds: seconds),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Menu Cetak Voucher',
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  DropdownButtonFormField<String>(
                    decoration:
                        const InputDecoration(
                      labelText: 'Pilih Profil',
                      border: OutlineInputBorder(),
                    ),
                    value: _selectedProfile,
                    items: _listProfil
                        .map(
                          (profile) =>
                              DropdownMenuItem<String>(
                            value: profile,
                            child: Text(profile),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (!mounted) return;

                      setState(() {
                        _selectedProfile = value;
                      });
                    },
                  ),
                  const SizedBox(height: 15),
                  TextField(
                    controller: _uptimeController,
                    decoration:
                        const InputDecoration(
                      labelText:
                          'Kuota Waktu / Uptime (Contoh: 1h)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 15),
                  TextField(
                    controller: _qtyController,
                    decoration:
                        const InputDecoration(
                      labelText: 'Jumlah Voucher',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType:
                        TextInputType.number,
                  ),
                  const SizedBox(height: 25),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.print),
                      label: const Text(
                        'Cetak Sekarang',
                      ),
                      onPressed:
                          _selectedProfile == null
                              ? null
                              : _prosesCetakDanSimpan,
                      style:
                          ElevatedButton.styleFrom(
                        shape:
                            RoundedRectangleBorder(
                          borderRadius:
                              BorderRadius.circular(
                            10,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 15),
                  TextButton(
                    onPressed:
                        _isLoading ? null : _loadProfil,
                    child: const Text(
                      'Refresh List Profil',
                      style: TextStyle(
                        color: Colors.deepPurple,
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
