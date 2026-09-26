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
        '/ip/hotspot/user/profile/print',
      ]);

      if (!mounted) return;

      final profiles = <String>{};

      for (final row in response) {
        if (row is Map) {
          final name = row['=name']?.toString().trim() ??
              row['name']?.toString().trim();
          if (name != null && name.isNotEmpty) {
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

    // Multi-page PDF tidak lagi dibatasi satu lembar.
    if (qty > 5000) {
      _showMessage('Jumlah maksimal 5000 voucher per proses.');
      return;
    }

    if (uptime.isEmpty) {
      _showMessage('Isi masa aktif voucher.');
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

      final commands = <String>[];

      for (final code in codes) {
        commands.addAll([
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

      final hasError = response.any((row) {
        if (row is! Map) return false;
        final type = (row['type'] ?? row['=type'] ?? '').toString();
        return type == '!trap' || type == '!fatal';
      });

      if (hasError) {
        _showMessage(
          'Gagal membuat voucher di MikroTik. Tidak mencetak PDF agar data tidak salah.',
        );
        return;
      }

      await _cetakPdf(codes, profile, uptime);

      if (!mounted) return;
      _showMessage(
        '$qty voucher berhasil dibuat dan PDF multi-halaman selesai dibuat.',
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

  Future<void> _cetakPdf(
    List<String> codes,
    String profile,
    String uptime,
  ) async {
    final pdf = pw.Document();

    const cardWidth = 88.0;
    const cardHeight = 62.0;
    const horizontalGap = 5.0;
    const verticalGap = 5.0;

    // A4 dengan margin 15pt:
    // area efektif kira-kira 565 x 812pt.
    // 6 kolom x 12 baris = 72 voucher/halaman.
    const columns = 6;
    const rows = 12;
    const perPage = columns * rows;

    for (int start = 0; start < codes.length; start += perPage) {
      final end = min(start + perPage, codes.length);
      final pageCodes = codes.sublist(start, end);

      final cards = <pw.Widget>[];

      for (final code in pageCodes) {
        cards.add(
          pw.Container(
            width: cardWidth,
            height: cardHeight,
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
                  'VOCERAN',
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
                pw.Text(
                  'User: $code',
                  style: const pw.TextStyle(fontSize: 6.5),
                ),
                pw.Text(
                  'Password: $code',
                  style: const pw.TextStyle(fontSize: 6.5),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  '$profile • $uptime',
                  style: const pw.TextStyle(fontSize: 6.5),
                ),
              ],
            ),
          ),
        );
      }

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(15),
          build: (context) {
            return pw.Wrap(
              spacing: horizontalGap,
              runSpacing: verticalGap,
              children: cards,
            );
          },
        ),
      );
    }

    await Printing.layoutPdf(
      onLayout: (format) async => pdf.save(),
      name: 'voceran_${DateTime.now().millisecondsSinceEpoch}.pdf',
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 3),
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
            ? const Center(child: CircularProgressIndicator())
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
                        hintText: 'Contoh: 72, 100, 200',
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
                        onPressed: _isLoading ? null : _prosesCetakDanSimpan,
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
                      'PDF otomatis dibagi menjadi beberapa lembar A4. '
                      'Setiap lembar berisi hingga 72 voucher.',
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
