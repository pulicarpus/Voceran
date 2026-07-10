import 'dart:io';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class MikrotikAPI {
  static Future<Map<String, String>> _getAuth() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'ip': prefs.getString('ip') ?? '10.10.10.1',
      'user': prefs.getString('user') ?? 'admin',
      'pass': prefs.getString('pass') ?? '',
    };
  }

  // Hanya menerima 1 parameter (cmds)
  static Future<List<String>> run(List<List<String>> cmds) async {
    final auth = await _getAuth();
    try {
      final socket = await Socket.connect(auth['ip']!, 8728, timeout: const Duration(seconds: 3));
      
      void send(String w) {
        List<int> b = utf8.encode(w);
        socket.add(b.length < 128 ? [b.length] : [((b.length | 0x8000) >> 8) & 0xFF, (b.length | 0x8000) & 0xFF]);
        socket.add(b);
      }

      send('/login'); 
      send('=name=${auth['user']}'); 
      send('=password=${auth['pass']}'); 
      socket.add([0]);
      
      await Future.delayed(const Duration(milliseconds: 200));
      for (var c in cmds) { 
        for (var w in c) send(w); 
        socket.add([0]); 
      }
      
      List<int> raw = [];
      await socket.listen(raw.addAll).asFuture().timeout(const Duration(seconds: 2), onTimeout: () {});
      socket.destroy();
      
      List<String> out = []; 
      int i = 0;
      while (i < raw.length) {
        int b = raw[i++]; 
        if (b == 0) continue;
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