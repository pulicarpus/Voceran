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
  final TextEditingController _timeController = TextEditingController(text: '1d');

  List<Map<String, String>> _listProfil = [];
  bool _isLoading = false;

  // Script sakti anti-jebol (Menggunakan >= agar pembulatan detik Mikrotik tetap terhapus otomatis)
  final String _scriptPembersihOtomatis = 
      r':local uuser $user; :local utime [/ip hotspot user get [find name=$uuser] uptime]; '
      r':local ltime [/ip hotspot user get [find name=$uuser] limit-uptime]; '
      r':if ($utime >= $ltime) do={ /ip hotspot user remove [find name=$uuser]; }';

  @override
  void initState() {
    super.initState();
    _loadDataProfil(); // Ambil list data profil saat halaman pertama dibuka
  }

  // 1. FUNGSI AMBIL DAFTAR PROFIL DARI MIKROTIK
  Future<void> _loadDataProfil() async {
    setState(() => _isLoading = true);
    try {
      var res = await MikrotikAPI.run([['/ip/hotspot/user/profile/print']]);
      List<Map<String, String>> tempProfil = [];
      Map<String, String> currentProfil = {};

      for (var line in res) {
        if (line.startsWith('=.id=')) {
          if (currentProfil.isNotEmpty) {
            tempProfil.add(currentProfil);
            currentProfil = {};
          }
          currentProfil['id'] = line.substring(5);
        } else if (line.startsWith('=name=')) {
          currentProfil['name'] = line.substring(6);
        } else if (line.startsWith('=rate-limit=')) {
          currentProfil['rate-limit'] = line.substring(12);
        } else if (line.startsWith('=session-timeout=')) {
          currentProfil['session-timeout'] = line.substring(17);
        } else if (line.startsWith('=shared-users=')) {
          currentProfil['shared-users'] = line.substring(14);
        }
      }
      if (currentProfil.isNotEmpty) {
        tempProfil.add(currentProfil);
      }

      setState(() {
        _listProfil = tempProfil;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      _showSnackBar("Gagal memuat profil: $e", Colors.redAccent);
    }
  }

  // 2. FUNGSI BUAT PROFIL BARU + INJECT AUTO CLEAN
  void _tambahProfil() async {
    if (_nameController.text.trim().isEmpty) {
      _showSnackBar("Nama profil tidak boleh kosong, Bos!", Colors.orange);
      return;
    }

    setState(() => _isLoading = true);
    
    List<List<String>> command = [[
      '/ip/hotspot/user/profile/add',
      '=name=${_nameController.text.trim()}',
      '=rate-limit=${_rateController.text.trim()}',
      '=session-timeout=${_timeController.text.trim()}',
      '=shared-users=1', // Secara default kita set 1 user per voucher
      '=on-logout=$_scriptPembersihOtomatis' // Menyuntikkan script anti-jebol baru
    ]];

    var response = await MikrotikAPI.run(command);
    setState(() => _isLoading = false);

    if (response.contains("ERROR") || response.contains("!trap")) {
      _showSnackBar("Gagal Simpan! Cek koneksi atau nama profil ganda", Colors.redAccent);
    } else {
      _showSnackBar("Profil Berhasil Dibuat + Auto-Clean Aktif!", Colors.green);
      _nameController.clear();
      _loadDataProfil(); // Refresh list profil otomatis
    }
  }

  // 3. FUNGSI UPDATE / EDIT PROFIL LAMA (SUDAH DIPERBAIKI 🛠️)
  Future<void> _updateProfil(String id, String name, String rateLimit, String sessionTimeout, String sharedUsers) async {
    setState(() => _isLoading = true);

    try {
      var response = await MikrotikAPI.run([
        [
          '/ip/hotspot/user/profile/set',
          '=.id=$id',
          '=rate-limit=$rateLimit',
          '=session-timeout=$sessionTimeout',
          '=shared-users=$sharedUsers',
          '=on-logout=$_scriptPembersihOtomatis' // SEKARANG SUDAH MENGGUNAKAN SCRIPT >= YANG AMAN
        ]
      ]);

      if (response.contains("ERROR") || response.contains("!trap")) {
        _showSnackBar("Gagal memperbarui profil $name", Colors.redAccent);
      } else {
        _showSnackBar("Profil $name berhasil diperbarui!", Colors.green);
        _loadDataProfil(); // Refresh list
      }
    } catch (e) {
      _showSnackBar("Terjadi kesalahan: $e", Colors.redAccent);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // 4. DIALOG POPUP FORM EDIT PROFIL
  void _openEditDialog(Map<String, String> profil) {
    final TextEditingController rateEditController = TextEditingController(text: profil['rate-limit'] ?? '');
    final TextEditingController timeEditController = TextEditingController(text: profil['session-timeout'] ?? '');
    final TextEditingController sharedEditController = TextEditingController(text: profil['shared-users'] ?? '1');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text("Edit Profil: ${profil['name']}", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.deepPurple)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: rateEditController,
                decoration: const InputDecoration(labelText: "Rate Limit / Kecepatan (Contoh: 1M/1M)", border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: timeEditController,
                decoration: const InputDecoration(labelText: "Masa Aktif / Session Timeout (Contoh: 1d)", border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: sharedEditController,
                decoration: const InputDecoration(labelText: "Shared Users (Bisa dipakai berapa HP)", border: OutlineInputBorder()),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 10),
              const Text(
                "*Fitur Auto-Clean otomatis aktif pada profil ini setelah disimpan.",
                style: TextStyle(fontSize: 11, color: Colors.grey, fontStyle: FontStyle.italic),
              )
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Batal")),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _updateProfil(
                profil['id'] ?? '',
                profil['name'] ?? '',
                rateEditController.text.trim(),
                timeEditController.text.trim(),
                sharedEditController.text.trim(),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple),
            child: const Text("Simpan", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
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
          padding: const EdgeInsets.all(16.0),
          children: [
            // BAGIAN 1: FORM INPUT
            Card(
              elevation: 3,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: ExpansionTile(
                initiallyExpanded: _listProfil.isEmpty,
                title: const Text("Buat Profil Baru", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.deepPurple)),
                leading: const Icon(Icons.add_box, color: Colors.deepPurple),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        TextField(controller: _nameController, decoration: const InputDecoration(labelText: "Nama Profil", border: OutlineInputBorder())),
                        const SizedBox(height: 10),
                        TextField(controller: _rateController, decoration: const InputDecoration(labelText: "Rate Limit (Contoh: 1M/1M)", border: OutlineInputBorder())),
                        const SizedBox(height: 10),
                        TextField(controller: _timeController, decoration: const InputDecoration(labelText: "Masa Aktif (Contoh: 1d)", border: OutlineInputBorder())),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: _isLoading 
                              ? const Center(child: CircularProgressIndicator()) 
                              : ElevatedButton.icon(
                                  icon: const Icon(Icons.save),
                                  label: const Text("Simpan ke Router"),
                                  onPressed: _tambahProfil,
                                  style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple, foregroundColor: Colors.white),
                                ),
                        ),
                      ],
                    ),
                  )
                ],
              ),
            ),
            const SizedBox(height: 25),
            
            // BAGIAN 2: LIST PROFIL
            const Text("Daftar Profil Terpasang", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            
            _listProfil.isEmpty && _isLoading
                ? const Center(child: Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()))
                : _listProfil.isEmpty
                    ? const Center(child: Padding(padding: EdgeInsets.all(20), child: Text("Tidak ada profil ditemukan")))
                    : Column(
                        children: _listProfil.map((prof) {
                          return Card(
                            elevation: 2,
                            margin: const EdgeInsets.symmetric(vertical: 6),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            child: ListTile(
                              leading: const CircleAvatar(
                                backgroundColor: Colors.amber,
                                child: Icon(Icons.speed, color: Colors.white),
                              ),
                              title: Text(prof['name'] ?? 'Unknown', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                              subtitle: Text(
                                "Speed: ${prof['rate-limit']?.isEmpty ?? true ? 'Unlimited' : prof['rate-limit']}\nTime Limit: ${prof['session-timeout'] ?? '-'} | Shared: ${prof['shared-users'] ?? '1'} User"
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.edit, color: Colors.deepPurple),
                                tooltip: "Edit Profil Ini",
                                onPressed: () => _openEditDialog(prof),
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
