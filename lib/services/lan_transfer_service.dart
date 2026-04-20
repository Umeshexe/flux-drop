import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Nearby / LAN fast-path transport.
///
/// Protocol (sender → receiver over a TCP socket):
///   [4 bytes big-endian]  total file count
///   For each file:
///     [2 bytes big-endian]  filename UTF-8 byte length
///     [N bytes]             filename UTF-8 bytes
///     [8 bytes big-endian]  file size in bytes
///     [M bytes]             raw file bytes
///
/// The receiver falls back to Firebase Storage automatically
/// when the TCP connection cannot be established within [_connectTimeout].
class LanTransferService {
  static const _channel = MethodChannel('fluxdrop/storage');
  static const _connectTimeout = Duration(seconds: 5);
  static const _serverConnectionTimeout = Duration(seconds: 30);

  ServerSocket? _server;
  bool _cancelled = false;

  // ─── Sender side ───────────────────────────────────────────────────────────

  /// Binds a TCP server on a random port and immediately starts waiting for
  /// one receiver connection.  Returns the local IP and port to be published
  /// to Firestore so the receiver can connect.
  ///
  /// The Future completes when the receiver finishes downloading, or throws
  /// on timeout / error.
  Future<({String ip, int port})> startServer({
    required List<File> files,
    required List<String> fileNames,
    required Function(int sent, int total) onProgress,
  }) async {
    _cancelled = false;
    final ip = await _getLocalIp();
    _server = await ServerSocket.bind(InternetAddress.anyIPv4, 0);

    debugPrint(
      '📡 [LAN] Server listening on $ip:${_server!.port}',
    );

    // Serve in background — we don't await here because the caller needs the
    // port immediately to write to Firestore.
    _serveOnce(files: files, fileNames: fileNames, onProgress: onProgress);

    return (ip: ip, port: _server!.port);
  }

  void _serveOnce({
    required List<File> files,
    required List<String> fileNames,
    required Function(int sent, int total) onProgress,
  }) async {
    try {
      // Wait for first connection, with a timeout so we don't hang forever.
      final socket = await _server!.first
          .timeout(_serverConnectionTimeout)
          .catchError((_) => throw const SocketException('Receiver timed out'));

      debugPrint('📡 [LAN] Receiver connected: ${socket.remoteAddress.address}');

      final totalBytes = files.fold<int>(0, (s, f) => s + f.lengthSync());

      // Write file count
      socket.add(_int32BE(files.length));

      int sent = 0;
      for (int i = 0; i < files.length; i++) {
        if (_cancelled) break;
        final nameBytes = Uint8List.fromList(fileNames[i].codeUnits);
        // 2-byte filename length
        socket.add(_int16BE(nameBytes.length));
        socket.add(nameBytes);
        // 8-byte file size
        socket.add(_int64BE(files[i].lengthSync()));
        // raw bytes streamed
        await for (final chunk in files[i].openRead()) {
          if (_cancelled) break;
          socket.add(chunk);
          sent += chunk.length;
          onProgress(sent, totalBytes);
        }
      }

      await socket.flush();
      await socket.close();
      debugPrint('✅ [LAN] All files sent via LAN TCP');
    } catch (e) {
      debugPrint('⚠️ [LAN] Server error (receiver will fallback): $e');
    } finally {
      await _server?.close();
      _server = null;
    }
  }

  void cancelServer() {
    _cancelled = true;
    _server?.close();
    _server = null;
  }

  // ─── Receiver side ─────────────────────────────────────────────────────────

  /// Returns saved file paths on success, or throws so the caller can
  /// fall back to Firebase Storage.
  Future<List<String>> receiveFromServer({
    required String serverIp,
    required int serverPort,
    required String outputDir,
    required Function(int received, int total) onProgress,
    List<String> expectedHashes = const [],
  }) async {
    debugPrint('📡 [LAN] Attempting direct TCP to $serverIp:$serverPort');
    final socket = await Socket.connect(
      serverIp,
      serverPort,
      timeout: _connectTimeout,
    );

    final savedPaths = <String>[];
    final buffer = _SocketBuffer(socket);

    // Read file count
    final countBytes = await buffer.read(4);
    final fileCount = _parseInt32BE(countBytes);
    debugPrint('📡 [LAN] Expecting $fileCount file(s)');

    int totalReceived = 0;

    for (int i = 0; i < fileCount; i++) {
      // 2-byte filename length
      final nameLenBytes = await buffer.read(2);
      final nameLen = _parseInt16BE(nameLenBytes);
      // filename bytes
      final nameBytes = await buffer.read(nameLen);
      final name = String.fromCharCodes(nameBytes);
      // 8-byte file size
      final sizeBytes = await buffer.read(8);
      final fileSize = _parseInt64BE(sizeBytes);

      debugPrint('📡 [LAN] Receiving file: $name ($fileSize bytes)');

      final outPath = '$outputDir/$name';
      final outFile = File(outPath);
      final sink = outFile.openWrite();

      int bytesRead = 0;
      while (bytesRead < fileSize) {
        final remaining = fileSize - bytesRead;
        final chunkSize = remaining < 65536 ? remaining.toInt() : 65536;
        final chunk = await buffer.read(chunkSize);
        sink.add(chunk);
        bytesRead += chunk.length;
        totalReceived += chunk.length;
        onProgress(totalReceived, -1);
      }

      await sink.flush();
      await sink.close();

      // ── SHA-256 integrity check ──────────────────────────────────────────
      final computedHash =
          sha256.convert(await outFile.readAsBytes()).toString();
      final expectedHash =
          i < expectedHashes.length ? expectedHashes[i] : '';

      if (expectedHash.isNotEmpty && computedHash != expectedHash) {
        await outFile.delete();
        await socket.close();
        throw Exception(
          '📡 [LAN] Integrity check failed for $name. '
          'File may be corrupted in transit.',
        );
      }
      debugPrint(
        '📡 [LAN] SHA-256 ✅ $name: $computedHash',
      );

      savedPaths.add(outPath);
    }

    await socket.close();
    debugPrint('✅ [LAN] Received ${savedPaths.length} file(s) via LAN TCP');
    return savedPaths;
  }

  // ─── Subnet detection ──────────────────────────────────────────────────────

  /// Returns true if [ip1] and [ip2] are on the same /24 subnet (first 3 octets match).
  static bool isSameSubnet(String ip1, String ip2) {
    final p1 = ip1.split('.');
    final p2 = ip2.split('.');
    if (p1.length < 4 || p2.length < 4) return false;
    return p1[0] == p2[0] && p1[1] == p2[1] && p1[2] == p2[2];
  }

  /// Quickly probes the sender's TCP port to confirm reachability.
  static Future<bool> isReachable(String ip, int port) async {
    try {
      final sock =
          await Socket.connect(ip, port, timeout: const Duration(seconds: 3));
      await sock.close();
      return true;
    } catch (_) {
      return false;
    }
  }

  // ─── Local IP (via native method channel on Android for reliability) ───────

  static Future<String> _getLocalIp() async {
    // Try the native Android/iOS channel first (more reliable than dart:io on Android)
    try {
      final ip = await _channel.invokeMethod<String>('getWifiIp');
      if (ip != null && ip.isNotEmpty && ip != '0.0.0.0') {
        debugPrint('📡 [LAN] Got local IP from native: $ip');
        return ip;
      }
    } catch (_) {}

    // Fallback: enumerate dart:io NetworkInterface
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );
      for (final iface in interfaces) {
        // Prefer wlan/en interfaces (Wi-Fi)
        if (iface.name.startsWith('wlan') ||
            iface.name.startsWith('en') ||
            iface.name.startsWith('wl')) {
          final addr = iface.addresses.first.address;
          debugPrint(
            '📡 [LAN] Got local IP from dart:io (${iface.name}): $addr',
          );
          return addr;
        }
      }
      // Any non-loopback
      for (final iface in interfaces) {
        final addr = iface.addresses.first.address;
        if (!addr.startsWith('127.')) return addr;
      }
    } catch (e) {
      debugPrint('📡 [LAN] NetworkInterface.list failed: $e');
    }

    return '0.0.0.0';
  }

  static Future<String> getLocalIp() => _getLocalIp();

  // ─── Byte helpers ──────────────────────────────────────────────────────────

  static Uint8List _int16BE(int v) =>
      (ByteData(2)..setInt16(0, v, Endian.big)).buffer.asUint8List();

  static Uint8List _int32BE(int v) =>
      (ByteData(4)..setInt32(0, v, Endian.big)).buffer.asUint8List();

  static Uint8List _int64BE(int v) =>
      (ByteData(8)..setInt64(0, v, Endian.big)).buffer.asUint8List();

  static int _parseInt16BE(List<int> b) =>
      ByteData.sublistView(Uint8List.fromList(b)).getInt16(0, Endian.big);

  static int _parseInt32BE(List<int> b) =>
      ByteData.sublistView(Uint8List.fromList(b)).getInt32(0, Endian.big);

  static int _parseInt64BE(List<int> b) =>
      ByteData.sublistView(Uint8List.fromList(b)).getInt64(0, Endian.big);
}

// ─── Buffered socket reader ────────────────────────────────────────────────────
/// Wraps a Socket stream and allows reading exactly N bytes at a time,
/// which is necessary for the framed LAN protocol.
class _SocketBuffer {
  final Socket _socket;
  final _buf = <int>[];
  final _controller = StreamController<List<int>>.broadcast();
  late final StreamSubscription _sub;

  _SocketBuffer(this._socket) {
    _sub = _socket.listen(
      (data) {
        _buf.addAll(data);
        _controller.add(data);
      },
      onError: (e) => _controller.addError(e),
      onDone: () => _controller.close(),
    );
  }

  Future<List<int>> read(int count) async {
    while (_buf.length < count) {
      await _controller.stream.first;
    }
    final result = List<int>.from(_buf.take(count));
    _buf.removeRange(0, count);
    return result;
  }

  void close() {
    _sub.cancel();
    _controller.close();
  }
}
