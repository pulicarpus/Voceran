import 'package:flutter/material.dart';
import 'mikrotik_api.dart';

class TabAktif extends StatefulWidget {
  const TabAktif({super.key});

  @override
  State<TabAktif> createState() => _TabAktifState();
}

class _TabAktifState extends State<TabAktif> {
  List<Map<String, String>> _listUserAktif = [];
  bool _isLoading = false;
  bool _showDetailList = false;

  @override
  void initState() {
    super.initState();
    _fetchUserAktif();
  }

  Future<void> _fetchUserAktif() async {
    if (_isLoading) return;

    if (mounted) {
      setState(() => _isLoading = true);
    }

    try {
      final response = await MikrotikAPI.run([
        ['/ip/hotspot/active/print'],
      ]);

      if (!mounted) return;

      if (_isErrorResponse(response)) {
        final message = _extractRouterMessage(response);

        setState(() => _isLoading = false);

        _showSnackBar(
          'Gagal mengambil data: $message',
          Colors.redAccent,
        );
        return;
      }

      final users = _parseActiveUserResponse(response);

      setState(() {
        _listUserAktif = users;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() => _isLoading = false);

      _showSnackBar(
        'Gagal mengambil data: $e',
        Colors.redAccent,
      );
    }
  }

  List<Map<String, String>> _parseActiveUserResponse(
    List<String> response,
  ) {
    final users = <Map<String, String>>[];
    Map<String, String>? current;

    void finishCurrent() {
      if (current == null || current!.isEmpty) return;

      final id = current!['id'];
      final user = current!['user'];

      if ((id != null && id.trim().isNotEmpty) ||
          (user != null && user.trim().isNotEmpty)) {
        users.add(Map<String, String>.from(current!));
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

      if (line.startsWith('=user=')) {
        current ??= <String, String>{};
        current!['user'] = line.substring(6);
        continue;
      }

      if (line.startsWith('=address=')) {
        current ??= <String, String>{};
        current!['address'] = line.substring(9);
        continue;
      }

      if (line.startsWith('=uptime=')) {
        current ??= <String, String>{};
        current!['uptime'] = line.substring(8);
        continue;
      }

      if (line.startsWith('=mac-address=')) {
        current ??= <String, String>{};
        current!['mac'] = line.substring(13);
        continue;
      }
    }

    finishCurrent();

    return users;
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

  Future<void> _kickUser(
    String id,
    String username,
  ) async {
    if (id.trim().isEmpty) {
      _showSnackBar(
        'ID sesi user tidak ditemukan.',
        Colors.redAccent,
      );
      return;
    }

    if (_isLoading) return;

    setState(() => _isLoading = true);

    try {
      final response = await MikrotikAPI.run([
        [
          '/ip/hotspot/active/remove',
          '=.id=$id',
        ],
      ]);

      if (!mounted) return;

      if (_isErrorResponse(response)) {
        _showSnackBar(
          'Gagal memutuskan koneksi $username: '
          '${_extractRouterMessage(response)}',
          Colors.redAccent,
        );
      } else {
        _showSnackBar(
          'User $username berhasil diputus.',
          Colors.green,
        );
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar(
          'Error: $e',
          Colors.redAccent,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }

    await _fetchUserAktif();
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
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _showDetailList
              ? 'Detail User Aktif'
              : 'Dashboard Aktif',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
        leading: _showDetailList
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: _isLoading
                    ? null
                    : () {
                        setState(() {
                          _showDetailList = false;
                        });
                      },
              )
            : null,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading
                ? null
                : _fetchUserAktif,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : _showDetailList
              ? _buildListView()
              : _buildGridView(),
    );
  }

  Widget _buildGridView() {
    return GridView.count(
      crossAxisCount: 2,
      padding: const EdgeInsets.all(16),
      mainAxisSpacing: 16,
      crossAxisSpacing: 16,
      children: [
        Card(
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          color: Colors.deepPurple,
          child: InkWell(
            borderRadius: BorderRadius.circular(15),
            onTap: () {
              if (!mounted) return;

              setState(() {
                _showDetailList = true;
              });
            },
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisAlignment:
                    MainAxisAlignment.center,
                crossAxisAlignment:
                    CrossAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.people,
                    size: 48,
                    color: Colors.white,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'USER AKTIF',
                    style: TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_listUserAktif.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 32,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Ketuk untuk Detail',
                    style: TextStyle(
                      color: Colors.white60,
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisAlignment:
                  MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.wifi,
                  size: 40,
                  color: _listUserAktif.isEmpty
                      ? Colors.grey
                      : Colors.green,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Status Hotspot',
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _listUserAktif.isEmpty
                      ? 'Sepi'
                      : 'Ramai Lancar',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildListView() {
    if (_listUserAktif.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment:
              MainAxisAlignment.center,
          children: [
            Icon(
              Icons.wifi_off,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 10),
            Text(
              'Tidak ada user aktif',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 15),
            ElevatedButton(
              onPressed: _isLoading
                  ? null
                  : () {
                      setState(() {
                        _showDetailList = false;
                      });
                    },
              child: const Text(
                'Kembali ke Dashboard',
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchUserAktif,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _listUserAktif.length,
        itemBuilder: (context, index) {
          final user = _listUserAktif[index];

          return Card(
            elevation: 3,
            margin: const EdgeInsets.symmetric(
              vertical: 6,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: ListTile(
              leading: const CircleAvatar(
                backgroundColor: Colors.deepPurple,
                child: Icon(
                  Icons.person,
                  color: Colors.white,
                ),
              ),
              title: Text(
                user['user'] ?? 'Unknown',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              subtitle: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  Text(
                    'IP: ${user['address'] ?? '-'}',
                  ),
                  Text(
                    'MAC: ${user['mac'] ?? '-'}',
                  ),
                  Text(
                    'Uptime: ${user['uptime'] ?? '-'}',
                    style: const TextStyle(
                      color: Colors.green,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              trailing: IconButton(
                icon: const Icon(
                  Icons.flash_off,
                  color: Colors.redAccent,
                  size: 28,
                ),
                tooltip: 'Putuskan Sesi',
                onPressed: _isLoading
                    ? null
                    : () {
                        _showKickDialog(
                          user['id'] ?? '',
                          user['user'] ?? '',
                        );
                      },
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _showKickDialog(
    String id,
    String username,
  ) async {
    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          title: const Row(
            children: [
              Icon(
                Icons.warning_amber_rounded,
                color: Colors.redAccent,
              ),
              SizedBox(width: 8),
              Text(
                'Putuskan Koneksi?',
                style: TextStyle(
                  color: Colors.redAccent,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: Text(
            "Apakah Bos yakin ingin men-kick "
            "user '$username' secara paksa dari jaringan?",
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  false,
                );
              },
              child: const Text(
                'Batal',
                style: TextStyle(
                  color: Colors.grey,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  true,
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                shape: RoundedRectangleBorder(
                  borderRadius:
                      BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'Ya, Kick!',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed == true && mounted) {
      await _kickUser(id, username);
    }
  }
}
