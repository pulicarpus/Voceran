import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'mikrotik_api.dart';

class TabPengaturan extends StatefulWidget {
  const TabPengaturan({super.key});

  @override
  State<TabPengaturan> createState() => _TabPengaturanState();
}

class _TabPengaturanState extends State<TabPengaturan> {
  final TextEditingController _ipController = TextEditingController();
  final TextEditingController _userController = TextEditingController();
  final TextEditingController _passController = TextEditingController();

  bool _isLoadingStatus = false;
  bool _isConnected = false;
  String _statusMessage = 'Memeriksa Koneksi...';

  @override
  void initState() {
    super.initState();
    _loadSavedData();
  }

  @override
  void dispose() {
    _ipController.dispose();
    _userController.dispose();
    _passController.dispose();
    super.dispose();
  }

  Future<void> _loadSavedData() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final ip = prefs.getString('ip') ?? '10.10.10.1';
      final user = prefs.getString('user') ?? 'admin';
      final pass = prefs.getString('pass') ?? '';

      if (!mounted) return;

      setState(() {
        _ipController.text = ip;
        _userController.text = user;
        _passController.text = pass;
      });

      await _checkMikrotikConnection();
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isConnected = false;
        _isLoadingStatus = false;
        _statusMessage = 'Gagal membaca pengaturan';
      });
    }
  }

  Future<void> _checkMikrotikConnection() async {
    if (!mounted || _isLoadingStatus) return;

    final ip = _ipController.text.trim();
    final user = _userController.text.trim();

    if (ip.isEmpty || user.isEmpty) {
      setState(() {
        _isConnected = false;
        _isLoadingStatus = false;
        _statusMessage = 'IP dan Username wajib diisi';
      });
      return;
    }

    setState(() {
      _isLoadingStatus = true;
      _statusMessage = 'Sedang menghubungkan...';
    });

    try {
      final response = await MikrotikAPI.run([
        ['/system/identity/print'],
      ]);

      if (!mounted) return;

      if (_isErrorResponse(response)) {
        setState(() {
          _isConnected = false;
          _statusMessage =
              'Gagal: ${_extractRouterMessage(response)}';
        });
        return;
      }

      setState(() {
        _isConnected = true;
        _statusMessage = 'Terhubung ke MikroTik';
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isConnected = false;
        _statusMessage = 'Terputus / Jaringan Error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingStatus = false;
        });
      }
    }
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

    return 'Akses API ditolak';
  }

  Future<void> _save() async {
    final ip = _ipController.text.trim();
    final user = _userController.text.trim();
    final pass = _passController.text;

    if (ip.isEmpty) {
      _showSnackBar(
        'IP Address tidak boleh kosong.',
        Colors.orange,
      );
      return;
    }

    if (user.isEmpty) {
      _showSnackBar(
        'Username API tidak boleh kosong.',
        Colors.orange,
      );
      return;
    }

    try {
      final prefs = await SharedPreferences.getInstance();

      await prefs.setString('ip', ip);
      await prefs.setString('user', user);
      await prefs.setString('pass', pass);

      if (!mounted) return;

      _showSnackBar(
        'Koneksi Router Tersimpan!',
        Colors.green,
      );

      await _checkMikrotikConnection();
    } catch (e) {
      if (!mounted) return;

      _showSnackBar(
        'Gagal menyimpan pengaturan: $e',
        Colors.redAccent,
      );
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
          style: const TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: color,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final statusColor = _isLoadingStatus
        ? Colors.orange
        : _isConnected
            ? Colors.green
            : Colors.red;

    final statusTextColor = _isLoadingStatus
        ? Colors.orange.shade800
        : _isConnected
            ? Colors.green.shade800
            : Colors.red.shade800;

    final statusBackgroundColor = _isLoadingStatus
        ? Colors.orange.withOpacity(0.1)
        : _isConnected
            ? Colors.green.withOpacity(0.1)
            : Colors.red.withOpacity(0.1);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pengaturan Router'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Icon(
              Icons.router,
              size: 80,
              color: Colors.blueAccent,
            ),

            Container(
              margin: const EdgeInsets.only(
                top: 15,
                bottom: 25,
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                color: statusBackgroundColor,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: statusColor,
                  width: 1.5,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_isLoadingStatus)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.orange,
                      ),
                    )
                  else
                    Icon(
                      _isConnected
                          ? Icons.check_circle_rounded
                          : Icons.cancel_rounded,
                      color: _isConnected
                          ? Colors.green
                          : Colors.red,
                      size: 20,
                    ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      _statusMessage,
                      style: TextStyle(
                        color: statusTextColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            TextField(
              controller: _ipController,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'IP Address',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.dns),
              ),
            ),

            const SizedBox(height: 15),

            TextField(
              controller: _userController,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Username API',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person),
              ),
            ),

            const SizedBox(height: 15),

            TextField(
              controller: _passController,
              obscureText: true,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                labelText: 'Password API',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.lock),
              ),
            ),

            const SizedBox(height: 30),

            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.save),
                label: const Text('SIMPAN KONEKSI'),
                onPressed: _isLoadingStatus ? null : _save,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
