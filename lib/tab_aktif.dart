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
    
    var response = await MikrotikAPI.run([
      ['/ip/hotspot/active/remove', '=.id=$id']
    ]);

    if (response.contains("ERROR") || response.contains("!trap")) {
      _showSnackBar("Gagal memutuskan koneksi $username", Colors.redAccent);
    } else {
      _showSnackBar("User $username berhasil diputus!", Colors.green);
      _fetchUserAktif(); // Refresh data setelah di-kick
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
    return Scaffold(
      appBar: AppBar(
        title: const Text("User Aktif", style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchUserAktif,
          )
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _listUserAktif.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.wifi_off, size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 10),
                      Text(
                        "Tidak ada user aktif",
                        style: TextStyle(color: Colors.grey[600], fontSize: 16),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _fetchUserAktif,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(10),
                    itemCount: _listUserAktif.length,
                    itemBuilder: (context, index) {
                      final user = _listUserAktif[index];
                      return Card(
                        elevation: 2,
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
                              Text("Mac: ${user['mac'] ?? '-'}"),
                              Text(
                                "Uptime: ${user['uptime'] ?? '-'}",
                                style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.flash_off, color: Colors.redAccent),
                            tooltip: "Kick User",
                            onPressed: () {
                              _showKickDialog(user['id'] ?? '', user['user'] ?? '');
                            },
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }

  void _showKickDialog(String id, String username) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Putuskan Koneksi?"),
        dominantColor: Colors.red, // placeholder logical styling
        content: Text("Apakah Bos yakin ingin men-kick user $username secara paksa?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Batal"),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _kickUser(id, username);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text("Ya, Kick!", style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
