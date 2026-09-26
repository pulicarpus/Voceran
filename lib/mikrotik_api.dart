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
  final _qtyController = TextEditingController(text: '72');
  final _uptimeController = TextEditingController(text: '1h');

  List<String> _profiles = [];
  String? _selectedProfile;
  bool _isLoading = false;
  bool _isLoadingProfiles = false;

  static const int _columns = 6;
  static const int _rows = 12;
  static const int _perPage = _columns * _rows;

  @override
  void initState() {
    super.initState();
    _loadProfiles();
  }

  @override
  void dispose() {
    _qtyController.dispose();
    _uptimeController.dispose();
    super.dispose();
  }

  Future<void> _loadProfiles() async {
    if (_isLoadingProfiles) return;

    setState(() => _isLoadingProfiles = true);

    try {
      final response = await MikrotikAPI.run([
        ['/ip/hotspot/user/profile/print'],
      ]);

      if (!mounted) return;

      final profiles = <String>{};

      for (final word in response) {
        if (word.startsWith('=name=')) {
          final name = word.substring('=name='.length).trim();
          if (name.isNotEmpty) {
            profiles.add(name);
          }
        }
      }

      final sorted = profiles.toList()..sort();

      setState(() {
        _profiles = sorted;
        if (_selectedProfile != null &&
            !_profiles.contains(_selectedProfile)) {
          _selectedProfile = null;
        }
      });
    } catch (e) {
      if (mounted) {
        _showMessage('Gagal membaca profile: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingProfiles = false);
      }
    }
  }

  String _generateCode(Random random) {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

    return List.generate(
      6,
      (_) => chars[random.nextInt(chars.length)],
    ).join();
  }

  bool _hasRouterError(List<String> response) {
    return response.contains('!trap') ||
        response.contains('!fatal') ||
        response.contains('ERROR');
  }

  String _extractRouterMessage(List<String> response) {
    for (final word in response) {
      if (word.startsWith('=message=')) {
        return word.substring('=message='.length).trim();
      }
    }

    return 'RouterOS menolak perintah.';
  }

  Future<void> _prosesCetakDanSimpan() async {
    if (_isLoading) return;

    final profile = _selectedProfile;
    final qty = int.tryParse(_qtyController.text.trim());
    final uptime = _uptimeController.text.trim();

    if (profile == null || profile.isEmpty) {
      _showMessage('Pilih profile terlebih dahulu.');
      return;
    }

    if (qty == null || qty < 1) {
      _showMessage('Jumlah voucher minimal 1.');
      return;
    }

    if (qty > 5000) {
      _showMessage('Jumlah maksimal 5000 voucher per proses.');
      return;
    }

    if (uptime.isEmpty) {
      _showMessage('Isi masa aktif / limit uptime.');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final random = Random.secure();
      final codes = <String>[];
      final used = <String>{};

      while (codes.length < qty) {
        final code = _generateCode(random);
        if (used.add(code)) {
          codes.add(code);
        }
      }

      final commands = <List<String>>[];

      for (final code in codes) {
        commands.add([
          '/ip/hotspot/user/add',
          '=name=$code',
          '=password=$code',
          '=profile=$profile',
          '=limit-uptime=$uptime',
          '=comment=Voucher',
        ]);
      }

      final response = await MikrotikAPI.run(commands);

      if (!mounted) return;

      if (_hasRouterError(response)) {
        _showMessage(
          'Gagal membuat voucher: ${_extractRouterMessage(response)}',
        );
        return;
      }

      await _cetakPdfMultiPage(
        codes: codes,
        profile: profile,
        uptime: uptime,
      );
    } catch (e) {
      if (mounted) {
        _showMessage('Gagal mencetak voucher: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _cetakPdfMultiPage({
    required List<String> codes,
    required String profile,
    required String uptime,
  }) async {
    final totalPages = (codes.length + _perPage - 1) ~/ _perPage;

    if (mounted) {
      _showMessage(
        '${codes.length} voucher akan dicetak menjadi $totalPages halaman A4.',
      );
    }

    final pdf = pw.Document();

    for (int pageIndex = 0; pageIndex < totalPages; pageIndex++) {
      final start = pageIndex * _perPage;
      final end = min(start + _perPage, codes.length);

      final pageCodes = codes.sublist(start, end);

      final cards = <pw.Widget>[
        for (final code in pageCodes) _buildVoucherCard(
          code: code,
          profile: profile,
          uptime: uptime,
        ),
      ];

      // Setiap pw.Page di sini adalah SATU halaman PDF.
      // Tidak menggunakan Wrap yang bergantung pada pagination.
      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(15),
          build: (_) {
            return pw.Column(
              children: [
                pw.Expanded(
                  child: pw.Wrap(
                    spacing: 5,
                    runSpacing: 5,
                    children: cards,
                  ),
                ),
              ],
            );
          },
        ),
      );
    }

    final pdfBytes = await pdf.save();

    // Validasi sederhana: dokumen harus mempunyai jumlah halaman
    // sesuai jumlah batch sebelum diberikan ke Android Print Spooler.
    if (pdfBytes.isEmpty) {
      throw Exception('PDF kosong.');
    }

    await Printing.layoutPdf(
      name: 'voceran_${codes.length}_${totalPages}halaman.pdf',
      format: PdfPageFormat.a4,
      onLayout: (_) async => pdfBytes,
    );

    if (mounted) {
      _showMessage(
        'PDF siap: ${codes.length} voucher / $totalPages halaman A4.',
      );
    }
  }

  pw.Widget _buildVoucherCard({
    required String code,
    required String profile,
    required String uptime,
  }) {
    return pw.Container(
      width: 88,
      height: 62,
      padding: const pw.EdgeInsets.all(5),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(width: 0.8),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Column(
        mainAxisAlignment: pw.MainAxisAlignment.center,
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Text(
            'WIFI HOTSPOT',
            style: pw.TextStyle(
              fontSize: 8,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            code,
            style: pw.TextStyle(
              fontSize: 15,
              fontWeight: pw.FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
          pw.SizedBox(height: 3),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'Up: $uptime',
                style: pw.TextStyle(
                  fontSize: 6.5,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.Text(
                'Profil: $profile',
                style: const pw.TextStyle(fontSize: 6.5),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 4),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cetak Voucher'),
        actions: [
          IconButton(
            onPressed: _isLoadingProfiles ? null : _loadProfiles,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh profile',
          ),
        ],
      ),
      body: SafeArea(
        child: _isLoadingProfiles
            ? const Center(
                child: CircularProgressIndicator(),
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<String>(
                      value: _selectedProfile,
                      decoration: const InputDecoration(
                        labelText: 'Profile Hotspot',
                        border: OutlineInputBorder(),
                      ),
                      items: _profiles
                          .map(
                            (profile) => DropdownMenuItem<String>(
                              value: profile,
                              child: Text(profile),
                            ),
                          )
                          .toList(),
                      onChanged: _isLoading
                          ? null
                          : (value) {
                              setState(() => _selectedProfile = value);
                            },
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _qtyController,
                      enabled: !_isLoading,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Jumlah voucher',
                        hintText: 'Contoh: 72, 73, 100, 200',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _uptimeController,
                      enabled: !_isLoading,
                      decoration: const InputDecoration(
                        labelText: 'Masa aktif / limit uptime',
                        hintText: 'Contoh: 1h, 2h, 1d',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      height: 52,
                      child: ElevatedButton.icon(
                        onPressed: _isLoading
                            ? null
                            : _prosesCetakDanSimpan,
                        icon: _isLoading
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.print),
                        label: Text(
                          _isLoading
                              ? 'Memproses...'
                              : 'Buat & Cetak Voucher',
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '6 × 12 = 72 voucher per halaman A4. '
                      'Jumlah di atas 72 otomatis dibuat menjadi '
                      'beberapa halaman.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
