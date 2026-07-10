import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TabPengaturan extends StatefulWidget {
  const TabPengaturan({super.key});

  @override
  State<TabPengaturan> createState() => _TabPengaturanState();
}

class _TabPengaturanState extends State<TabPengaturan> {
  final TextEditingController _ipController = TextEditingController();
  final TextEditingController _userController = TextEditingController();
  final TextEditingController _passController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSavedData();
  }

  // Load data lama saat tab dibuka
  void _loadSavedData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _ipController.text = prefs.getString('ip') ?? '10.10.10.1';
      _userController.text = prefs.getString('user') ?? 'admin';
      _passController.text = prefs.getString('pass') ?? '';
    });
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('ip', _ipController.text);
    await prefs.setString('user', _userController.text);
    await prefs.setString('pass', _passController.text);
    
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Koneksi Router Tersimpan!")));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Pengaturan Router"), centerTitle: true),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            const Icon(Icons.router, size: 80, color: Colors.blueAccent),
            const SizedBox(height: 20),
            TextField(
              controller: _ipController, 
              decoration: const InputDecoration(labelText: "IP Address", border: OutlineInputBorder(), prefixIcon: Icon(Icons.dns))
            ),
            const SizedBox(height: 15),
            TextField(
              controller: _userController, 
              decoration: const InputDecoration(labelText: "Username API", border: OutlineInputBorder(), prefixIcon: Icon(Icons.person))
            ),
            const SizedBox(height: 15),
            TextField(
              controller: _passController, 
              obscureText: true, // Posisi ini sudah benar
              decoration: const InputDecoration(labelText: "Password API", border: OutlineInputBorder(), prefixIcon: Icon(Icons.lock))
            ),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.save),
                label: const Text("SIMPAN KONEKSI"),
                onPressed: _save,
              ),
            ),
          ],
        ),
      ),
    );
  }
}