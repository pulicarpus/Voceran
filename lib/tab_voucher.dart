import 'package:flutter/material.dart';
import 'mikrotik_api.dart';

class TabVoucher extends StatefulWidget {
  const TabVoucher({super.key});

  @override
  State<TabVoucher> createState() => _TabVoucherState();
}

class _TabVoucherState extends State<TabVoucher> {
  List<Map<String, String>> _vouchers = [];
  bool _isLoading = false;

  void _loadVouchers() async {
    setState(() => _isLoading = true);
    // Hanya 1 argumen
    var res = await MikrotikAPI.run([['/ip/hotspot/user/print']]);
    
    List<Map<String, String>> temp = [];
    Map<String, String> current = {};
    
    for (var item in res) {
      if (item == '!re') {
        if (current.isNotEmpty) temp.add(Map.from(current));
        current.clear();
      } else if (item.startsWith('=name=')) {
        current['name'] = item.substring(6);
      } else if (item.startsWith('=profile=')) {
        current['profile'] = item.substring(9);
      }
    }
    
    setState(() {
      _vouchers = temp;
      _isLoading = false;
    });
  }

  @override
  void initState() {
    super.initState();
    _loadVouchers();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Daftar Voucher"), centerTitle: true, actions: [
        IconButton(icon: const Icon(Icons.refresh), onPressed: _loadVouchers)
      ]),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : ListView.builder(
            padding: const EdgeInsets.all(10),
            itemCount: _vouchers.length,
            itemBuilder: (context, index) {
              final v = _vouchers[index];
              return Card(
                elevation: 3,
                margin: const EdgeInsets.symmetric(vertical: 6),
                child: ListTile(
                  leading: const CircleAvatar(backgroundColor: Colors.blueAccent, child: Icon(Icons.vpn_key, color: Colors.white)),
                  title: Text(v['name'] ?? "No Name", style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text("Profil: ${v['profile'] ?? '-'}"),
                  trailing: const Icon(Icons.chevron_right),
                ),
              );
            },
          ),
    );
  }
}