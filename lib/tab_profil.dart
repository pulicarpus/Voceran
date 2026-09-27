import 'package:flutter/material.dart';
import 'mikrotik_api.dart';

class TabProfil extends StatefulWidget {
  const TabProfil({super.key});

  @override
  State<TabProfil> createState() => _TabProfilState();
}

class _TabProfilState extends State<TabProfil> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _rateController = TextEditingController(text: '1M/1M');
  final TextEditingController _validityController = TextEditingController(text: '1d');
  final TextEditingController _sharedController = TextEditingController(text: '1');
  final TextEditingController _priceController = TextEditingController(text: '0');
  final TextEditingController _sellingPriceController = TextEditingController(text: '0');

  List<Map<String, String>> _listProfil = [];
  List<String> _addressPools = ['none'];
  List<String> _parentQueues = ['none'];
  bool _isLoading = false;
  bool _isLoadingProfiles = false;

  String _expiryMode = 'rem';
  String _lockUser = 'Disable';
  String _addressPool = 'none';
  String _parentQueue = 'none';

  static const _expiryModes = <String, String>{
    '0': 'None',
    'rem': 'Remove',
    'ntf': 'Notice',
    'remc': 'Remove & Record',
    'ntfc': 'Notice & Record',
  };

  @override
  void initState() {
    super.initState();
    _loadDataProfil();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _rateController.dispose();
    _validityController.dispose();
    _sharedController.dispose();
    _priceController.dispose();
    _sellingPriceController.dispose();
    super.dispose();
  }

  Future<void> _loadDataProfil() async {
    if (_isLoadingProfiles) return;
    if (mounted) setState(() => _isLoadingProfiles = true);

    try {
      final response = await MikrotikAPI.run([
        ['/ip/hotspot/user/profile/print'],
      ]);
      if (!mounted) return;

      if (_isErrorResponse(response)) {
        setState(() => _isLoadingProfiles = false);
        _showSnackBar(
          'Gagal memuat profil: ${_extractRouterMessage(response)}',
          Colors.redAccent,
        );
        return;
      }

      final profiles = _parseProfileResponse(response);
      setState(() {
        _listProfil = profiles;
        _isLoadingProfiles = false;
      });

      await _loadRouterChoices();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingProfiles = false);
      _showSnackBar('Gagal memuat profil: $e', Colors.redAccent);
    }
  }

  Future<void> _loadRouterChoices() async {
    try {
      final poolResponse = await MikrotikAPI.run([
        ['/ip/pool/print'],
      ]);
      final queueResponse = await MikrotikAPI.run([
        ['/queue/simple/print', '?dynamic=false'],
      ]);
      if (!mounted) return;

      final pools = <String>['none'];
      for (final line in poolResponse) {
        if (line.startsWith('=name=')) {
          final name = line.substring(6).trim();
          if (name.isNotEmpty && !pools.contains(name)) pools.add(name);
        }
      }

      final queues = <String>['none'];
      for (final line in queueResponse) {
        if (line.startsWith('=name=')) {
          final name = line.substring(6).trim();
          if (name.isNotEmpty && !queues.contains(name)) queues.add(name);
        }
      }

      setState(() {
        _addressPools = pools;
        _parentQueues = queues;
        if (!_addressPools.contains(_addressPool)) _addressPool = 'none';
        if (!_parentQueues.contains(_parentQueue)) _parentQueue = 'none';
      });
    } catch (_) {
      // Address pool and parent queue are optional; keep the form usable.
    }
  }

  List<Map<String, String>> _parseProfileResponse(List<String> response) {
    final profiles = <Map<String, String>>[];
    Map<String, String>? current;

    void finishCurrent() {
      if (current == null || current!.isEmpty) return;
      final name = current!['name'];
      if (name != null && name.trim().isNotEmpty) {
        final p = Map<String, String>.from(current!);
        p.addAll(_parseMikhmonMetadata(p['on-login'] ?? ''));
        profiles.add(p);
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
      } else if (line.startsWith('=name=')) {
        current ??= <String, String>{};
        current!['name'] = line.substring(6);
      } else if (line.startsWith('=rate-limit=')) {
        current ??= <String, String>{};
        current!['rate-limit'] = line.substring(12);
      } else if (line.startsWith('=session-timeout=')) {
        current ??= <String, String>{};
        current!['session-timeout'] = line.substring(17);
      } else if (line.startsWith('=shared-users=')) {
        current ??= <String, String>{};
        current!['shared-users'] = line.substring(14);
      } else if (line.startsWith('=address-pool=')) {
        current ??= <String, String>{};
        current!['address-pool'] = line.substring(14);
      } else if (line.startsWith('=parent-queue=')) {
        current ??= <String, String>{};
        current!['parent-queue'] = line.substring(14);
      } else if (line.startsWith('=on-login=')) {
        current ??= <String, String>{};
        current!['on-login'] = line.substring(10);
      }
    }

    finishCurrent();
    return profiles;
  }

  Map<String, String> _parseMikhmonMetadata(String script) {
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
      out['owner'] = script.contains('# VOCERAN_MIKHMON_COMPAT') ? 'voceran' : 'mikhmon';
    }
    return out;
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
    for (final line in response) {
      if (line.startsWith('=category=')) {
        return 'RouterOS category: ${line.substring(10)}';
      }
    }
    return 'RouterOS tidak memberikan detail error.';
  }

  bool _isRealMikhmonProfile(Map<String, String> profile) {
    return profile['owner'] == 'mikhmon';
  }

  String _modeLabel(String mode) => _expiryModes[mode] ?? (mode.isEmpty ? '-' : mode);

  String _quoteSafe(String value) {
    return value.replaceAll('\\', '\\\\').replaceAll('"', '\\"');
  }

  String _buildMikhmonOnLoginScript({
    required String expiryMode,
    required String validity,
    required String price,
    required String sellingPrice,
    required String lockUser,
  }) {
    final safeValidity = validity.trim().isEmpty ? '1d' : validity.trim();
    final safePrice = price.trim().isEmpty ? '0' : price.trim();
    final safeSelling = sellingPrice.trim().isEmpty ? '0' : sellingPrice.trim();
    final safeLock = lockUser == 'Enable' ? 'Enable' : 'Disable';

    final lock = safeLock == 'Enable'
        ? r'; [:local mac $"mac-address"; /ip hotspot user set mac-address=$mac [find where name=$user]]'
        : '';

    final record = expiryMode == 'remc' || expiryMode == 'ntfc'
        ? '; :local mac \$"mac-address"; :local time [/system clock get time ]; /system script add name="\$date-|\$time-|\$user-|-${safePrice}-|-\$address-|-\$mac-|-${safeValidity}-|-\$comment" owner="\$month\$year" source="\$date" comment="mikhmon"'
        : '';

    if (expiryMode == '0') {
      return '# VOCERAN_MIKHMON_COMPAT\n'
          ':put (",,'
          '$safePrice'
          ',,,'
          'noexp,'
          '$safeLock'
          ',")'
          '$lock';
    }

    final base = ':put (",$expiryMode,$safePrice,$safeValidity,$safeSelling,,$safeLock,"); {'
        ':local comment [ /ip hotspot user get [/ip hotspot user find where name="\$user"] comment]; '
        ':local ucode [:pic \$comment 0 2]; '
        ':if (\$ucode = "vc" or \$ucode = "up" or \$comment = "") do={ '
        ':local date [ /system clock get date ]; '
        ':local year [ :pick \$date 7 11 ]; '
        ':local month [ :pick \$date 0 3 ]; '
        '/sys sch add name="\$user" disable=no start-date=\$date interval="$safeValidity"; '
        ':delay 5s; '
        ':local exp [ /sys sch get [ /sys sch find where name="\$user" ] next-run]; '
        ':local getxp [len \$exp]; '
        ':if (\$getxp = 15) do={ '
        ':local d [:pic \$exp 0 6]; '
        ':local t [:pic \$exp 7 16]; '
        ':local s ("/"); '
        ':local exp ("\$d\$s\$year \$t"); '
        '/ip hotspot user set comment="\$exp" [find where name="\$user"];}; '
        ':if (\$getxp = 8) do={ /ip hotspot user set comment="\$date \$exp" [find where name="\$user"];}; '
        ':if (\$getxp > 15) do={ /ip hotspot user set comment="\$exp" [find where name="\$user"];}; '
        ':delay 5s; /sys sch remove [find where name="\$user"]';

    return '# VOCERAN_MIKHMON_COMPAT\n$base$record$lock}}';
  }

  String _buildExpiryMonitorScript(String profileName, String mode) {
    final safeName = _quoteSafe(profileName);
    final action = (mode == 'ntf' || mode == 'ntfc')
        ? 'set limit-uptime=1s'
        : 'remove';
    return ':local dateint do={:local montharray ( "jan","feb","mar","apr","may","jun","jul","aug","sep","oct","nov","dec" );'
        ':local days [ :pick \$d 4 6 ]; :local month [ :pick \$d 0 3 ]; :local year [ :pick \$d 7 11 ]; '
        ':local monthint ([ :find \$montharray \$month]); :local month (\$monthint + 1); '
        ':if ( [len \$month] = 1) do={:local zero ("0"); :return [:tonum ("\$year\$zero\$month\$days")];} else={:return [:tonum ("\$year\$month\$days")];}}; '
        ':local timeint do={ :local hours [ :pick \$t 0 2 ]; :local minutes [ :pick \$t 3 5 ]; :return (\$hours * 60 + \$minutes) ; }; '
        ':local date [ /system clock get date ]; :local time [ /system clock get time ]; '
        ':local today [\$dateint d=\$date] ; :local curtime [\$timeint t=\$time] ; '
        ':foreach i in [ /ip hotspot user find where profile="$safeName" ] do={ '
        ':local comment [ /ip hotspot user get \$i comment]; :local uname [ /ip hotspot user get \$i name]; '
        ':if ([:len \$comment] >= 20 and [:pic \$comment 3] = "/" and [:pic \$comment 6] = "/") do={ '
        ':local gettime [:pic \$comment 12 20]; :local expd [\$dateint d=\$comment] ; :local expt [\$timeint t=\$gettime] ; '
        ':if ((\$expd < \$today and \$expt < \$curtime) or (\$expd < \$today and \$expt > \$curtime) or (\$expd = \$today and \$expt < \$curtime)) do={ '
        '[ /ip hotspot user $action \$i ]; [ /ip hotspot active remove [find where user=\$uname] ]; }} }';
  }

  Future<bool> _syncExpiryMonitor(String profileName, String mode) async {
    final schedulerResponse = await MikrotikAPI.run([
      ['/system/scheduler/print'],
    ]);
    if (_isErrorResponse(schedulerResponse)) {
      _showSnackBar(
        'Gagal membaca scheduler: ${_extractRouterMessage(schedulerResponse)}',
        Colors.redAccent,
      );
      return false;
    }

    final safeProfile = profileName.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final schedulerName = 'VOCERAN-MON-$safeProfile';
    String? schedulerId;
    String? currentId;
    String? currentName;
    String? currentComment;

    void inspect() {
      if (currentComment == 'VocerAN Monitor Profile $profileName' || currentName == schedulerName) {
        schedulerId = currentId;
      }
      currentId = null;
      currentName = null;
      currentComment = null;
    }

    for (final line in schedulerResponse) {
      if (line == '!re') {
        inspect();
      } else if (line == '!done') {
        inspect();
      } else if (line.startsWith('=.id=')) {
        currentId = line.substring(5);
      } else if (line.startsWith('=name=')) {
        currentName = line.substring(6);
      } else if (line.startsWith('=comment=')) {
        currentComment = line.substring(9);
      }
    }

    if (mode == '0') {
      if (schedulerId != null) {
        final remove = await MikrotikAPI.run([
          ['/system/scheduler/remove', '=.id=$schedulerId'],
        ]);
        if (_isErrorResponse(remove)) {
          _showSnackBar(
            'Gagal menghapus monitor expiry: ${_extractRouterMessage(remove)}',
            Colors.redAccent,
          );
          return false;
        }
      }
      return true;
    }

    final source = _buildExpiryMonitorScript(profileName, mode);
    final command = schedulerId == null
        ? [
            '/system/scheduler/add',
            '=name=$schedulerName',
            '=interval=2m',
            '=on-event=$source',
            '=comment=VocerAN Monitor Profile $profileName',
            '=disabled=no',
          ]
        : [
            '/system/scheduler/set',
            '=.id=$schedulerId',
            '=name=$schedulerName',
            '=interval=2m',
            '=on-event=$source',
            '=comment=VocerAN Monitor Profile $profileName',
            '=disabled=no',
          ];

    final result = await MikrotikAPI.run([command]);
    if (_isErrorResponse(result)) {
      _showSnackBar(
        'Gagal memasang monitor expiry: ${_extractRouterMessage(result)}',
        Colors.redAccent,
      );
      return false;
    }
    return true;
  }

  Future<void> _tambahProfil() async {
    final name = _nameController.text.trim().replaceAll(RegExp(r'\s+'), '-');
    final rate = _rateController.text.trim();
    final validity = _validityController.text.trim();
    final shared = int.tryParse(_sharedController.text.trim());
    final price = _priceController.text.trim().isEmpty ? '0' : _priceController.text.trim();
    final selling = _sellingPriceController.text.trim().isEmpty ? '0' : _sellingPriceController.text.trim();

    if (name.isEmpty) {
      _showSnackBar('Nama paket tidak boleh kosong.', Colors.orange);
      return;
    }
    if (shared == null || shared < 1) {
      _showSnackBar('Shared Users harus berupa angka minimal 1.', Colors.orange);
      return;
    }
    if (_expiryMode != '0' && validity.isEmpty) {
      _showSnackBar('Validity wajib diisi jika expiry aktif. Contoh: 1d, 12h, 30m.', Colors.orange);
      return;
    }
    if (_isLoading) return;

    setState(() => _isLoading = true);
    try {
      final existing = await MikrotikAPI.run([
        ['/ip/hotspot/user/profile/print'],
      ]);
      if (_isErrorResponse(existing)) {
        _showSnackBar('Gagal memeriksa profile: ${_extractRouterMessage(existing)}', Colors.redAccent);
        return;
      }
      if (existing.any((line) => line == '=name=$name')) {
        _showSnackBar('Profile "$name" sudah ada. Tidak ditimpa agar profile Mikhmon aman.', Colors.orange);
        return;
      }

      final onLogin = _buildMikhmonOnLoginScript(
        expiryMode: _expiryMode,
        validity: validity,
        price: price,
        sellingPrice: selling,
        lockUser: _lockUser,
      );

      final command = <String>[
        '/ip/hotspot/user/profile/add',
        '=name=$name',
        '=rate-limit=$rate',
        '=shared-users=$shared',
        '=status-autorefresh=1m',
        '=on-login=$onLogin',
      ];
      if (_addressPool != 'none') command.add('=address-pool=$_addressPool');
      if (_parentQueue != 'none') command.add('=parent-queue=$_parentQueue');

      final response = await MikrotikAPI.run([command]);
      if (_isErrorResponse(response)) {
        _showSnackBar('Gagal menyimpan paket: ${_extractRouterMessage(response)}', Colors.redAccent);
        return;
      }

      if (_expiryMode != '0') {
        final monitorOk = await _syncExpiryMonitor(name, _expiryMode);
        if (!monitorOk) return;
      }

      _nameController.clear();
      _showSnackBar(
        'Paket $name berhasil dibuat. Validity ${validity.isEmpty ? 'tanpa expiry' : validity}, mode ${_modeLabel(_expiryMode)}.',
        Colors.green,
      );
      await _loadDataProfil();
    } catch (e) {
      if (mounted) _showSnackBar('Terjadi kesalahan: $e', Colors.redAccent);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _updateProfil(
    String id,
    String name,
    String rateLimit,
    String validity,
    String sharedUsers,
    String mode,
    String price,
    String sellingPrice,
    String lockUser,
  ) async {
    if (id.trim().isEmpty) {
      _showSnackBar('ID profil tidak ditemukan.', Colors.redAccent);
      return;
    }

    Map<String, String>? profile;
    for (final item in _listProfil) {
      if (item['id'] == id) {
        profile = item;
        break;
      }
    }
    if (profile != null && _isRealMikhmonProfile(profile)) {
      _showSnackBar(
        'Profile Mikhmon tidak diedit dari Voceran agar script expiry dan voucher lama tetap aman.',
        Colors.orange,
      );
      return;
    }

    final parsedShared = int.tryParse(sharedUsers);
    if (parsedShared == null || parsedShared < 1) {
      _showSnackBar('Shared Users harus berupa angka minimal 1.', Colors.orange);
      return;
    }
    if (mode != '0' && validity.trim().isEmpty) {
      _showSnackBar('Validity wajib diisi jika expiry aktif.', Colors.orange);
      return;
    }
    if (_isLoading) return;

    setState(() => _isLoading = true);
    try {
      final onLogin = _buildMikhmonOnLoginScript(
        expiryMode: mode,
        validity: validity,
        price: price,
        sellingPrice: sellingPrice,
        lockUser: lockUser,
      );
      final response = await MikrotikAPI.run([
        [
          '/ip/hotspot/user/profile/set',
          '=.id=$id',
          '=rate-limit=$rateLimit',
          '=shared-users=$parsedShared',
          '=on-login=$onLogin',
        ],
      ]);

      if (_isErrorResponse(response)) {
        _showSnackBar(
          'Gagal memperbarui profil $name: ${_extractRouterMessage(response)}',
          Colors.redAccent,
        );
      } else {
        final monitorOk = await _syncExpiryMonitor(name, mode);
        if (monitorOk) {
          _showSnackBar('Paket $name berhasil diperbarui.', Colors.green);
        }
      }
    } catch (e) {
      if (mounted) _showSnackBar('Terjadi kesalahan: $e', Colors.redAccent);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
    await _loadDataProfil();
  }

  Future<void> _openEditDialog(Map<String, String> profil) async {
    if (_isRealMikhmonProfile(profil)) return;

    final rateEdit = TextEditingController(text: profil['rate-limit'] ?? '');
    final validityEdit = TextEditingController(text: profil['validity'] ?? '1d');
    final sharedEdit = TextEditingController(text: profil['shared-users'] ?? '1');
    final priceEdit = TextEditingController(text: profil['price'] ?? '0');
    final sellingEdit = TextEditingController(text: profil['selling-price'] ?? '0');
    var mode = profil['expiry-mode'] ?? 'rem';
    var lock = profil['lock-user'] ?? 'Disable';

    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                title: Text('Edit Paket: ${profil['name'] ?? '-'}'),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: rateEdit,
                        decoration: const InputDecoration(
                          labelText: 'Rate Limit (up/down)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        value: _expiryModes.containsKey(mode) ? mode : 'rem',
                        decoration: const InputDecoration(
                          labelText: 'Mode Expired',
                          border: OutlineInputBorder(),
                        ),
                        items: _expiryModes.entries
                            .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                            .toList(),
                        onChanged: (v) => setDialogState(() => mode = v ?? mode),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: validityEdit,
                        decoration: const InputDecoration(
                          labelText: 'Validity (Contoh: 1d)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: sharedEdit,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Shared Users',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: priceEdit,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Harga',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: sellingEdit,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Harga Jual',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        value: lock,
                        decoration: const InputDecoration(
                          labelText: 'Kunci Pengguna',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'Disable', child: Text('Disable')),
                          DropdownMenuItem(value: 'Enable', child: Text('Enable')),
                        ],
                        onChanged: (v) => setDialogState(() => lock = v ?? lock),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: const Text('Batal'),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.pop(dialogContext);
                      _updateProfil(
                        profil['id'] ?? '',
                        profil['name'] ?? '',
                        rateEdit.text.trim(),
                        validityEdit.text.trim(),
                        sharedEdit.text.trim(),
                        mode,
                        priceEdit.text.trim(),
                        sellingEdit.text.trim(),
                        lock,
                      );
                    },
                    child: const Text('Simpan'),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      rateEdit.dispose();
      validityEdit.dispose();
      sharedEdit.dispose();
      priceEdit.dispose();
      sellingEdit.dispose();
    }
  }

  void _showSnackBar(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontWeight: FontWeight.bold)),
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: ExpansionTile(
                initiallyExpanded: _listProfil.isEmpty,
                title: const Text(
                  'Buat Paket Voucher Baru',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.deepPurple),
                ),
                leading: const Icon(Icons.add_box, color: Colors.deepPurple),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        TextField(
                          controller: _nameController,
                          decoration: const InputDecoration(
                            labelText: 'Nama Paket',
                            hintText: 'Contoh: 1-Jam',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _rateController,
                          decoration: const InputDecoration(
                            labelText: 'Rate Limit (Contoh: 10M/10M)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _validityController,
                          decoration: const InputDecoration(
                            labelText: 'Validity / Masa Berlaku',
                            hintText: 'Contoh: 1d, 3d, 12h, 30m',
                            helperText: 'Dihitung sejak login pertama. Time Limit diatur saat membuat voucher.',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _sharedController,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'Shared Users',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                value: _expiryMode,
                                decoration: const InputDecoration(
                                  labelText: 'Mode Expired',
                                  border: OutlineInputBorder(),
                                ),
                                items: _expiryModes.entries
                                    .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                                    .toList(),
                                onChanged: (v) => setState(() => _expiryMode = v ?? _expiryMode),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _priceController,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'Harga',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextField(
                                controller: _sellingPriceController,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'Harga Jual',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                value: _lockUser,
                                decoration: const InputDecoration(
                                  labelText: 'Kunci Pengguna',
                                  border: OutlineInputBorder(),
                                ),
                                items: const [
                                  DropdownMenuItem(value: 'Disable', child: Text('Disable')),
                                  DropdownMenuItem(value: 'Enable', child: Text('Enable')),
                                ],
                                onChanged: (v) => setState(() => _lockUser = v ?? _lockUser),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                value: _addressPools.contains(_addressPool) ? _addressPool : 'none',
                                decoration: const InputDecoration(
                                  labelText: 'Address Pool',
                                  border: OutlineInputBorder(),
                                ),
                                items: _addressPools.map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
                                onChanged: (v) => setState(() => _addressPool = v ?? 'none'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        DropdownButtonFormField<String>(
                          value: _parentQueues.contains(_parentQueue) ? _parentQueue : 'none',
                          decoration: const InputDecoration(
                            labelText: 'Parent Queue',
                            border: OutlineInputBorder(),
                          ),
                          items: _parentQueues.map((q) => DropdownMenuItem(value: q, child: Text(q))).toList(),
                          onChanged: (v) => setState(() => _parentQueue = v ?? 'none'),
                        ),
                        const SizedBox(height: 8),
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Mode expired, validity, harga, harga jual, lock user, address pool dan parent queue mengikuti konsep profile Mikhmon. Voceran hanya menerapkan script pada paket baru miliknya.',
                            style: TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                        ),
                        const SizedBox(height: 18),
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: _isLoading
                              ? const Center(child: CircularProgressIndicator())
                              : ElevatedButton.icon(
                                  icon: const Icon(Icons.save),
                                  label: const Text('Simpan Paket ke Router'),
                                  onPressed: _tambahProfil,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.deepPurple,
                                    foregroundColor: Colors.white,
                                  ),
                                ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Profile Mikhmon yang terdeteksi diberi label READ-ONLY dan tidak akan diubah oleh Voceran.',
              style: TextStyle(fontSize: 12, color: Colors.orange),
            ),
            const SizedBox(height: 8),
            const Text(
              'Daftar Paket / Profil Terpasang',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            _listProfil.isEmpty && _isLoadingProfiles
                ? const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))
                : _listProfil.isEmpty
                    ? const Center(child: Padding(padding: EdgeInsets.all(20), child: Text('Tidak ada profil ditemukan')))
                    : Column(
                        children: _listProfil.map((prof) {
                          final rate = prof['rate-limit']?.trim() ?? '';
                          final isMikhmon = _isRealMikhmonProfile(prof);
                          final validity = prof['validity']?.trim() ?? '';
                          final mode = prof['expiry-mode'] ?? '';
                          final ownerText = isMikhmon ? 'Mikhmon: READ-ONLY' : (prof['mikhmon'] == 'yes' ? 'Voceran: Mikhmon-compatible' : '');
                          return Card(
                            elevation: 2,
                            margin: const EdgeInsets.symmetric(vertical: 6),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            child: ListTile(
                              leading: const CircleAvatar(
                                backgroundColor: Colors.amber,
                                child: Icon(Icons.speed, color: Colors.white),
                              ),
                              title: Text(
                                prof['name'] ?? 'Unknown',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                              subtitle: Text(
                                'Speed: ${rate.isEmpty ? 'Unlimited' : rate}'
                                '\nBerlaku: ${validity.isEmpty ? '-' : validity}'
                                ' | Mode: ${_modeLabel(mode)}'
                                ' | Shared: ${prof['shared-users'] ?? '1'}'
                                '${ownerText.isEmpty ? '' : '\n$ownerText'}',
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.edit, color: Colors.deepPurple),
                                tooltip: 'Edit Paket Ini',
                                onPressed: _isLoading || isMikhmon ? null : () => _openEditDialog(prof),
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
