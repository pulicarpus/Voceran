import 'package:flutter/material.dart';
import 'mikrotik_api.dart';

class TabProfil extends StatefulWidget {
  const TabProfil({super.key});

  @override
  State<TabProfil> createState() => _TabProfilState();
}

class _TabProfilState extends State<TabProfil> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _rateController =
      TextEditingController(text: '1M/1M');
  final TextEditingController _timeController =
      TextEditingController(text: '1d');

  List<Map<String, String>> _listProfil = [];
  bool _isLoading = false;

  final String _scriptPembersihOtomatis =
      r':local uuser $user; :local utime [/ip hotspot user get [find name=$uuser] uptime]; '
      r':local ltime [/ip hotspot user get [find name=$uuser] limit-uptime]; '
      r':if ($utime >= $ltime) do={ /ip hotspot user remove [find name=$uuser]; }';

  @override
  void initState() {
    super.initState();
    _loadDataProfil();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _rateController.dispose();
    _timeController.dispose();
    super.dispose();
  }

  Future<void> _loadDataProfil() async {
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
        final message = _extractRouterMessage(response);

        setState(() => _isLoading = false);

        _showSnackBar(
          'Gagal memuat profil: $message',
          Colors.redAccent,
        );
        return;
      }

      final profiles = _parseProfileResponse(response);

      setState(() {
        _listProfil = profiles;
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

  List<Map<String, String>> _parseProfileResponse(
    List<String> response,
  ) {
    final profiles = <Map<String, String>>[];
    Map<String, String>? current;

    void finishCurrent() {
      if (current == null || current!.isEmpty) return;

      final name = current!['name'];

      if (name != null && name.trim().isNotEmpty) {
        profiles.add(Map<String, String>.from(current!));
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

      if (line.startsWith('=rate-limit=')) {
        current ??= <String, String>{};
        current!['rate-limit'] = line.substring(12);
        continue;
      }

      if (line.startsWith('=session-timeout=')) {
        current ??= <String, String>{};
        current!['session-timeout'] = line.substring(17);
        continue;
      }

      if (line.startsWith('=shared-users=')) {
        current ??= <String, String>{};
        current!['shared-users'] = line.substring(14);
        continue;
      }
    }

    finishCurrent();

    return profiles;
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

  Future<void> _tambahProfil() async {
    final name = _nameController.text.trim();
    final rate = _rateController.text.trim();
    final time = _timeController.text.trim();

    if (name.isEmpty) {
      _showSnackBar(
        'Nama profil tidak boleh kosong, Bos!',
        Colors.orange,
      );
      return;
    }

    if (_isLoading) return;

    setState(() => _isLoading = true);

    try {
      final response = await MikrotikAPI.run([
        [
          '/ip/hotspot/user/profile/add',
          '=name=$name',
          '=rate-limit=$rate',
          '=session-timeout=$time',
          '=shared-users=1',
          '=on-logout=$_scriptPembersihOtomatis',
        ],
      ]);

      if (!mounted) return;

      if (_isErrorResponse(response)) {
        _showSnackBar(
          'Gagal menyimpan profil: '
          '${_extractRouterMessage(response)}',
          Colors.redAccent,
        );
        return;
      }

      _nameController.clear();

      _showSnackBar(
        'Profil berhasil dibuat + Auto-Clean aktif!',
        Colors.green,
      );
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

    await _loadDataProfil();
  }

  Future<void> _updateProfil(
    String id,
    String name,
    String rateLimit,
    String sessionTimeout,
    String sharedUsers,
  ) async {
    if (id.trim().isEmpty) {
      _showSnackBar(
        'ID profil tidak ditemukan.',
        Colors.redAccent,
      );
      return;
    }

    final parsedSharedUsers = int.tryParse(sharedUsers);

    if (parsedSharedUsers == null || parsedSharedUsers < 1) {
      _showSnackBar(
        'Shared Users harus berupa angka minimal 1.',
        Colors.orange,
      );
      return;
    }

    if (_isLoading) return;

    setState(() => _isLoading = true);

    try {
      final response = await MikrotikAPI.run([
        [
          '/ip/hotspot/user/profile/set',
          '=.id=$id',
          '=rate-limit=$rateLimit',
          '=session-timeout=$sessionTimeout',
          '=shared-users=$parsedSharedUsers',
          '=on-logout=$_scriptPembersihOtomatis',
        ],
      ]);

      if (!mounted) return;

      if (_isErrorResponse(response)) {
        _showSnackBar(
          'Gagal memperbarui profil $name: '
          '${_extractRouterMessage(response)}',
          Colors.redAccent,
        );
      } else {
        _showSnackBar(
          'Profil $name berhasil diperbarui!',
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

    await _loadDataProfil();
  }

  Future<void> _openEditDialog(
    Map<String, String> profil,
  ) async {
    final rateEditController = TextEditingController(
      text: profil['rate-limit'] ?? '',
    );

    final timeEditController = TextEditingController(
      text: profil['session-timeout'] ?? '',
    );

    final sharedEditController = TextEditingController(
      text: profil['shared-users'] ?? '1',
    );

    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: Text(
              'Edit Profil: ${profil['name'] ?? '-'}',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.deepPurple,
              ),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: rateEditController,
                    decoration: const InputDecoration(
                      labelText:
                          'Rate Limit / Kecepatan (Contoh: 1M/1M)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: timeEditController,
                    decoration: const InputDecoration(
                      labelText:
                          'Masa Aktif / Session Timeout (Contoh: 1d)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: sharedEditController,
                    decoration: const InputDecoration(
                      labelText:
                          'Shared Users (Bisa dipakai berapa HP)',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    '*Fitur Auto-Clean otomatis aktif pada profil ini setelah disimpan.',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                },
                child: const Text('Batal'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(dialogContext);

                  _updateProfil(
                    profil['id'] ?? '',
                    profil['name'] ?? '',
                    rateEditController.text.trim(),
                    timeEditController.text.trim(),
                    sharedEditController.text.trim(),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                ),
                child: const Text(
                  'Simpan',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          );
        },
      );
    } finally {
      rateEditController.dispose();
      timeEditController.dispose();
      sharedEditController.dispose();
    }
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
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _loadDataProfil,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              elevation: 3,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: ExpansionTile(
                initiallyExpanded: _listProfil.isEmpty,
                title: const Text(
                  'Buat Profil Baru',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.deepPurple,
                  ),
                ),
                leading: const Icon(
                  Icons.add_box,
                  color: Colors.deepPurple,
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        TextField(
                          controller: _nameController,
                          decoration: const InputDecoration(
                            labelText: 'Nama Profil',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _rateController,
                          decoration: const InputDecoration(
                            labelText:
                                'Rate Limit (Contoh: 1M/1M)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _timeController,
                          decoration: const InputDecoration(
                            labelText:
                                'Masa Aktif (Contoh: 1d)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: _isLoading
                              ? const Center(
                                  child:
                                      CircularProgressIndicator(),
                                )
                              : ElevatedButton.icon(
                                  icon: const Icon(Icons.save),
                                  label: const Text(
                                    'Simpan ke Router',
                                  ),
                                  onPressed: _tambahProfil,
                                  style:
                                      ElevatedButton.styleFrom(
                                    backgroundColor:
                                        Colors.deepPurple,
                                    foregroundColor:
                                        Colors.white,
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 25),
            const Text(
              'Daftar Profil Terpasang',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            _listProfil.isEmpty && _isLoading
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: CircularProgressIndicator(),
                    ),
                  )
                : _listProfil.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(20),
                          child: Text(
                            'Tidak ada profil ditemukan',
                          ),
                        ),
                      )
                    : Column(
                        children: _listProfil.map((prof) {
                          final rate =
                              prof['rate-limit']?.trim() ?? '';

                          return Card(
                            elevation: 2,
                            margin: const EdgeInsets.symmetric(
                              vertical: 6,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(10),
                            ),
                            child: ListTile(
                              leading: const CircleAvatar(
                                backgroundColor: Colors.amber,
                                child: Icon(
                                  Icons.speed,
                                  color: Colors.white,
                                ),
                              ),
                              title: Text(
                                prof['name'] ?? 'Unknown',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              subtitle: Text(
                                'Speed: '
                                '${rate.isEmpty ? 'Unlimited' : rate}'
                                '\nTime Limit: '
                                '${prof['session-timeout'] ?? '-'}'
                                ' | Shared: '
                                '${prof['shared-users'] ?? '1'} User',
                              ),
                              trailing: IconButton(
                                icon: const Icon(
                                  Icons.edit,
                                  color: Colors.deepPurple,
                                ),
                                tooltip: 'Edit Profil Ini',
                                onPressed: _isLoading
                                    ? null
                                    : () =>
                                        _openEditDialog(prof),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
          ],
        ),
      ),
    );
  }
}
