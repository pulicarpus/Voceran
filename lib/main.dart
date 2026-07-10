import 'package:flutter/material.dart';
import 'tab_cetak.dart';
import 'tab_voucher.dart';
import 'tab_profil.dart';
import 'tab_aktif.dart';
import 'tab_pengaturan.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Voucher Master Pro',
      theme: ThemeData(primarySwatch: Colors.blue, useMaterial3: true),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _currentIndex = 0;

  // Data Global untuk semua tab
  String ip = "10.10.10.1";
  String user = "admin";
  String pass = "";

  // List Halaman
  final List<Widget> _pages = [
    const TabCetak(),
    const TabVoucher(),
    const TabProfil(),
    const TabAktif(),
    const TabPengaturan(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_currentIndex],
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _currentIndex,
        onTap: (index) => setState(() => _currentIndex = index),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.print), label: 'Cetak'),
          BottomNavigationBarItem(icon: Icon(Icons.list), label: 'Voucher'),
          BottomNavigationBarItem(icon: Icon(Icons.add_circle), label: 'Profil'),
          BottomNavigationBarItem(icon: Icon(Icons.bolt), label: 'Aktif'),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Router'),
        ],
      ),
    );
  }
}