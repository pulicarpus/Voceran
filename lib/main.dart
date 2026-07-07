import 'package:flutter/material.dart';
import 'package:mikrotik_api/mikrotik_api.dart';
import 'dart:math';

void main() => runApp(MyApp());

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Voceran MikroTik',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: VoucherScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class VoucherScreen extends StatefulWidget {
  @override
  _VoucherScreenState createState() => _VoucherScreenState();
}

class _VoucherScreenState extends State<VoucherScreen> {
  final _ipController = TextEditingController(text: "192.168.88.1");
  final _userController = TextEditingController(text: "admin");
  final _passController = TextEditingController();
  String _hasilVoucher = "-";
  bool _isLoading = false;

  String generateCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    return List.generate(5, (index) => chars[Random().nextInt(chars.length)]).join();
  }

  void buatVoucher(String profil, String limitWaktu) async {
    setState(() {
      _isLoading = true;
      _hasilVoucher = "Memproses...";
    });

    String kode = generateCode();
    var client = RouterClient(_ipController.text, _userController.text, _passController.text);
    
    try {
      bool connected = await client.connect();
      if (connected) {
        await client.talk([
          '/ip/hotspot/user/add',
          '=name=$kode',
          '=password=$kode',
          '=profile=$profil',
          '=limit-uptime=$limitWaktu'
        ]);
        
        setState(() {
          _hasilVoucher = kode;
        });
        client.disconnect();
      } else {
        showSnippet("Koneksi ke MikroTik Gagal!");
        setState(() { _hasilVoucher = "-"; });
      }
    } catch (e) {
      showSnippet("Error: $e");
      setState(() { _hasilVoucher = "-"; });
    } finally {
      setState(() { _isLoading = false; });
    }
  }

  void showSnippet(String pesan) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(pesan)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Voceran MikroTik v6')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(controller: _ipController, decoration: InputDecoration(labelText: 'IP / Domain VPN Remote')),
              TextField(controller: _userController, decoration: InputDecoration(labelText: 'Username Router')),
              TextField(controller: _passController, decoration: InputDecoration(labelText: 'Password Router'), obscureText: true),
              SizedBox(height: 24),
              Text('PILIH PAKET:', style: TextStyle(fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.green, padding: EdgeInsets.symmetric(vertical: 12)),
                onPressed: _isLoading ? null : () => buatVoucher('Paket_2K', '02:00:00'),
                child: Text('2 Jam (Paket_2K)', style: TextStyle(color: Colors.white)),
              ),
              SizedBox(height: 10),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, padding: EdgeInsets.symmetric(vertical: 12)),
                onPressed: _isLoading ? null : () => buatVoucher('Paket_5K', '12:00:00'),
                child: Text('12 Jam (Paket_5K)', style: TextStyle(color: Colors.white)),
              ),
              SizedBox(height: 24),
              Card(
                color: Colors.grey[200],
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      Text('KODE VOUCHER', style: TextStyle(fontSize: 14, color: Colors.grey[600])),
                      SizedBox(height: 10),
                      Text(_hasilVoucher, style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold, letterSpacing: 4, color: Colors.blue[900])),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
