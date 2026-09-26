import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

class MikrotikAPI {
  static const int _apiPort = 8728;
  static const Duration _connectTimeout = Duration(seconds: 5);
  static const Duration _responseTimeout = Duration(seconds: 5);

  static Future<Map<String, String>> _getAuth() async {
    final prefs = await SharedPreferences.getInstance();

    return {
      'ip': prefs.getString('ip')?.trim() ?? '10.10.10.1',
      'user': prefs.getString('user')?.trim() ?? 'admin',
      'pass': prefs.getString('pass') ?? '',
    };
  }

  /// Menjalankan command RouterOS API secara berurutan.
  ///
  /// Penting: Socket Stream hanya memiliki SATU listener yang dibuat
  /// untuk seluruh koneksi. Ini mencegah:
  /// "Bad state: Stream has already been listened to."
  static Future<List<String>> run(List<List<String>> commands) async {
    if (commands.isEmpty) {
      return [];
    }

    final auth = await _getAuth();

    if (auth['ip']!.isEmpty || auth['user']!.isEmpty) {
      return [
        'ERROR',
        '!trap',
        '=message=Konfigurasi router belum lengkap',
      ];
    }

    Socket? socket;
    _RouterOsReader? reader;

    try {
      socket = await Socket.connect(
        auth['ip']!,
        _apiPort,
        timeout: _connectTimeout,
      );

      socket.setOption(SocketOption.tcpNoDelay, true);

      // SATU listener untuk seluruh umur socket.
      reader = _RouterOsReader(socket);
      reader.start();

      // RouterOS v6 classic login.
      await _sendSentenceAndWait(
        socket,
        reader,
        [
          '/login',
          '=name=${auth['user']}',
          '=password=${auth['pass']}',
        ],
      );

      final result = <String>[];

      for (final command in commands) {
        if (command.isEmpty) {
          continue;
        }

        final response = await _sendSentenceAndWait(
          socket,
          reader,
          command,
        );

        result.addAll(response);

        if (_containsTrap(response)) {
          break;
        }
      }

      return result;
    } on SocketException catch (e) {
      return [
        'ERROR',
        '=message=Tidak dapat terhubung ke MikroTik: ${e.message}',
      ];
    } on TimeoutException {
      return [
        'ERROR',
        '=message=Timeout menunggu respons MikroTik',
      ];
    } catch (e) {
      return [
        'ERROR',
        '=message=$e',
      ];
    } finally {
      reader?.dispose();

      try {
        socket?.destroy();
      } catch (_) {}
    }
  }

  static Future<List<String>> _sendSentenceAndWait(
    Socket socket,
    _RouterOsReader reader,
    List<String> words,
  ) async {
    for (final word in words) {
      _sendWord(socket, word);
    }

    // Empty word menandai akhir sentence.
    socket.add(const <int>[0]);
    await socket.flush();

    return reader.nextSentence().timeout(_responseTimeout);
  }

  static void _sendWord(Socket socket, String word) {
    final bytes = utf8.encode(word);

    socket.add(_encodeLength(bytes.length));
    socket.add(bytes);
  }

  static List<int> _encodeLength(int length) {
    if (length < 0x80) {
      return [length];
    }

    if (length < 0x4000) {
      return [
        ((length >> 8) | 0x80) & 0xFF,
        length & 0xFF,
      ];
    }

    if (length < 0x200000) {
      return [
        ((length >> 16) | 0xC0) & 0xFF,
        (length >> 8) & 0xFF,
        length & 0xFF,
      ];
    }

    if (length < 0x10000000) {
      return [
        ((length >> 24) | 0xE0) & 0xFF,
        (length >> 16) & 0xFF,
        (length >> 8) & 0xFF,
        length & 0xFF,
      ];
    }

    return [
      0xF0,
      (length >> 24) & 0xFF,
      (length >> 16) & 0xFF,
      (length >> 8) & 0xFF,
      length & 0xFF,
    ];
  }

  static bool _containsTrap(List<String> response) {
    return response.contains('!trap') ||
        response.contains('!fatal') ||
        response.contains('ERROR');
  }
}

/// Satu parser/listener permanen untuk satu Socket RouterOS.
///
/// Setiap pemanggilan nextSentence() hanya menunggu hasil dari
/// sentence berikutnya; tidak pernah memanggil listen() kedua kali.
class _RouterOsReader {
  final Socket socket;

  final _buffer = <int>[];
  final _pending = <Completer<List<String>>>[];

  StreamSubscription<List<int>>? _subscription;
  List<String> _currentWords = <String>[];
  bool _started = false;
  bool _closed = false;

  _RouterOsReader(this.socket);

  void start() {
    if (_started) return;
    _started = true;

    _subscription = socket.listen(
      (data) {
        if (_closed) return;

        _buffer.addAll(data);

        try {
          _parse();
        } catch (e) {
          _failCurrent(e);
        }
      },
      onError: (Object error) {
        _failAll(error);
      },
      onDone: () {
        if (!_closed) {
          _failAll(
            const SocketException(
              'Koneksi MikroTik ditutup sebelum response selesai',
            ),
          );
        }
      },
      cancelOnError: false,
    );
  }

  Future<List<String>> nextSentence() {
    if (_closed) {
      return Future.error(
        const SocketException('RouterOS reader sudah ditutup'),
      );
    }

    final completer = Completer<List<String>>();
    _pending.add(completer);

    // Response mungkin sudah masuk sangat cepat sebelum pemanggilan
    // berikutnya. Parser tetap dijalankan terhadap buffer yang tersisa.
    _parse();

    return completer.future;
  }

  void _parse() {
    while (!_closed) {
      if (_buffer.isEmpty) {
        return;
      }

      // Empty word = separator akhir sentence.
      if (_buffer[0] == 0) {
        _buffer.removeAt(0);
        continue;
      }

      final lengthInfo = _decodeLength(_buffer);

      if (lengthInfo == null) {
        return;
      }

      final total = lengthInfo.headerLength + lengthInfo.length;

      if (_buffer.length < total) {
        return;
      }

      final wordBytes = _buffer.sublist(
        lengthInfo.headerLength,
        total,
      );

      _buffer.removeRange(0, total);

      final word = utf8.decode(
        wordBytes,
        allowMalformed: true,
      );

      _currentWords.add(word);

      if (word == '!done' || word == '!fatal') {
        _completeCurrent();
      }
    }
  }

  void _completeCurrent() {
    if (_pending.isEmpty) {
      _currentWords = <String>[];
      return;
    }

    final completer = _pending.removeAt(0);

    if (!completer.isCompleted) {
      completer.complete(List<String>.from(_currentWords));
    }

    _currentWords = <String>[];
  }

  void _failCurrent(Object error) {
    if (_pending.isEmpty) {
      return;
    }

    final completer = _pending.removeAt(0);

    if (!completer.isCompleted) {
      completer.completeError(error);
    }

    _currentWords = <String>[];
  }

  void _failAll(Object error) {
    for (final completer in _pending) {
      if (!completer.isCompleted) {
        completer.completeError(error);
      }
    }

    _pending.clear();
    _currentWords = <String>[];
  }

  void dispose() {
    _closed = true;
    _failAll(
      const SocketException('RouterOS reader dihentikan'),
    );
    _subscription?.cancel();
    _subscription = null;
  }

  static _LengthInfo? _decodeLength(List<int> data) {
    if (data.isEmpty) {
      return null;
    }

    final first = data[0];

    // 1 byte
    if ((first & 0x80) == 0) {
      return _LengthInfo(
        length: first,
        headerLength: 1,
      );
    }

    // 2 byte
    if ((first & 0xC0) == 0x80) {
      if (data.length < 2) {
        return null;
      }

      return _LengthInfo(
        length: ((first & 0x3F) << 8) | data[1],
        headerLength: 2,
      );
    }

    // 3 byte
    if ((first & 0xE0) == 0xC0) {
      if (data.length < 3) {
        return null;
      }

      return _LengthInfo(
        length:
            ((first & 0x1F) << 16) |
            (data[1] << 8) |
            data[2],
        headerLength: 3,
      );
    }

    // 4 byte
    if ((first & 0xF0) == 0xE0) {
      if (data.length < 4) {
        return null;
      }

      return _LengthInfo(
        length:
            ((first & 0x0F) << 24) |
            (data[1] << 16) |
            (data[2] << 8) |
            data[3],
        headerLength: 4,
      );
    }

    // 5 byte
    if (first == 0xF0) {
      if (data.length < 5) {
        return null;
      }

      return _LengthInfo(
        length:
            (data[1] << 24) |
            (data[2] << 16) |
            (data[3] << 8) |
            data[4],
        headerLength: 5,
      );
    }

    throw const FormatException(
      'Invalid RouterOS API length prefix',
    );
  }
}

class _LengthInfo {
  final int length;
  final int headerLength;

  const _LengthInfo({
    required this.length,
    required this.headerLength,
  });
}
