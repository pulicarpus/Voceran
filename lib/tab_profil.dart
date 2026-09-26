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
  final TextEditingController _validityController =
      TextEditingController(text: '1d');

  List<Map<String, String>> _listProfil = [];
  bool _isLoading = false;
  bool _isLoadingProfiles = false;

  static const String _expiryScriptName = 'voceran_v3_expiry_cleanup';
  static const String _expirySchedulerName = 'voceran_v3_expiry_scheduler';

  String _buildOnLoginScript(String validity) {
    // EXPNS stores the expiry moment as nanoseconds since RouterOS epoch.
    // The marker is written only on the first successful login.
    return ':local uid [/ip hotspot user find where name=\$user]; '
        ':if ([:len \$uid] = 0) do={ :return; }; '
        ':local c [/ip hotspot user get \$uid comment]; '
        ':local marker "EXPNS="; '
        ':local pos [:find \$c \$marker]; '
        ':if (\$pos = nil) do={ '
        ':local expiry ([:tonsec [:timestamp]] + [:tonsec $validity]); '
        '/ip hotspot user set \$uid comment=("Voucher|EXPNS=" . \$expiry); '
        ':log info ("VOCERAN V3 expiry set " . \$user); '
        '} else={ '
        ':local raw [:pick \$c (\$pos + 6) [:len \$c]]; '
        ':local expiry [:tonum \$raw]; '
        ':local now [:tonsec [:timestamp]]; '
        ':if (\$now >= \$expiry) do={ '
        '/ip hotspot active remove [find where user=\$user]; '
        '/ip hotspot user remove \$uid; '
        ':log warning ("VOCERAN V3 expired " . \$user); '
        '} '
        '}';
  }

  final String _onLogoutScript =
      ':local uid [/ip hotspot user find where name=\$user]; '
      ':if ([:len \$uid] = 0) do={ :return; }; '
      ':local utime [/ip hotspot user get \$uid uptime]; '
      ':local ltime [/ip hotspot user get \$uid limit-uptime]; '
      ':if (\$ltime != 0s && \$utime >= \$ltime) do={ '
      '/ip hotspot user remove \$uid; '
      ':log info ("VOCERAN V3 uptime exhausted " . \$user); '
      '}';

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
    super.dispose();
  }

  Future<void> _loadDataProfil() async {
    if (_isLoadingProfiles) return;

    if (mounted) {
      setState(() => _isLoadingProfiles = true);
    }

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
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingProfiles = false);
      _showSnackBar('Gagal memuat profil: $e', Colors.redAccent);
    }
  }

  List<Map<String, String>> _parseProfileResponse(List<String> response) {
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
      } else if (line.startsWith('=add-mac-cookie=')) {
        current ??= <String, String>{};
        current!['add-mac-cookie'] = line.substring(17);
      } else if (line.startsWith('=mac-cookie-timeout=')) {
        current ??= <String, String>{};
        current!['mac-cookie-timeout'] = line.substring(20);
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
      if (line.startsWith('=message=')) return line.substring(9);
    }
    for (final line in response) {
      if (line.startsWith('=category=')) {
        return 'RouterOS category: ${line.substring(10)}';
      }
    }
    return 'RouterOS tidak memberikan detail error.';
  }

  String _valueAfter(List<String> response, String prefix) {
    for (final line in response) {
      if (line.startsWith(prefix)) return line.substring(prefix.length);
    }
    return '';
  }

  Future<bool> _ensureMacCookieLogin() async {
    final response = await MikrotikAPI.run([
      ['/ip/hotspot/profile/print'],
    ]);

    if (_isErrorResponse(response)) {
      _showSnackBar(
        'Gagal membaca HotSpot Profile: '
        '${_extractRouterMessage(response)}',
        Colors.redAccent,
      );
      return false;
    }

    final profiles = <Map<String, String>>[];
    Map<String, String>? current;

    void finish() {
      if (current != null && current!.containsKey('id')) {
        profiles.add(Map<String, String>.from(current!));
      }
      current = null;
    }

    for (final line in response) {
      if (line == '!re') {
        finish();
        current = <String, String>{};
      } else if (line == '!done') {
        finish();
      } else if (line.startsWith('=.id=')) {
        current ??= <String, String>{};
        current!['id'] = line.substring(5);
      } else if (line.startsWith('=name=')) {
        current ??= <String, String>{};
        current!['name'] = line.substring(6);
      } else if (line.startsWith('=login-by=')) {
        current ??= <String, String>{};
        current!['login-by'] = line.substring(10);
      }
    }
    finish();

    for (final profile in profiles) {
      final id = profile['id'];
      if (id == null || id.isEmpty) continue;

      final existing = (profile['login-by'] ?? '').trim();
      final methods = existing
          .split(',')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();

      if (!methods.contains('mac-cookie')) {
        methods.add('mac-cookie');

        final update = await MikrotikAPI.run([
          [
            '/ip/hotspot/profile/set',
            '=.id=$id',
            '=login-by=${methods.join(',')}',
          ],
        ]);

        if (_isErrorResponse(update)) {
          _showSnackBar(
            'Gagal mengaktifkan mac-cookie pada '
            '${profile['name'] ?? 'HotSpot Profile'}: '
            '${_extractRouterMessage(update)}',
            Colors.redAccent,
          );
          return false;
        }
      }
    }

    return true;
  }

  Future<bool> _ensureExpiryScheduler() async {
    final scriptResponse = await MikrotikAPI.run([
      ['/system/script/print'],
    ]);

    if (_isErrorResponse(scriptResponse)) {
      _showSnackBar(
        'Gagal membaca System Script: '
        '${_extractRouterMessage(scriptResponse)}',
        Colors.redAccent,
      );
      return false;
    }

    String? scriptId;
    String? schedulerId;

    String? currentId;
    String? currentName;

    void inspectScriptRecord() {
      if (currentName == _expiryScriptName) scriptId = currentId;
      currentId = null;
      currentName = null;
    }

    for (final line in scriptResponse) {
      if (line == '!re') {
        inspectScriptRecord();
      } else if (line == '!done') {
        inspectScriptRecord();
      } else if (line.startsWith('=.id=')) {
        currentId = line.substring(5);
      } else if (line.startsWith('=name=')) {
        currentName = line.substring(6);
      }
    }

    final cleanupSource = r''':foreach uid in=[/ip hotspot user find] do={
  :local c [/ip hotspot user get $uid comment];
  :local marker "EXPNS=";
  :local pos [:find $c $marker];
  :if ($pos != nil) do={
    :local raw [:pick $c ($pos + 6) [:len $c]];
    :local expiry [:tonum $raw];
    :local now [:tonsec [:timestamp]];
    :if ($now >= $expiry) do={
      :local uname [/ip hotspot user get $uid name];
      /ip hotspot active remove [find where user=$uname];
      /ip hotspot user remove $uid;
      :log warning ("VOCERAN V3 expired " . $uname);
    }
  }
}
''';

    final List<String> scriptCommand;
    if (scriptId != null) {
      scriptCommand = [
        '/system/script/set',
        '=.id=$scriptId',
        '=source=$cleanupSource',
      ];
    } else {
      scriptCommand = [
        '/system/script/add',
        '=name=$_expiryScriptName',
        '=policy=read,write,policy,test',
        '=source=$cleanupSource',
      ];
    }

    final scriptUpdate = await MikrotikAPI.run([scriptCommand]);

    if (_isErrorResponse(scriptUpdate)) {
      _showSnackBar(
        'Gagal memasang script expiry: '
        '${_extractRouterMessage(scriptUpdate)}',
        Colors.redAccent,
      );
      return false;
    }

    final schedulerResponse = await MikrotikAPI.run([
      ['/system/scheduler/print'],
    ]);

    if (_isErrorResponse(schedulerResponse)) {
      _showSnackBar(
        'Gagal membaca Scheduler: '
        '${_extractRouterMessage(schedulerResponse)}',
        Colors.redAccent,
      );
      return false;
    }

    currentId = null;
    currentName = null;

    void inspectSchedulerRecord() {
      if (currentName == _expirySchedulerName) {
        schedulerId = currentId;
      }
      currentId = null;
      currentName = null;
    }

    for (final line in schedulerResponse) {
      if (line == '!re') {
        inspectSchedulerRecord();
      } else if (line == '!done') {
        inspectSchedulerRecord();
      } else if (line.startsWith('=.id=')) {
        currentId = line.substring(5);
      } else if (line.startsWith('=name=')) {
        currentName = line.substring(6);
      }
    }

    final schedulerCommand = schedulerId == null
        ? [
            '/system/scheduler/add',
            '=name=$_expirySchedulerName',
            '=interval=1m',
            '=on-event=$_expiryScriptName',
          ]
        : [
            '/system/scheduler/set',
            '=.id=$schedulerId',
            '=interval=1m',
            '=on-event=$_expiryScriptName',
          ];

    final schedulerUpdate = await MikrotikAPI.run([schedulerCommand]);

    if (_isErrorResponse(schedulerUpdate)) {
      _showSnackBar(
        'Gagal memasang scheduler expiry: '
        '${_extractRouterMessage(schedulerUpdate)}',
        Colors.redAccent,
      );
      return false;
    }

    return true;
  }

  Future<void> _prepareVoucherSystem(String validity) async {
    final macOk = await _ensureMacCookieLogin();
    if (!macOk) return;

    final schedulerOk = await _ensureExpiryScheduler();
    if (!schedulerOk) return;

    _showSnackBar(
      'Auto-login MAC + scheduler expiry siap.',
      Colors.green,
    );
  }

  Future<void> _tambahProfil() async {
    final name = _nameController.text.trim();
    final rate = _rateController.text.trim();
    final validity = _validityController.text.trim();

    if (name.isEmpty) {
      _showSnackBar(
        'Nama profil tidak boleh kosong, Bos!',
        Colors.orange,
      );
      return;
    }

    if (validity.isEmpty) {
      _showSnackBar(
        'Masa berlaku voucher tidak boleh kosong.',
        Colors.orange,
      );
      return;
    }

    if (_isLoading) return;
    setState(() => _isLoading = true);

    try {
      final prepared = await _ensureMacCookieLogin();
      if (!prepared) return;

      final schedulerReady = await _ensureExpiryScheduler();
      if (!schedulerReady) return;

      final response = await MikrotikAPI.run([
        [
          '/ip/hotspot/user/profile/add',
          '=name=$name',
          '=rate-limit=$rate',
          '=session-timeout=0s',
          '=shared-users=1',
          '=add-mac-cookie=yes',
          '=mac-cookie-timeout=$validity',
          '=on-login=${_buildOnLoginScript(validity)}',
          '=on-logout=$_onLogoutScript',
        ],
      ]);

      if (!mounted) return;

      if (_isErrorResponse(response)) {
        _showSnackBar(
          'Gagal menyimpan profil: ${_extractRouterMessage(response)}',
          Colors.redAccent,
        );
        return;
      }

      _nameController.clear();

      _showSnackBar(
        'Profil berhasil dibuat. Auto-login MAC aktif, '
        'masa berlaku $validity mulai saat login pertama.',
        Colors.green,
      );
    } catch (e) {
      if (mounted) {
        _showSnackBar('Terjadi kesalahan: $e', Colors.redAccent);
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
    String validity,
    String sharedUsers,
  ) async {
    if (id.trim().isEmpty) {
      _showSnackBar('ID profil tidak ditemukan.', Colors.redAccent);
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

    if (validity.trim().isEmpty) {
      _showSnackBar(
        'Masa berlaku tidak boleh kosong.',
        Colors.orange,
      );
      return;
    }

    if (_isLoading) return;
    setState(() => _isLoading = true);

    try {
      final prepared = await _ensureMacCookieLogin();
      if (!prepared) return;

      final schedulerReady = await _ensureExpiryScheduler();
      if (!schedulerReady) return;

      final response = await MikrotikAPI.run([
        [
          '/ip/hotspot/user/profile/set',
          '=.id=$id',
          '=rate-limit=$rateLimit',
          '=session-timeout=0s',
          '=shared-users=$parsedSharedUsers',
          '=add-mac-cookie=yes',
          '=mac-cookie-timeout=$validity',
          '=on-login=${_buildOnLoginScript(validity)}',
          '=on-logout=$_onLogoutScript',
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
          'Profil $name berhasil diperbarui. '
          'Auto-login MAC tetap aktif.',
          Colors.green,
        );
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('Terjadi kesalahan: $e', Colors.redAccent);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }

    await _loadDataProfil();
  }

  Future<void> _openEditDialog(Map<String, String> profil) async {
    final rateEditController =
        TextEditingController(text: profil['rate-limit'] ?? '');

    final validityEditController = TextEditingController(
      text: profil['mac-cookie-timeout'] ??
          profil['session-timeout'] ??
          '1d',
    );

    final sharedEditController =
        TextEditingController(text: profil['shared-users'] ?? '1');

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
                      labelText: 'Rate Limit (Contoh: 1M/1M)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: validityEditController,
                    decoration: const InputDecoration(
                      labelText: 'Masa Berlaku (Contoh: 1d)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: sharedEditController,
                    decoration: const InputDecoration(
                      labelText: 'Shared Users',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Masa berlaku dimulai saat login pertama. '
                    'Putus Wi-Fi tidak mengulang masa berlaku dan '
                    'tidak menghapus voucher.',
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
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Batal'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  _updateProfil(
                    profil['id'] ?? '',
                    profil['name'] ?? '',
                    rateEditController.text.trim(),
                    validityEditController.text.trim(),
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
      validityEditController.dispose();
      sharedEditController.dispose();
    }
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
                  'Buat Profil Voucher V3',
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
                            labelText: 'Rate Limit (Contoh: 1M/1M)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: _validityController,
                          decoration: const InputDecoration(
                            labelText: 'Masa Berlaku Voucher (Contoh: 1d)',
                            border: OutlineInputBorder(),
                            helperText:
                                'Mulai dihitung sejak login pertama.',
                          ),
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: _isLoading
                              ? const Center(
                                  child: CircularProgressIndicator(),
                                )
                              : ElevatedButton.icon(
                                  icon: const Icon(Icons.save),
                                  label: const Text('Simpan ke Router'),
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
            const SizedBox(height: 25),
            const Text(
              'Daftar Profil Terpasang',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            _listProfil.isEmpty && _isLoadingProfiles
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
                          child: Text('Tidak ada profil ditemukan'),
                        ),
                      )
                    : Column(
                        children: _listProfil.map((prof) {
                          final rate =
                              prof['rate-limit']?.trim() ?? '';
                          final validity =
                              prof['mac-cookie-timeout']?.trim() ??
                                  '1d';

                          return Card(
                            elevation: 2,
                            margin: const EdgeInsets.symmetric(
                              vertical: 6,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
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
                                '\nBerlaku: $validity'
                                ' | Shared: '
                                '${prof['shared-users'] ?? '1'}',
                              ),
                              trailing: IconButton(
                                icon: const Icon(
                                  Icons.edit,
                                  color: Colors.deepPurple,
                                ),
                                tooltip: 'Edit Profil Ini',
                                onPressed: _isLoading
                                    ? null
                                    : () => _openEditDialog(prof),
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
