import 'package:flutter/material.dart';
import 'tab_cetak.dart';
import 'tab_voucher.dart';
import 'tab_profil.dart';
import 'tab_aktif.dart';
import 'tab_pengaturan.dart';

void main() => runApp(const MaterialApp(debugShowCheckedModeBanner: false, home: HomePage()));

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _index = 0;
  final List<Widget> _pages = [const TabCetak(), const TabVoucher(), const TabProfil(), const TabAktif(), const TabPengaturan()];
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_index],
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
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