import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TabPengaturan extends StatefulWidget {
  const TabPengaturan({super.key});
  @override
  State<TabPengaturan> createState() => _TabPengaturanState();
}

class _TabPengaturanState extends State<TabPengaturan> {
  final _ip = TextEditingController();
  final _user = TextEditingController();
  final _pass = TextEditingController();

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('ip', _ip.text);
    await p.setString('user', _user.text);
    await p.setString('pass', _pass.text);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Router Tersimpan!")));
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      TextField(controller: _ip, decoration: const InputDecoration(labelText: "IP Router")),
      TextField(controller: _user, decoration: const InputDecoration(labelText: "User")),
      TextField(controller: _pass, decoration: const InputDecoration(labelText: "Password", obscureText: true)),
      ElevatedButton(onPressed: _save, child: const Text("Simpan Koneksi")),
    ]);
  }
}