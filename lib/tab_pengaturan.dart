import 'package:flutter/material.dart';

class TabPengaturan extends StatefulWidget {
  // Kita buat callback agar perubahan data bisa tersimpan ke variabel global di main.dart
  final Function(String, String, String) onSave;
  
  const TabPengaturan({super.key, required this.onSave});

  @override
  State<TabPengaturan> createState() => _TabPengaturanState();
}

class _TabPengaturanState extends State<TabPengaturan> {
  final _ipController = TextEditingController(text: '10.10.10.1');
  final _userController = TextEditingController(text: 'admin');
  final _passController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Pengaturan Router"), centerTitle: true),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            const Icon(Icons.router, size: 60, color: Colors.blueAccent),
            const SizedBox(height: 20),
            TextField(controller: _ipController, decoration: const InputDecoration(labelText: "IP Address", border: OutlineInputBorder(), prefixIcon: Icon(Icons.dns))),
            const SizedBox(height: 15),
            TextField(controller: _userController, decoration: const InputDecoration(labelText: "Username API", border: OutlineInputBorder(), prefixIcon: Icon(Icons.person))),
            const SizedBox(height: 15),
            TextField(controller: _passController, decoration: const InputDecoration(labelText: "Password API", border: OutlineInputBorder(), prefixIcon: Icon(Icons.lock)), obscureText: true),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.save),
                label: const Text("SIMPAN KONEKSI"),
                onPressed: () {
                  widget.onSave(
                    _ipController.text,
                    _userController.text,
                    _passController.text
                  );
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Pengaturan berhasil disimpan!")));
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}