import 'package:flutter/material.dart';
import 'mikrotik_api.dart';

class TabAktif extends StatefulWidget {
  final String ip, user, pass;
  const TabAktif({super.key, required this.ip, required this.user, required this.pass});

  @override
  State<TabAktif> createState() => _TabAktifState();
}

class _TabAktifState extends State<TabAktif> {
  List<Map<String, String>> _activeUsers = [];
  bool _isLoading = false;

  void _loadActive() async {
    setState(() => _isLoading = true);
    var res = await MikrotikAPI.run(widget.ip, widget.user, widget.pass, [['/ip/hotspot/active/print']]);
    
    List<Map<String, String>> temp = [];
    Map<String, String> current = {};
    
    for (var item in res) {
      if (item == '!re') {
        if (current.isNotEmpty) temp.add(Map.from(current));
        current.clear();
      } else if (item.startsWith('=user=')) current['user'] = item.substring(6);
      else if (item.startsWith('=address=')) current['address'] = item.substring(9);
    }
    
    setState(() {
      _activeUsers = temp;
      _isLoading = false;
    });
  }

  @override
  void initState() {
    super.initState();
    _loadActive();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("User Aktif"), actions: [
        IconButton(icon: const Icon(Icons.refresh), onPressed: _loadActive)
      ]),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : _activeUsers.isEmpty 
            ? const Center(child: Text("Tidak ada user aktif"))
            : ListView.builder(
                padding: const EdgeInsets.all(10),
                itemCount: _activeUsers.length,
                itemBuilder: (context, index) {
                  final u = _activeUsers[index];
                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 5),
                    child: ListTile(
                      leading: const CircleAvatar(backgroundColor: Colors.green, child: Icon(Icons.wifi, color: Colors.white)),
                      title: Text(u['user'] ?? "Unknown", style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text("IP: ${u['address']}"),
                      trailing: IconButton(
                        icon: const Icon(Icons.power_settings_new, color: Colors.red),
                        onPressed: () { /* Tambah logika kick user di sini */ },
                      ),
                    ),
                  );
                },
              ),
    );
  }
}