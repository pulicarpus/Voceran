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

  List<Map<String, String>> _profiles = [];
  Map<String, String>? _selectedProfile;
  String _usageDuration = '1h';
  bool _usageDetected = false;
  bool _isLoading = false;
  bool _isLoadingProfiles = false;

  static const _durationOptions = <String>[
    '15m', '30m', '1h', '2h', '3h', '5h', '6h', '12h', '1d', '2d', '3d', '7d', '14d', '30d'
  ];

  @override
  void initState() {
    super.initState();
    _loadProfiles();
  }

  @override
  void dispose() {
    _qtyController.dispose();
    super.dispose();
  }

  bool _hasError(List<String> r) =>
      r.contains('!trap') || r.contains('!fatal') || r.contains('ERROR');

  String _routerMessage(List<String> r) {
    for (final x in r) {
      if (x.startsWith('=message=')) return x.substring(9).trim();
    }
    return 'RouterOS menolak perintah.';
  }

  Future<void> _loadProfiles() async {
    if (_isLoadingProfiles) return;
    setState(() => _isLoadingProfiles = true);
    try {
      final r = await MikrotikAPI.run([
        ['/ip/hotspot/user/profile/print'],
      ]);
      if (!mounted) return;
      if (_hasError(r)) {
        _show('Gagal membaca profile: ${_routerMessage(r)}');
        return;
      }

      final profiles = <Map<String, String>>[];
      Map<String, String>? current;

      void finish() {
        if (current != null && (current!['name'] ?? '').trim().isNotEmpty) {
          final p = Map<String, String>.from(current!);
          p.addAll(_parseMikhmon(p['on-login'] ?? ''));
          profiles.add(p);
        }
        current = null;
      }

      for (final x in r) {
        if (x == '!re') {
          finish();
          current = {};
        } else if (x == '!done') {
          finish();
        } else if (x.startsWith('=name=')) {
          current ??= {};
          current!['name'] = x.substring(6).trim();
        } else if (x.startsWith('=rate-limit=')) {
          current ??= {};
          current!['rate-limit'] = x.substring(12).trim();
        } else if (x.startsWith('=shared-users=')) {
          current ??= {};
          current!['shared-users'] = x.substring(14).trim();
        } else if (x.startsWith('=on-login=')) {
          current ??= {};
          current!['on-login'] = x.substring(10);
        }
      }
      finish();

      profiles.sort((a, b) =>
          (a['name'] ?? '').toLowerCase().compareTo((b['name'] ?? '').toLowerCase()));

      setState(() {
        _profiles = profiles;
        if (_selectedProfile != null &&
            !profiles.any((p) => p['name'] == _selectedProfile!['name'])) {
          _selectedProfile = null;
        }
      });
    } catch (e) {
      if (mounted) _show('Gagal membaca profile: $e');
    } finally {
      if (mounted) setState(() => _isLoadingProfiles = false);
    }
  }

  Map<String, String> _parseMikhmon(String script) {
    final out = <String, String>{};
    const marker = ':put (",';
    final start = script.indexOf(marker);
    if (start < 0) return out;
    final end = script.indexOf('")', start);
    if (end < 0) return out;

    final fields = script.substring(start + marker.length, end).split(',');
    if (fields.length >= 4) {
      out['mikhmon'] = 'yes';
      out['expiry-mode'] = fields[0].trim();
      out['price'] = fields[1].trim();
      out['validity'] = fields[2].trim();
      out['selling-price'] = fields[3].trim();
      if (fields.length > 5) out['lock-user'] = fields[5].trim();
    }
    return out;
  }

  String _generateCode(Random random) {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    return List.generate(6, (_) => chars[random.nextInt(chars.length)]).join();
  }

  Future<Set<String>> _loadExistingNames() async {
    final r = await MikrotikAPI.run([
      ['/ip/hotspot/user/print'],
    ]);
    if (_hasError(r)) throw Exception(_routerMessage(r));
    final names = <String>{};
    for (final x in r) {
      if (x.startsWith('=name=')) names.add(x.substring(6).trim().toUpperCase());
    }
    return names;
  }

  Future<String?> _detectUsageDuration(String profile) async {
    // Mikhmon stores validity in the profile script, but limit-uptime belongs
    // to each HotSpot user. Reuse the most common existing value for this
    // profile instead of inventing one. This keeps existing packages intact.
    try {
      final r = await MikrotikAPI.run([
        ['/ip/hotspot/user/print', '?profile=$profile'],
      ]);
      if (_hasError(r)) return null;

      final counts = <String, int>{};
      for (final x in r) {
        if (x.startsWith('=limit-uptime=')) {
          final v = x.substring(14).trim();
          if (v.isNotEmpty && v != '0s') counts[v] = (counts[v] ?? 0) + 1;
        }
      }
      if (counts.isEmpty) return null;
      counts.entries.toList().sort((a, b) => b.value.compareTo(a.value));
      return counts.entries.first.key;
    } catch (_) {
      return null;
    }
  }

  String _inferFromName(String name) {
    final s = name.toLowerCase().replaceAll(' ', '');
    final hour = RegExp(r'(\d+)\-?jam').firstMatch(s);
    if (hour != null) return '${hour.group(1)}h';
    final week = RegExp(r'(\d+)\-?minggu').firstMatch(s);
    if (week != null) return '${int.parse(week.group(1)!) * 7}d';
    final day = RegExp(r'(\d+)\-?hari').firstMatch(s);
    if (day != null) return '${day.group(1)}d';
    final dayEn = RegExp(r'(\d+)\-?day').firstMatch(s);
    if (dayEn != null) return '${dayEn.group(1)}d';
    return '1h';
  }

  Future<void> _selectProfile(Map<String, String>? profile) async {
    setState(() {
      _selectedProfile = profile;
      _usageDetected = false;
      _usageDuration = profile == null ? '1h' : _inferFromName(profile['name'] ?? '');
    });
    if (profile == null) return;

    final detected = await _detectUsageDuration(profile['name'] ?? '');
    if (!mounted || _selectedProfile?['name'] != profile['name']) return;
    if (detected != null) {
      setState(() {
        _usageDuration = detected;
        _usageDetected = true;
      });
    }
  }

  Future<void> _createAndPrint() async {
    if (_isLoading) return;
    final profile = _selectedProfile;
    final qty = int.tryParse(_qtyController.text.trim());
    if (profile == null) {
      _show('Pilih paket/profile terlebih dahulu.');
      return;
    }
    if (qty == null || qty < 1 || qty > 5000) {
      _show('Jumlah voucher harus 1 sampai 5000.');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final existing = await _loadExistingNames();
      final random = Random.secure();
      final codes = <String>[];
      final used = <String>{};
      while (codes.length < qty) {
        final code = _generateCode(random);
        if (!existing.contains(code) && used.add(code)) codes.add(code);
      }

      // Mikhmon checks vc/up/empty on first login. Username=password is a
      // voucher, therefore use the vc- prefix. Do not use EXPNS here.
      final now = DateTime.now();
      final batch = 'vc-${now.millisecondsSinceEpoch % 1000}-'
          '${now.month.toString().padLeft(2, '0')}.${now.day.toString().padLeft(2, '0')}.${(now.year % 100).toString().padLeft(2, '0')}-';

      final commands = <List<String>>[];
      for (final code in codes) {
        commands.add([
          '/ip/hotspot/user/add',
          '=name=$code',
          '=password=$code',
          '=profile=${profile['name']}',
          '=limit-uptime=$_usageDuration',
          '=comment=$batch',
        ]);
      }

      final response = await MikrotikAPI.run(commands);
      if (!mounted) return;
      if (_hasError(response)) {
        _show('Gagal membuat voucher: ${_routerMessage(response)}');
        return;
      }

      await _printPdf(
        codes,
        profile['name'] ?? '-',
        profile['rate-limit'] ?? '',
        _usageDuration,
        profile['validity'] ?? '',
      );
      if (mounted) {
        _show('$qty voucher berhasil dibuat. Masa berlaku tetap mengikuti profile/Mikhmon.');
      }
    } catch (e) {
      if (mounted) _show('Gagal membuat voucher: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _printPdf(
    List<String> codes,
    String profile,
    String rate,
    String uptime,
    String validity,
  ) async {
    final pdf = pw.Document();
    const perPage = 72;
    for (var start = 0; start < codes.length; start += perPage) {
      final pageCodes = codes.sublist(start, min(start + perPage, codes.length));
      final cards = <pw.Widget>[];
      for (final code in pageCodes) {
        cards.add(pw.Container(
          width: 88,
          height: 62,
          padding: const pw.EdgeInsets.all(4),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(width: .8),
            borderRadius: pw.BorderRadius.circular(4),
          ),
          child: pw.Column(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('VOCERAN', style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold)),
              pw.Text(code, style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold, letterSpacing: 1.1)),
              pw.Text('$profile • pakai $uptime', style: const pw.TextStyle(fontSize: 5.5)),
              pw.Text('Berlaku $validity • $rate', style: const pw.TextStyle(fontSize: 5.5)),
              pw.Text('User: $code  Pass: $code', style: const pw.TextStyle(fontSize: 5.5)),
            ],
          ),
        ));
      }
      pdf.addPage(pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(15),
        build: (_) => pw.Wrap(spacing: 5, runSpacing: 5, children: cards),
      ));
    }
    await Printing.layoutPdf(
      name: 'voceran_${codes.length}.pdf',
      onLayout: (_) async => pdf.save(),
    );
  }

  void _show(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), duration: const Duration(seconds: 4)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Buat & Cetak Voucher'),
        actions: [
          IconButton(
            onPressed: _isLoadingProfiles ? null : _loadProfiles,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loadingBody(),
    );
  }

  Widget _loadingBody() {
    if (_isLoadingProfiles) return const Center(child: CircularProgressIndicator());
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DropdownButtonFormField<Map<String, String>>(
            value: _selectedProfile,
            decoration: const InputDecoration(
              labelText: 'Paket / Profile',
              border: OutlineInputBorder(),
            ),
            items: _profiles.map((p) {
              final m = p['mikhmon'] == 'yes';
              return DropdownMenuItem(
                value: p,
                child: Text('${p['name']} • ${p['rate-limit'] ?? '-'}${m ? ' • Mikhmon' : ''}'),
              );
            }).toList(),
            onChanged: _isLoading ? null : _selectProfile,
          ),
          if (_selectedProfile != null) ...[
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Paket: ${_selectedProfile!['name'] ?? '-'}', style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text('Speed: ${_selectedProfile!['rate-limit'] ?? 'Unlimited'}'),
                    Text('Masa berlaku: ${_selectedProfile!['validity'] ?? 'mengikuti profile'}'),
                    Text('Durasi pemakaian: $_usageDuration${_usageDetected ? ' (terdeteksi dari voucher lama)' : ' (otomatis)'}'),
                    if (_selectedProfile!['mikhmon'] == 'yes')
                      const Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: Text(
                          'Kompatibilitas Mikhmon aktif. Script expiry profile tidak diubah.',
                          style: TextStyle(color: Colors.green, fontWeight: FontWeight.w600),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _durationOptions.contains(_usageDuration) ? _usageDuration : null,
              decoration: const InputDecoration(
                labelText: 'Durasi pemakaian voucher',
                helperText: 'Bisa disesuaikan; masa berlaku kalender tetap milik profile/Mikhmon.',
                border: OutlineInputBorder(),
              ),
              items: _durationOptions.map((x) => DropdownMenuItem(value: x, child: Text(x))).toList(),
              onChanged: _isLoading ? null : (v) => setState(() => _usageDuration = v ?? _usageDuration),
            ),
          ],
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
          const SizedBox(height: 20),
          SizedBox(
            height: 52,
            child: ElevatedButton.icon(
              onPressed: _isLoading ? null : _createAndPrint,
              icon: _isLoading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.print),
              label: Text(_isLoading ? 'Memproses...' : 'Buat & Cetak Voucher'),
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            'Voucher Mikhmon dibuat dengan komentar vc- dan tanpa EXPNS Voceran. Profile lama tidak disentuh.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
