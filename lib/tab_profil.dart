import 'package:flutter/material.dart';
import 'mikrotik_api.dart';

class TabProfil extends StatefulWidget {
  const TabProfil({super.key});

  @override
  State<TabProfil> createState() => _TabProfilState();
}

class _TabProfilState extends State<TabProfil> {
  // Controller input
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _rateController = TextEditingController(text: '1M/1M');
  final TextEditingController _timeController = TextEditingController(text: '1d');

  bool _isLoading = false;

  void _tambahProfil() async {
    setState(() => _isLoading = true);
    
    // Perintah API MikroTik untuk menambah profil
    List<List<String>> command = [[
      '/ip/hotspot/user/profile/add',
      '=name=${_nameController.text}',
      '=rate-limit=${_rateController.text}',
      '=session-timeout=${_timeController.text}'
    ]];

    // Panggil engine kita
    var response = await MikrotikAPI.run("10.10.10.1", "admin", "", command);

    setState(() => _isLoading = false);

    if (response.contains("ERROR")) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Gagal Simpan! Cek koneksi")));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Profil Berhasil Dibuat!")));
      _nameController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          TextField(controller: _nameController, decoration: const InputDecoration(labelText: "Nama Profil")),
          TextField(controller: _rateController, decoration: const InputDecoration(labelText: "Rate Limit (Contoh: 1M/1M)")),
          TextField(controller: _timeController, decoration: const InputDecoration(labelText: "Masa Aktif (Contoh: 1d)")),
          const SizedBox(height: 20),
          _isLoading 
            ? const CircularProgressIndicator() 
            : ElevatedButton(onPressed: _tambahProfil, child: const Text("Simpan ke Router")),
        ],
      ),
    );
  }
}