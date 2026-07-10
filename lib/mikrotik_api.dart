import 'dart:io';
import 'dart:convert';

class MikrotikAPI {
  /// Fungsi untuk menjalankan perintah ke MikroTik via API (Port 8728)
  static Future<List<String>> run(String ip, String user, String pass, List<List<String>> cmds) async {
    try {
      // 1. Koneksi ke Router
      final socket = await Socket.connect(ip, 8728, timeout: const Duration(seconds: 3));

      // 2. Helper untuk mengirim perintah dengan format API MikroTik
      void send(String w) {
        List<int> b = utf8.encode(w);
        // Mengirimkan panjang kata (length prefix)
        if (b.length < 128) {
          socket.add([b.length]);
        } else {
          socket.add([((b.length | 0x8000) >> 8) & 0xFF, (b.length | 0x8000) & 0xFF]);
        }
        socket.add(b);
      }

      // 3. Login
      send('/login');
      send('=name=$user');
      send('=password=$pass');
      socket.add([0]); // Penanda akhir kalimat

      await Future.delayed(const Duration(milliseconds: 200));

      // 4. Kirim perintah
      for (var c in cmds) {
        for (var w in c) send(w);
        socket.add([0]);
      }

      // 5. Baca balasan dari Router
      List<int> raw = [];
      await socket.listen(raw.addAll).asFuture().timeout(const Duration(seconds: 2), onTimeout: () {});
      socket.destroy();

      // 6. Parsing (Mengupas kode byte MikroTik)
      List<String> out = [];
      int i = 0;
      while (i < raw.length) {
        int b = raw[i++];
        if (b == 0) continue; // Skip byte 0 (end of sentence)
        
        int len = (b < 0x80) ? b : ((b & 0x3F) << 8) | raw[i++];
        
        if (i + len <= raw.length) {
          out.add(utf8.decode(raw.sublist(i, i + len), allowMalformed: true));
          i += len;
        } else {
          break;
        }
      }
      return out;
    } catch (e) {
      return ["ERROR"];
    }
  }
}