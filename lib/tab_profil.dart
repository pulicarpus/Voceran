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

  bool _isLoading = false;

  void _tambahProfil() async {
    setState(() => _isLoading = true);
    
    List<List<String>> command = [[
      '/ip/hotspot/user/profile/add',
      '=name=${_nameController.text}',
      '=rate-limit=${_rateController.text}',
      '=session-timeout=${_timeController.text}'
    ]];

    // Hanya 1 argumen
    var response = await MikrotikAPI.run(command);
    setState(() => _isLoading = false);

    if (response.contains("ERROR")) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Gagal Simpan! Cek koneksi")));
    } else {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Profil Berhasil Dibuat!")));
      _nameController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const Text("Buat Profil Baru", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
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
                  ),
            ),
          ],
        ),
      ),
    );
  }
}