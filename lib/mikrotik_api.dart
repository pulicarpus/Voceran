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
  /// Setiap command dikirim sebagai satu sentence dan ditunggu
  /// sampai RouterOS mengirim !done / !fatal.
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

    try {
      socket = await Socket.connect(
        auth['ip']!,
        _apiPort,
        timeout: _connectTimeout,
      );

      socket.setOption(SocketOption.tcpNoDelay, true);

      // IMPORTANT:
      // Socket Stream adalah single-subscription stream.
      // Versi lama mencoba listen() ulang untuk setiap command,
      // sehingga setelah command pertama muncul:
      // "Bad state: Stream has already been listened to."
      //
      // Broadcast stream memungkinkan setiap sentence membuat
      // subscription baru setelah sentence sebelumnya selesai.
      final input = socket.asBroadcastStream();

      // Login RouterOS v6.
      await _sendSentenceAndWait(
        socket,
        input,
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
          input,
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
      try {
        socket?.destroy();
      } catch (_) {}
    }
  }

  static Future<List<String>> _sendSentenceAndWait(
    Socket socket,
    Stream<List<int>> input,
    List<String> words,
  ) async {
    for (final word in words) {
      _sendWord(socket, word);
    }

    // Empty word menandai akhir sentence.
    socket.add(const <int>[0]);
    await socket.flush();

    return _readSentence(input);
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

  static Future<List<String>> _readSentence(
    Stream<List<int>> input,
  ) async {
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
      completer.completeError(error);
    }

    void parseBuffer() {
      while (true) {
        if (buffer.isEmpty) {
          return;
        }

        // Empty word = end of sentence.
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

        if (word == '!done') {
          finish(List<String>.from(words));
          return;
        }

        if (word == '!fatal') {
          finish(List<String>.from(words));
          return;
        }

        // !trap biasanya diikuti =message=..., jadi teruskan
        // membaca sampai !done / akhir response.
      }
    }

    timeoutTimer = Timer(
      _responseTimeout,
      () {
        fail(
          const TimeoutException(
            'Timeout menunggu response RouterOS API',
          ),
        );
      },
    );

    subscription = input.listen(
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
              'Koneksi MikroTik ditutup sebelum response selesai',
            ),
          );
        }
      },
      cancelOnError: false,
    );

    return completer.future;
  }

  static _LengthInfo? _decodeLength(List<int> data) {
    if (data.isEmpty) {
      return null;
    }

    final first = data[0];

    if ((first & 0x80) == 0) {
      return _LengthInfo(
        length: first,
        headerLength: 1,
      );
    }

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
