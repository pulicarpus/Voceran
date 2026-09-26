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

  /// Menjalankan satu atau beberapa command RouterOS API.
  ///
  /// Contoh:
  /// [
  ///   ['/system/identity/print'],
  ///   ['/ip/hotspot/user/print']
  /// ]
  ///
  /// Semua command dikirim secara berurutan dan setiap command
  /// ditunggu sampai RouterOS mengirim !done / !trap.
  static Future<List<String>> run(List<List<String>> commands) async {
    if (commands.isEmpty) {
      return [];
    }

    final auth = await _getAuth();

    if (auth['ip']!.isEmpty || auth['user']!.isEmpty) {
      return ['!trap', '=message=Konfigurasi router belum lengkap'];
    }

    Socket? socket;

    try {
      socket = await Socket.connect(
        auth['ip']!,
        _apiPort,
        timeout: _connectTimeout,
      );

      socket.setOption(SocketOption.tcpNoDelay, true);

      // RouterOS API klasik / RouterOS v6:
      // /login
      // =name=username
      // =password=password
      // !done
      await _sendSentenceAndWait(
        socket,
        [
          '/login',
          '=name=${auth['user']}',
          '=password=${auth['pass']}',
        ],
      );

      final List<String> result = [];

      for (final command in commands) {
        if (command.isEmpty) {
          continue;
        }

        final response = await _sendSentenceAndWait(
          socket,
          command,
        );

        result.addAll(response);

        // Jangan lanjutkan command berikutnya jika RouterOS
        // melaporkan kesalahan.
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
      try {
        socket?.destroy();
      } catch (_) {}
    }
  }

  /// Mengirim satu sentence RouterOS API dan menunggu sampai
  /// RouterOS menyelesaikan sentence tersebut.
  static Future<List<String>> _sendSentenceAndWait(
    Socket socket,
    List<String> words,
  ) async {
    for (final word in words) {
      _sendWord(socket, word);
    }

    // Empty word menandai akhir sentence.
    socket.add(const <int>[0]);

    await socket.flush();

    return _readSentence(socket);
  }

  /// Encode dan kirim satu word menggunakan framing RouterOS API.
  static void _sendWord(Socket socket, String word) {
    final bytes = utf8.encode(word);

    socket.add(_encodeLength(bytes.length));
    socket.add(bytes);
  }

  /// RouterOS API variable-length encoding.
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

  /// Membaca response RouterOS sampai menemukan !done atau !trap.
  ///
  /// Parser ini juga menangani frame yang terpotong di tengah packet,
  /// karena TCP tidak menjamin satu packet = satu word API.
  static Future<List<String>> _readSentence(Socket socket) async {
    final completer = Completer<List<String>>();
    final buffer = <int>[];
    final words = <String>[];

    StreamSubscription<List<int>>? subscription;
    Timer? timeoutTimer;

    void finish(List<String> result) {
      if (completer.isCompleted) {
        return;
      }

      timeoutTimer?.cancel();
      subscription?.cancel();
      completer.complete(result);
    }

    void fail(Object error) {
      if (completer.isCompleted) {
        return;
      }

      timeoutTimer?.cancel();
      subscription?.cancel();

      if (error is TimeoutException) {
        completer.completeError(error);
      } else {
        completer.completeError(error);
      }
    }

    void parseBuffer() {
      while (true) {
        if (buffer.isEmpty) {
          return;
        }

        // Empty word = akhir sentence.
        if (buffer[0] == 0) {
          buffer.removeAt(0);
          continue;
        }

        final lengthInfo = _decodeLength(buffer);

        if (lengthInfo == null) {
          return;
        }

        final headerLength = lengthInfo.headerLength;
        final wordLength = lengthInfo.length;

        if (buffer.length < headerLength + wordLength) {
          return;
        }

        final start = headerLength;
        final end = start + wordLength;

        final wordBytes = buffer.sublist(start, end);
        buffer.removeRange(0, end);

        final word = utf8.decode(
          wordBytes,
          allowMalformed: true,
        );

        words.add(word);

        // RouterOS menyelesaikan sentence dengan !done.
        if (word == '!done') {
          finish(List<String>.from(words));
          return;
        }

        // !trap berarti command gagal.
        // Kita tetap kembalikan response lengkap agar caller
        // bisa membaca =message=...
        if (word == '!trap') {
          // Jangan langsung finish di sini.
          // RouterOS biasanya mengirim =message= setelah !trap.
          continue;
        }

        // !fatal juga harus mengakhiri pembacaan.
        if (word == '!fatal') {
          finish(List<String>.from(words));
          return;
        }
      }
    }

    timeoutTimer = Timer(
      _responseTimeout,
      () {
        fail(
          TimeoutException(
            'Timeout menunggu response RouterOS API',
          ),
        );
      },
    );

    subscription = socket.listen(
      (data) {
        buffer.addAll(data);

        try {
          parseBuffer();
        } catch (e) {
          fail(e);
        }
      },
      onError: (Object error) {
        fail(error);
      },
      onDone: () {
        if (!completer.isCompleted) {
          fail(
            const SocketException(
              'Koneksi MikroTik ditutup sebelum !done diterima',
            ),
          );
        }
      },
      cancelOnError: false,
    );

    return completer.future;
  }

  /// Decode RouterOS variable-length prefix.
  static _LengthInfo? _decodeLength(List<int> data) {
    if (data.isEmpty) {
      return null;
    }

    final first = data[0];

    // 1 byte length
    if ((first & 0x80) == 0) {
      return _LengthInfo(
        length: first,
        headerLength: 1,
      );
    }

    // 2 byte length
    if ((first & 0xC0) == 0x80) {
      if (data.length < 2) {
        return null;
      }

      final length =
          ((first & 0x3F) << 8) |
          data[1];

      return _LengthInfo(
        length: length,
        headerLength: 2,
      );
    }

    // 3 byte length
    if ((first & 0xE0) == 0xC0) {
      if (data.length < 3) {
        return null;
      }

      final length =
          ((first & 0x1F) << 16) |
          (data[1] << 8) |
          data[2];

      return _LengthInfo(
        length: length,
        headerLength: 3,
      );
    }

    // 4 byte length
    if ((first & 0xF0) == 0xE0) {
      if (data.length < 4) {
        return null;
      }

      final length =
          ((first & 0x0F) << 24) |
          (data[1] << 16) |
          (data[2] << 8) |
          data[3];

      return _LengthInfo(
        length: length,
        headerLength: 4,
      );
    }

    // 5 byte length
    if (first == 0xF0) {
      if (data.length < 5) {
        return null;
      }

      final length =
          (data[1] << 24) |
          (data[2] << 16) |
          (data[3] << 8) |
          data[4];

      return _LengthInfo(
        length: length,
        headerLength: 5,
      );
    }

    throw const FormatException(
      'Invalid RouterOS API length prefix',
    );
  }

  static bool _containsTrap(List<String> response) {
    return response.contains('!trap') ||
        response.contains('!fatal') ||
        response.contains('ERROR');
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