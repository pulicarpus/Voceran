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

  static Future<List<String>> run(List<List<String>> commands) async {
    if (commands.isEmpty) return [];

    final auth = await _getAuth();
    if (auth['ip']!.isEmpty || auth['user']!.isEmpty) {
      return ['ERROR', '!trap', '=message=Konfigurasi router belum lengkap'];
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

      reader = _RouterOsReader(socket);
      reader.start();

      final login = await _sendSentenceAndWait(socket, reader, [
        '/login',
        '=name=${auth['user']}',
        '=password=${auth['pass']}',
      ]);

      if (login.contains('!trap') || login.contains('!fatal') || login.contains('ERROR')) {
        return login;
      }

      final result = <String>[];

      for (final command in commands) {
        if (command.isEmpty) continue;
        final response = await _sendSentenceAndWait(socket, reader, command);
        result.addAll(response);

        if (response.contains('!trap') ||
            response.contains('!fatal') ||
            response.contains('ERROR')) {
          break;
        }
      }

      return result;
    } on SocketException catch (e) {
      return ['ERROR', '=message=Tidak dapat terhubung ke MikroTik: ${e.message}'];
    } on TimeoutException {
      return ['ERROR', '=message=Timeout menunggu respons MikroTik'];
    } catch (e) {
      return ['ERROR', '=message=$e'];
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
      final bytes = utf8.encode(word);
      socket.add(_encodeLength(bytes.length));
      socket.add(bytes);
    }

    socket.add(const <int>[0]);
    await socket.flush();

    return reader.nextSentence().timeout(_responseTimeout);
  }

  static List<int> _encodeLength(int length) {
    if (length < 0x80) return [length];
    if (length < 0x4000) {
      return [((length >> 8) | 0x80) & 0xFF, length & 0xFF];
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
}

class _RouterOsReader {
  final Socket socket;
  final List<int> _buffer = <int>[];
  final List<Completer<List<String>>> _pending = <Completer<List<String>>>[];

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
      onError: (Object error) => _failAll(error),
      onDone: () {
        if (!_closed) {
          _failAll(const SocketException(
            'Koneksi MikroTik ditutup sebelum response selesai',
          ));
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
    _parse();
    return completer.future;
  }

  void _parse() {
    while (!_closed && _buffer.isNotEmpty) {
      if (_buffer[0] == 0) {
        _buffer.removeAt(0);
        continue;
      }

      final info = _decodeLength(_buffer);
      if (info == null) return;

      final total = info.headerLength + info.length;
      if (_buffer.length < total) return;

      final wordBytes = _buffer.sublist(info.headerLength, total);
      _buffer.removeRange(0, total);

      final word = utf8.decode(wordBytes, allowMalformed: true);
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
    if (_pending.isEmpty) return;
    final completer = _pending.removeAt(0);
    if (!completer.isCompleted) completer.completeError(error);
    _currentWords = <String>[];
  }

  void _failAll(Object error) {
    for (final completer in _pending) {
      if (!completer.isCompleted) completer.completeError(error);
    }
    _pending.clear();
    _currentWords = <String>[];
  }

  void dispose() {
    if (_closed) return;
    _closed = true;
    _failAll(const SocketException('RouterOS reader dihentikan'));
    _subscription?.cancel();
    _subscription = null;
  }

  _LengthInfo? _decodeLength(List<int> data) {
    if (data.isEmpty) return null;
    final first = data[0];

    if ((first & 0x80) == 0) {
      return _LengthInfo(length: first, headerLength: 1);
    }
    if ((first & 0xC0) == 0x80) {
      if (data.length < 2) return null;
      return _LengthInfo(
        length: ((first & 0x3F) << 8) | data[1],
        headerLength: 2,
      );
    }
    if ((first & 0xE0) == 0xC0) {
      if (data.length < 3) return null;
      return _LengthInfo(
        length: ((first & 0x1F) << 16) | (data[1] << 8) | data[2],
        headerLength: 3,
      );
    }
    if ((first & 0xF0) == 0xE0) {
      if (data.length < 4) return null;
      return _LengthInfo(
        length: ((first & 0x0F) << 24) |
            (data[1] << 16) |
            (data[2] << 8) |
            data[3],
        headerLength: 4,
      );
    }
    if (first == 0xF0) {
      if (data.length < 5) return null;
      return _LengthInfo(
        length: (data[1] << 24) |
            (data[2] << 16) |
            (data[3] << 8) |
            data[4],
        headerLength: 5,
      );
    }

    throw const FormatException('Invalid RouterOS API length prefix');
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
