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
  
  // Variabel untuk mengontrol apakah sedang menampilkan list detail atau tidak
  bool _showDetailList = false;

  @override
  void initState() {
    super.initState();
    _fetchUserAktif();
  }

  // 1. FUNGSI AMBIL DATA USER AKTIF DARI MIKROTIK
  Future<void> _fetchUserAktif() async {
    setState(() => _isLoading = true);

    try {
      var res = await MikrotikAPI.run([['/ip/hotspot/active/print']]);
      
      List<Map<String, String>> tempUsers = [];
      Map<String, String> currentUser = {};

      // Parser data flat list dari MikroTik API
      for (var line in res) {
        if (line.startsWith('=.id=')) {
          if (currentUser.isNotEmpty) {
            tempUsers.add(currentUser);
            currentUser = {};
          }
          currentUser['id'] = line.substring(5);
        } else if (line.startsWith('=user=')) {
          currentUser['user'] = line.substring(6);
        } else if (line.startsWith('=address=')) {
          currentUser['address'] = line.substring(9);
        } else if (line.startsWith('=uptime=')) {
          currentUser['uptime'] = line.substring(8);
        } else if (line.startsWith('=mac-address=')) {
          currentUser['mac'] = line.substring(13);
        }
      }
      
      if (currentUser.isNotEmpty) {
        tempUsers.add(currentUser);
      }

      setState(() {
        _listUserAktif = tempUsers;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      _showSnackBar("Gagal mengambil data: $e", Colors.redAccent);
    }
  }

  // 2. FUNGSI KICK / DISCONNECT USER
  Future<void> _kickUser(String id, String username) async {
    setState(() => _isLoading = true);
    
    try {
      var response = await MikrotikAPI.run([
        ['/ip/hotspot/active/remove', '=.id=$id']
      ]);

      setState(() => _isLoading = false);

      if (response.contains("ERROR") || response.contains("!trap")) {
        _showSnackBar("Gagal memutuskan koneksi $username", Colors.redAccent);
      } else {
        _showSnackBar("User $username berhasil diputus!", Colors.green);
        _fetchUserAktif(); // Refresh data otomatis setelah di-kick
      }
    } catch (e) {
      setState(() => _isLoading = false);
      _showSnackBar("Error: $e", Colors.redAccent);
    }
  }

  void _showSnackBar(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: color,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // Mengubah judul AppBar secara dinamis berdasarkan view yang aktif
        title: Text(
          _showDetailList ? "Detail User Aktif" : "Dashboard Aktif", 
          style: const TextStyle(fontWeight: FontWeight.bold)
        ),
        centerTitle: true,
        leading: _showDetailList 
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () {
                  setState(() {
                    _showDetailList = false; // Tombol kembali ke tampilan Grid
                  });
                },
              )
            : null,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchUserAktif,
          )
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _showDetailList 
              ? _buildListView()   // Tampilan 2: List Detail User Aktif
              : _buildGridView(),  // Tampilan 1: Kotak Grid Jumlah Aktif
    );
  }

  // ================= TAMPILAN 1: GRID VIEW (KOTAK RINGKASAN JUMLAH) =================
  Widget _buildGridView() {
    return GridView.count(
      crossAxisCount: 2,
      padding: const EdgeInsets.all(16),
      mainAxisSpacing: 16,
      crossAxisSpacing: 16,
      children: [
        // Kotak Grid Utama untuk User Aktif
        Card(
          elevation: 4,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          color: Colors.deepPurple,
          child: InkWell(
            borderRadius: BorderRadius.circular(15),
            onTap: () {
              // Jika ditekan, pindah ke halaman list detail
              setState(() {
                _showDetailList = true;
              });
            },
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Icon(Icons.people, size: 48, color: Colors.white),
                  const SizedBox(height: 12),
                  const Text(
                    "USER AKTIF",
                    style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "${_listUserAktif.length}",
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 32),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    "Ketuk untuk Detail",
                    style: TextStyle(color: Colors.white60, fontSize: 11, fontStyle: FontStyle.italic),
                  ),
                ],
              ),
            ),
          ),
        ),
        
        // Kotak Variasi Tambahan (Bisa Bos gunakan untuk info lain ke depannya)
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.wifi, size: 40, color: _listUserAktif.isEmpty ? Colors.grey : Colors.green),
                const SizedBox(height: 12),
                const Text("Status Hotspot", style: TextStyle(color: Colors.grey, fontSize: 12)),
                const SizedBox(height: 4),
                Text(
                  _listUserAktif.isEmpty ? "Sepi" : "Ramai Lancar",
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ================= TAMPILAN 2: LIST VIEW (DETAIL USER & TOMBOL KICK) =================
  Widget _buildListView() {
    if (_listUserAktif.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.wifi_off, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 10),
            Text(
              "Tidak ada user aktif",
              style: TextStyle(color: Colors.grey[600], fontSize: 16),
            ),
            const SizedBox(height: 15),
            ElevatedButton(
              onPressed: () => setState(() => _showDetailList = false),
              child: const Text("Kembali ke Dashboard"),
            )
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
                  Text("IP: ${user['address'] ?? '-'}"),
                  Text("MAC: ${user['mac'] ?? '-'}"),
                  Text(
                    "Uptime: ${user['uptime'] ?? '-'}",
                    style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              // Tombol Diskonek / Kick
              trailing: IconButton(
                icon: const Icon(Icons.flash_off, color: Colors.redAccent, size: 28),
                tooltip: "Putuskan Sesi",
                onPressed: () {
                  // Memicu popup dialog konfirmasi Ya/Tidak
                  _showKickDialog(user['id'] ?? '', user['user'] ?? '');
                },
              ),
            ),
          );
        },
      ),
    );
  }

  // ================= POPUP DIALOG KONFIRMASI (YA / TIDAK) =================
  void _showKickDialog(String id, String username) {
    showDialog(
      context: context,
      barrierDismissible: false, // User wajib memilih tombol, tidak bisa asal ketuk luar screen
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
            SizedBox(width: 8),
            Text("Putuskan Koneksi?", style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text("Apakah Bos yakin ingin men-kick user '$username' secara paksa dari jaringan?"),
        actions: [
          // Tombol TIDAK / BATAL
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Batal", style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
          ),
          // Tombol YA / KICK
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context); // Tutup dialog dulu
              _kickUser(id, username); // Jalankan fungsi kick ke MikroTik
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text("Ya, Kick!", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}