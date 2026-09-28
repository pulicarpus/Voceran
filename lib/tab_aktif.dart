import 'dart:async';

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

  String _identity = '-';
  String _date = '-';
  String _time = '-';
  String _uptime = '-';
  String _model = '-';
  String _version = '-';
  String _cpuLoad = '-';
  String _freeMemory = '-';
  String _totalMemory = '-';
  String _freeHdd = '-';
  String _totalHdd = '-';
  String _trafficInterface = '-';
  double _txMbps = 0;
  double _rxMbps = 0;
  final List<double> _txHistory = [];
  final List<double> _rxHistory = [];
  Timer? _dashboardTimer;

  @override
  void initState() {
    super.initState();
    _fetchDashboard();
    _dashboardTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _refreshDashboardSilently(),
    );
  }

  @override
  void dispose() {
    _dashboardTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchDashboard() async {
    if (_isLoading) return;
    if (mounted) setState(() => _isLoading = true);

    try {
      await _loadSystemInfo();
      await _loadTraffic();
      await _fetchUserAktif();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _refreshDashboardSilently() async {
    if (!mounted || _isLoading || _showDetailList) return;
    try {
      await _loadSystemInfo();
      await _loadTraffic();
      await _fetchUserAktif(silent: true);
    } catch (_) {
      // Dashboard tetap menampilkan data terakhir jika polling gagal.
    }
  }

  Future<void> _loadSystemInfo() async {
    final response = await MikrotikAPI.run([
      ['/system/clock/print'],
      ['/system/resource/print'],
      ['/system/identity/print'],
      ['/system/routerboard/print'],
    ]);

    if (_isErrorResponse(response)) {
      throw Exception(_extractRouterMessage(response));
    }

    final records = _parseRecords(response);
    Map<String, String> clock = {};
    Map<String, String> resource = {};
    Map<String, String> identity = {};
    Map<String, String> routerboard = {};

    for (final record in records) {
      if (record.containsKey('time') || record.containsKey('date')) {
        clock = record;
      } else if (record.containsKey('uptime') ||
          record.containsKey('free-memory') ||
          record.containsKey('cpu-load')) {
        resource = record;
      } else if (record.containsKey('name')) {
        identity = record;
      } else if (record.containsKey('model') ||
          record.containsKey('routerboard')) {
        routerboard = record;
      }
    }

    if (!mounted) return;
    setState(() {
      _identity = identity['name'] ?? _identity;
      _date = clock['date'] ?? _date;
      _time = clock['time'] ?? _time;
      _uptime = resource['uptime'] ?? _uptime;
      _model = routerboard['model'] ?? resource['board-name'] ?? _model;
      _version = resource['version'] ?? _version;
      _cpuLoad = resource['cpu-load'] == null
          ? _cpuLoad
          : '${resource['cpu-load']}%';
      _freeMemory = _formatBytes(resource['free-memory']);
      _totalMemory = _formatBytes(resource['total-memory']);
      _freeHdd = _formatBytes(
        resource['free-hdd-space'] ?? resource['free-hdd-space'],
      );
      _totalHdd = _formatBytes(
        resource['total-hdd-space'] ?? resource['total-hdd-space'],
      );
    });
  }

  Future<void> _loadTraffic() async {
    final interfaceResponse = await MikrotikAPI.run([
      ['/interface/print'],
    ]);

    if (_isErrorResponse(interfaceResponse)) return;

    final interfaces = _parseRecords(interfaceResponse);
    if (interfaces.isEmpty) return;

    Map<String, String>? selected;
    for (final item in interfaces) {
      final name = item['name'] ?? '';
      final running = item['running'] == 'true';
      if (running && name.contains('ether1')) {
        selected = item;
        break;
      }
    }
    selected ??= interfaces.firstWhere(
      (item) => item['running'] == 'true',
      orElse: () => interfaces.first,
    );

    final name = selected['name'] ?? '';
    if (name.isEmpty) return;

    final trafficResponse = await MikrotikAPI.run([
      [
        '/interface/monitor-traffic',
        '=interface=$name',
        '=once=',
      ],
    ]);

    if (_isErrorResponse(trafficResponse)) return;

    final records = _parseRecords(trafficResponse);
    if (records.isEmpty) return;

    final traffic = records.first;
    final tx = _toMbps(traffic['tx-bits-per-second']);
    final rx = _toMbps(traffic['rx-bits-per-second']);

    if (!mounted) return;
    setState(() {
      _trafficInterface = name;
      _txMbps = tx;
      _rxMbps = rx;
      _txHistory.add(tx);
      _rxHistory.add(rx);
      if (_txHistory.length > 12) _txHistory.removeAt(0);
      if (_rxHistory.length > 12) _rxHistory.removeAt(0);
    });
  }

  Future<void> _fetchUserAktif({bool silent = false}) async {
    if (!silent && _isLoading) {
      // Called from the dashboard's initial loading sequence.
    }

    final response = await MikrotikAPI.run([
      ['/ip/hotspot/active/print'],
    ]);

    if (_isErrorResponse(response)) {
      if (!silent && mounted) {
        _showSnackBar(
          'Gagal mengambil data: ${_extractRouterMessage(response)}',
          Colors.redAccent,
        );
      }
      return;
    }

    final users = _parseActiveUserResponse(response);
    if (!mounted) return;
    setState(() => _listUserAktif = users);
  }

  List<Map<String, String>> _parseRecords(List<String> response) {
    final records = <Map<String, String>>[];
    Map<String, String>? current;

    void finish() {
      if (current != null && current!.isNotEmpty) {
        records.add(Map<String, String>.from(current!));
      }
      current = null;
    }

    for (final line in response) {
      if (line == '!re') {
        finish();
        current = <String, String>{};
        continue;
      }
      if (line == '!done') {
        finish();
        continue;
      }
      if (line == '!trap' || line == '!fatal') continue;

      if (line.startsWith('=')) {
        final separator = line.indexOf('=', 1);
        if (separator > 1) {
          current ??= <String, String>{};
          final key = line.substring(1, separator);
          current![key] = line.substring(separator + 1);
        }
      }
    }

    finish();
    return records;
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
      if (line == '!trap' || line == '!fatal') continue;

      if (line.startsWith('=.id=')) {
        current ??= <String, String>{};
        current!['id'] = line.substring(5);
      } else if (line.startsWith('=user=')) {
        current ??= <String, String>{};
        current!['user'] = line.substring(6);
      } else if (line.startsWith('=address=')) {
        current ??= <String, String>{};
        current!['address'] = line.substring(9);
      } else if (line.startsWith('=uptime=')) {
        current ??= <String, String>{};
        current!['uptime'] = line.substring(8);
      } else if (line.startsWith('=mac-address=')) {
        current ??= <String, String>{};
        current!['mac'] = line.substring(13);
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
      if (line.startsWith('=message=')) return line.substring(9);
    }
    return 'RouterOS tidak memberikan detail error.';
  }

  String _formatBytes(String? value) {
    final bytes = int.tryParse(value ?? '');
    if (bytes == null) return '-';
    if (bytes >= 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(0)} GiB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MiB';
  }

  double _toMbps(String? value) {
    final bits = double.tryParse(value ?? '') ?? 0;
    return bits / 1000000;
  }

  Future<void> _kickUser(String id, String username) async {
    if (id.trim().isEmpty) {
      _showSnackBar('ID sesi user tidak ditemukan.', Colors.redAccent);
      return;
    }

    if (_isLoading) return;
    setState(() => _isLoading = true);

    try {
      final response = await MikrotikAPI.run([
        ['/ip/hotspot/active/remove', '=.id=$id'],
      ]);

      if (!mounted) return;
      if (_isErrorResponse(response)) {
        _showSnackBar(
          'Gagal memutuskan koneksi $username: ${_extractRouterMessage(response)}',
          Colors.redAccent,
        );
      } else {
        _showSnackBar('User $username berhasil diputus.', Colors.green);
      }
    } catch (e) {
      if (mounted) _showSnackBar('Error: $e', Colors.redAccent);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }

    await _fetchUserAktif(silent: true);
  }

  void _showSnackBar(String message, Color color) {
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
          _showDetailList ? 'Detail User Aktif' : 'Dashboard Aktif',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        leading: _showDetailList
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: _isLoading
                    ? null
                    : () => setState(() => _showDetailList = false),
              )
            : null,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _fetchDashboard,
          ),
        ],
      ),
      body: _isLoading &&
              _identity == '-' &&
              _listUserAktif.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : _showDetailList
              ? _buildListView()
              : _buildDashboard(),
    );
  }

  Widget _buildDashboard() {
    return RefreshIndicator(
      onRefresh: _fetchDashboard,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          _buildSystemCard(),
          const SizedBox(height: 14),
          _buildHotspotSection(),
          const SizedBox(height: 14),
          _buildTrafficCard(),
        ],
      ),
    );
  }

  Widget _buildSystemCard() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _infoRow(Icons.calendar_month, 'Tanggal & Waktu Sistem', '$_date  $_time'),
            const SizedBox(height: 14),
            _infoRow(Icons.timer, 'Hidup', _uptime),
            const Divider(height: 26),
            _infoRow(Icons.info_outline, 'Nama Router', _identity),
            const SizedBox(height: 8),
            _infoRow(Icons.memory, 'Model', _model),
            const SizedBox(height: 8),
            _infoRow(Icons.system_update, 'RouterOS', _version),
            const Divider(height: 26),
            _infoRow(Icons.speed, 'Beban CPU', _cpuLoad),
            const SizedBox(height: 8),
            _infoRow(Icons.storage, 'Memori Bebas', _freeMemory),
            const SizedBox(height: 8),
            _infoRow(Icons.sd_storage, 'HDD Bebas', _freeHdd),
          ],
        ),
      ),
    );
  }

  Widget _buildHotspotSection() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(6, 4, 6, 12),
              child: Row(
                children: [
                  Icon(Icons.wifi),
                  SizedBox(width: 8),
                  Text(
                    'Hotspot Aktif',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: double.infinity,
              child: _dashboardTile(
                color: Colors.lightBlue,
                icon: Icons.laptop,
                value: '${_listUserAktif.length}',
                title: 'Pengguna Aktif',
                subtitle: 'Lihat pengguna Hotspot yang sedang terhubung',
                onTap: () => setState(() => _showDetailList = true),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dashboardTile({
    required Color color,
    required IconData icon,
    String? value,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: color,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: Colors.white, size: 32),
              const SizedBox(height: 8),
              if (value != null)
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTrafficCard() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 18),
        child: Column(
          children: [
            const Row(
              children: [
                Icon(Icons.show_chart),
                SizedBox(width: 8),
                Text(
                  'Lalu Lintas',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Antarmuka $_trafficInterface',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 180,
              child: CustomPaint(
                painter: _TrafficPainter(
                  tx: List<double>.from(_txHistory),
                  rx: List<double>.from(_rxHistory),
                ),
                child: const SizedBox.expand(),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _legend(Colors.blue, 'Tx ${_txMbps.toStringAsFixed(2)} Mbps'),
                const SizedBox(width: 24),
                _legend(Colors.redAccent, 'Rx ${_rxMbps.toStringAsFixed(2)} Mbps'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _legend(Color color, String text) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(text),
      ],
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 23, color: Colors.deepPurple),
        const SizedBox(width: 12),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: DefaultTextStyle.of(context).style,
              children: [
                TextSpan(
                  text: '$label: ',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                TextSpan(text: value),
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
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.wifi_off, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 10),
            Text(
              'Tidak ada user aktif',
              style: TextStyle(color: Colors.grey[600], fontSize: 16),
            ),
            const SizedBox(height: 15),
            ElevatedButton(
              onPressed: () => setState(() => _showDetailList = false),
              child: const Text('Kembali ke Dashboard'),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _fetchUserAktif(silent: true),
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _listUserAktif.length,
        itemBuilder: (context, index) {
          final user = _listUserAktif[index];
          return Card(
            elevation: 3,
            margin: const EdgeInsets.symmetric(vertical: 6),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ListTile(
              leading: const CircleAvatar(
                backgroundColor: Colors.deepPurple,
                child: Icon(Icons.person, color: Colors.white),
              ),
              title: Text(
                user['user'] ?? 'Unknown',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  Text('IP: ${user['address'] ?? '-'}'),
                  Text('MAC: ${user['mac'] ?? '-'}'),
                  Text(
                    'Uptime: ${user['uptime'] ?? '-'}',
                    style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              trailing: IconButton(
                icon: const Icon(Icons.flash_off, color: Colors.redAccent, size: 28),
                tooltip: 'Putuskan Sesi',
                onPressed: _isLoading
                    ? null
                    : () => _showKickDialog(user['id'] ?? '', user['user'] ?? ''),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _showKickDialog(String id, String username) async {
    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
              SizedBox(width: 8),
              Text(
                'Putuskan Koneksi?',
                style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: Text(
            "Apakah Bos yakin ingin men-kick user '$username' secara paksa dari jaringan?",
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Batal', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Ya, Kick!', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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

class _TrafficPainter extends CustomPainter {
  final List<double> tx;
  final List<double> rx;

  const _TrafficPainter({required this.tx, required this.rx});

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = Colors.grey.withOpacity(0.22)
      ..strokeWidth = 1;
    final txPaint = Paint()
      ..color = Colors.blue
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    final rxPaint = Paint()
      ..color = Colors.redAccent
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    for (var i = 1; i < 5; i++) {
      final y = size.height * i / 5;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    for (var i = 1; i < 6; i++) {
      final x = size.width * i / 6;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }

    final maxValue = [...tx, ...rx].fold<double>(1, (max, v) => v > max ? v : max);

    Path buildPath(List<double> values) {
      final path = Path();
      if (values.isEmpty) return path;
      for (var i = 0; i < values.length; i++) {
        final x = values.length == 1
            ? size.width
            : i * size.width / (values.length - 1);
        final y = size.height - (values[i] / maxValue) * (size.height - 8) - 4;
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      return path;
    }

    canvas.drawPath(buildPath(tx), txPaint);
    canvas.drawPath(buildPath(rx), rxPaint);
  }

  @override
  bool shouldRepaint(covariant _TrafficPainter oldDelegate) {
    return oldDelegate.tx != tx || oldDelegate.rx != rx;
  }
}
