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

  Future<void> _loadDaftarVoucher() async {
    if (_isLoading) return;

    if (mounted) {
      setState(() => _isLoading = true);
    }

    try {
      final response = await MikrotikAPI.run([
        ['/ip/hotspot/user/print'],
      ]);

      if (!mounted) return;

      if (_isErrorResponse(response)) {
        final message = _extractRouterMessage(response);
        setState(() => _isLoading = false);
        _showSnackBar(
          'Gagal memuat voucher: $message',
          Colors.redAccent,
        );
        return;
      }

      final vouchers = _parseVoucherResponse(response);
      final profiles = <String>{'Semua Profil'};

      for (final voucher in vouchers) {
        final profile = voucher['profile'];
        if (profile != null && profile.trim().isNotEmpty) {
          profiles.add(profile.trim());
        }
      }

      final filteredVouchers = vouchers
          .where((voucher) => voucher['name'] != 'default')
          .toList();

      final sortedProfiles = profiles.toList();
      sortedProfiles.sort((a, b) {
        if (a == 'Semua Profil') return -1;
        if (b == 'Semua Profil') return 1;
        return a.toLowerCase().compareTo(b.toLowerCase());
      });

      var selectedProfile = _selectedProfilFilter;
      if (!sortedProfiles.contains(selectedProfile)) {
        selectedProfile = 'Semua Profil';
      }

      setState(() {
        _allVouchers = filteredVouchers;
        _listProfilFilter = sortedProfiles;
        _selectedProfilFilter = selectedProfile;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() => _isLoading = false);
      _showSnackBar(
        'Gagal memuat voucher: $e',
        Colors.redAccent,
      );
    }
  }

  List<Map<String, String>> _parseVoucherResponse(
    List<String> response,
  ) {
    final vouchers = <Map<String, String>>[];
    Map<String, String>? current;

    void finishCurrent() {
      if (current == null || current!.isEmpty) return;

      final name = current!['name'];
      if (name != null && name.trim().isNotEmpty) {
        vouchers.add(Map<String, String>.from(current!));
      }

      current = null;
    }

    for (final line in response) {
      if (line == '!re') {
        finishCurrent();
        current = <String, String>{};
        continue;
      }

      if (line == '!done') {
        finishCurrent();
        continue;
      }

      if (line == '!trap' || line == '!fatal') {
        continue;
      }

      if (line.startsWith('=.id=')) {
        current ??= <String, String>{};
        current!['id'] = line.substring(5);
        continue;
      }

      if (line.startsWith('=name=')) {
        current ??= <String, String>{};
        current!['name'] = line.substring(6);
        continue;
      }

      if (line.startsWith('=profile=')) {
        current ??= <String, String>{};
        current!['profile'] = line.substring(9);
        continue;
      }

      if (line.startsWith('=limit-uptime=')) {
        current ??= <String, String>{};
        current!['limit-uptime'] = line.substring(14);
        continue;
      }

      if (line.startsWith('=comment=')) {
        current ??= <String, String>{};
        current!['comment'] = line.substring(9);
        continue;
      }
    }

    finishCurrent();
    return vouchers;
  }

  bool _isErrorResponse(List<String> response) {
    return response.contains('ERROR') ||
        response.contains('!trap') ||
        response.contains('!fatal');
  }

  String _extractRouterMessage(List<String> response) {
    for (final line in response) {
      if (line.startsWith('=message=')) {
        return line.substring(9);
      }
    }

    for (final line in response) {
      if (line.startsWith('=category=')) {
        return 'RouterOS category: ${line.substring(10)}';
      }
    }

    return 'RouterOS tidak memberikan detail error.';
  }

  Future<void> _cetakUlangPdf(
    List<Map<String, String>> vouchersToPrint,
  ) async {
    if (vouchersToPrint.isEmpty) {
      _showSnackBar(
        'Tidak ada voucher untuk dicetak.',
        Colors.orange,
      );
      return;
    }

    try {
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
                vouchersToPrint.length,
                (index) {
                  final voucher = vouchersToPrint[index];

                  final kode =
                      voucher['name']?.trim().isNotEmpty == true
                          ? voucher['name']!
                          : '-';

                  final uptime =
                      voucher['limit-uptime']?.trim().isNotEmpty == true
                          ? voucher['limit-uptime']!
                          : '-';

                  final profil =
                      voucher['profile']?.trim().isNotEmpty == true
                          ? voucher['profile']!
                          : 'default';

                  return pw.Container(
                    width: 88,
                    height: 62,
                    padding: const pw.EdgeInsets.all(4),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(
                        color: PdfColors.grey800,
                        width: 1,
                      ),
                      borderRadius: pw.BorderRadius.circular(4),
                    ),
                    child: pw.Column(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text(
                          'WIFI HOTSPOT',
                          style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold,
                            fontSize: 7,
                          ),
                        ),
                        pw.Container(
                          padding: const pw.EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 1,
                          ),
                          decoration: const pw.BoxDecoration(
                            color: PdfColors.grey200,
                          ),
                          child: pw.Text(
                            kode,
                            style: pw.TextStyle(
                              fontWeight: pw.FontWeight.bold,
                              fontSize: 11,
                              color: PdfColors.blue900,
                            ),
                          ),
                        ),
                        pw.Row(
                          mainAxisAlignment:
                              pw.MainAxisAlignment.spaceBetween,
                          children: [
                            pw.Text(
                              'Up: $uptime',
                              style: pw.TextStyle(
                                fontSize: 6,
                                fontWeight: pw.FontWeight.bold,
                              ),
                            ),
                            pw.Text(
                              'Profil: $profil',
                              style: const pw.TextStyle(fontSize: 5),
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
    } catch (e) {
      _showSnackBar(
        'Gagal mencetak voucher: $e',
        Colors.redAccent,
      );
    }
  }

  Future<void> _hapusVoucherTunggal(
    String id,
    String name,
  ) async {
    if (id.trim().isEmpty) {
      _showSnackBar(
        'ID voucher tidak ditemukan.',
        Colors.redAccent,
      );
      return;
    }

    final konfirmasi = await _showKonfirmasiDialog(
      'Hapus Eceran',
      'Apakah Bos yakin ingin menghapus voucher dengan kode: $name?',
      okText: 'Ya, Hapus',
      okColor: Colors.red,
    );

    if (!konfirmasi || !mounted) return;

    setState(() => _isLoading = true);

    try {
      final response = await MikrotikAPI.run([
        [
          '/ip/hotspot/user/remove',
          '=.id=$id',
        ],
      ]);

      if (!mounted) return;

      if (_isErrorResponse(response)) {
        _showSnackBar(
          'Gagal menghapus voucher $name: '
          '${_extractRouterMessage(response)}',
          Colors.redAccent,
        );
      } else {
        _showSnackBar(
          'Voucher $name berhasil dihapus.',
          Colors.green,
        );
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar(
          'Terjadi kesalahan: $e',
          Colors.redAccent,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }

    await _loadDaftarVoucher();
  }

  Future<void> _hapusVoucherGrup(
    String commentName,
    List<Map<String, String>> targets,
  ) async {
    if (targets.isEmpty) return;

    final konfirmasi = await _showKonfirmasiDialog(
      'Hapus Massal Satu Grup',
      'Perhatian Bos!\n\n'
          'Sebanyak ${targets.length} voucher di grup '
          '\'$commentName\' akan dihapus permanen.\n\n'
          'Lanjutkan?',
      okText: 'Hapus Semua',
      okColor: Colors.red,
    );

    if (!konfirmasi || !mounted) return;

    setState(() => _isLoading = true);

    try {
      final batchCommand = <List<String>>[];

      for (final voucher in targets) {
        final id = voucher['id'];

        if (id != null && id.trim().isNotEmpty) {
          batchCommand.add([
            '/ip/hotspot/user/remove',
            '=.id=$id',
          ]);
        }
      }

      if (batchCommand.isEmpty) {
        _showSnackBar(
          'Tidak ada ID voucher yang valid.',
          Colors.redAccent,
        );
        return;
      }

      final response = await MikrotikAPI.run(batchCommand);

      if (!mounted) return;

      if (_isErrorResponse(response)) {
        _showSnackBar(
          'Sebagian atau seluruh voucher gagal dihapus: '
          '${_extractRouterMessage(response)}',
          Colors.redAccent,
        );
      } else {
        _showSnackBar(
          '${targets.length} voucher grup '
          '\'$commentName\' berhasil dihapus.',
          Colors.green,
        );
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar(
          'Terjadi kesalahan sistem: $e',
          Colors.redAccent,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }

    await _loadDaftarVoucher();
  }

  Future<bool> _showKonfirmasiDialog(
    String title,
    String message, {
    String okText = 'Ya, Proses',
    Color okColor = Colors.blue,
  }) async {
    if (!mounted) return false;

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },
              child: const Text('Batal'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, true);
              },
              child: Text(
                okText,
                style: TextStyle(
                  color: okColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );

    return result ?? false;
  }

  void _showSnackBar(
    String message,
    Color color,
  ) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: color,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredList = _allVouchers.where((voucher) {
      if (_selectedProfilFilter == 'Semua Profil') {
        return true;
      }

      return voucher['profile'] == _selectedProfilFilter;
    }).toList();

    final groupedVouchers =
        <String, List<Map<String, String>>>{};

    for (final voucher in filteredList) {
      final rawComment = voucher['comment']?.trim();

      final groupKey =
          rawComment == null || rawComment.isEmpty
              ? 'Dibuat Manual / Tanpa Grup'
              : rawComment;

      groupedVouchers.putIfAbsent(
        groupKey,
        () => <Map<String, String>>[],
      );

      groupedVouchers[groupKey]!.add(voucher);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Daftar Voucher',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _isLoading ? null : _loadDaftarVoucher,
          ),
        ],
      ),
      body: _isLoading && _allVouchers.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: DropdownButtonFormField<String>(
                    decoration: const InputDecoration(
                      labelText: 'Filter Berdasarkan Profil',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.filter_list),
                    ),
                    value: _selectedProfilFilter,
                    items: _listProfilFilter
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
                            if (value == null || !mounted) return;

                            setState(() {
                              _selectedProfilFilter = value;
                            });
                          },
                  ),
                ),
                Expanded(
                  child: filteredList.isEmpty
                      ? const Center(
                          child: Text(
                            'Tidak ada voucher ditemukan',
                            style: TextStyle(color: Colors.grey),
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _loadDaftarVoucher,
                          child: ListView.builder(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                            ),
                            itemCount: groupedVouchers.length,
                            itemBuilder: (context, index) {
                              final groupKey =
                                  groupedVouchers.keys.elementAt(index);

                              final itemsInGroup =
                                  groupedVouchers[groupKey]!;

                              return Card(
                                margin: const EdgeInsets.symmetric(
                                  vertical: 6,
                                ),
                                elevation: 2,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: ExpansionTile(
                                  leading: const Icon(
                                    Icons.folder_shared,
                                    color: Colors.deepPurple,
                                  ),
                                  title: Text(
                                    groupKey,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                    ),
                                  ),
                                  subtitle: Text(
                                    '${itemsInGroup.length} Voucher ditemukan',
                                  ),
                                  trailing: Wrap(
                                    spacing: 0,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      IconButton(
                                        icon: const Icon(
                                          Icons.print,
                                          color: Colors.blueAccent,
                                        ),
                                        tooltip: 'Cetak Massal Grup Ini',
                                        onPressed: _isLoading
                                            ? null
                                            : () async {
                                                final siap =
                                                    await _showKonfirmasiDialog(
                                                  'Konfirmasi Cetak',
                                                  'Apakah Bos ingin mencetak '
                                                      'semua (${itemsInGroup.length}) '
                                                      'voucher di grup '
                                                      '\'$groupKey\'?',
                                                  okText: 'Cetak',
                                                  okColor: Colors.blue,
                                                );

                                                if (siap && mounted) {
                                                  await _cetakUlangPdf(
                                                    itemsInGroup,
                                                  );
                                                }
                                              },
                                      ),
                                      IconButton(
                                        icon: const Icon(
                                          Icons.delete_sweep,
                                          color: Colors.redAccent,
                                        ),
                                        tooltip: 'Hapus Massal Grup Ini',
                                        onPressed: _isLoading
                                            ? null
                                            : () => _hapusVoucherGrup(
                                                  groupKey,
                                                  itemsInGroup,
                                                ),
                                      ),
                                      const Icon(Icons.expand_more),
                                    ],
                                  ),
                                  children: itemsInGroup.map(
                                    (voucher) {
                                      final name = voucher['name'] ?? '-';

                                      return ListTile(
                                        leading: const Icon(
                                          Icons.vpn_key,
                                          color: Colors.orangeAccent,
                                        ),
                                        title: Text(
                                          name,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            letterSpacing: 0.5,
                                          ),
                                        ),
                                        subtitle: Text(
                                          'Profil: ${voucher['profile'] ?? '-'}'
                                          ' | Limit: '
                                          '${voucher['limit-uptime'] ?? '-'}',
                                        ),
                                        onTap: _isLoading
                                            ? null
                                            : () async {
                                                final siap =
                                                    await _showKonfirmasiDialog(
                                                  'Cetak Voucher',
                                                  'Apakah Bos yakin ingin '
                                                      'mencetak voucher: $name?',
                                                  okText: 'Cetak',
                                                  okColor: Colors.blue,
                                                );

                                                if (siap && mounted) {
                                                  await _cetakUlangPdf(
                                                    [voucher],
                                                  );
                                                }
                                              },
                                        trailing: IconButton(
                                          icon: const Icon(
                                            Icons.delete_outline,
                                            color: Colors.redAccent,
                                            size: 22,
                                          ),
                                          tooltip: 'Hapus Voucher Ini',
                                          onPressed: _isLoading
                                              ? null
                                              : () => _hapusVoucherTunggal(
                                                    voucher['id'] ?? '',
                                                    name,
                                                  ),
                                        ),
                                      );
                                    },
                                  ).toList(),
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
