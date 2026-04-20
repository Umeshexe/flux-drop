import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'package:file_picker/file_picker.dart';

import '../core/constants.dart';
import '../models/transfer_model.dart';
import '../models/user_model.dart';

class TransferCancelledException implements Exception {
  final String message;

  TransferCancelledException(this.message);

  @override
  String toString() => message;
}

class TransferService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final _uuid = const Uuid();
  static const _storageChannel = MethodChannel('fluxdrop/storage');
  static UploadTask? _activeUploadTask;
  static String? _activeUploadTransferId;
  static bool _uploadCancelRequested = false;
  static final Map<String, DownloadTask> _activeDownloadTasks = {};
  static final Set<String> _downloadCancelRequested = <String>{};

  Future<bool> _hasEnoughStorage(int requiredBytes) async {
    if (kIsWeb) return true; // fallback
    try {
      final int? freeSpace = await _storageChannel.invokeMethod('getFreeSpace');
      if (freeSpace != null) {
        // Buffer of 50 MB
        return freeSpace > (requiredBytes + 50 * 1024 * 1024);
      }
    } catch (e) {
      debugPrint('Storage check disabled or failed: $e');
    }
    return true; // Fallback: pretend we have space
  }

  Future<bool> cancelCurrentUpload() async {
    final transferId = _activeUploadTransferId;
    if (transferId == null) return false;
    _uploadCancelRequested = true;
    final task = _activeUploadTask;
    if (task == null) {
      return true;
    }
    try {
      return await task.cancel();
    } catch (_) {
      return true;
    }
  }

  Future<bool> cancelUpload(String transferId) async {
    if (_activeUploadTransferId != transferId) return false;
    return cancelCurrentUpload();
  }

  Future<bool> cancelDownload(String transferId) async {
    final hasTrackedDownload =
        _activeDownloadTasks.containsKey(transferId) ||
        _downloadCancelRequested.contains(transferId);
    if (!hasTrackedDownload) return false;

    _downloadCancelRequested.add(transferId);
    final task = _activeDownloadTasks[transferId];
    if (task == null) {
      return true;
    }

    try {
      return await task.cancel();
    } catch (_) {
      return true;
    }
  }

  // ─── Stream of incoming transfers for a receiver ──────────────────────────
  Stream<List<TransferModel>> incomingTransfers(String receiverId) {
    debugPrint(
      '📥 [Transfer] Listening for incoming transfers for: $receiverId',
    );
    return _db
        .collection(AppConstants.transfersCollection)
        .where('receiverId', isEqualTo: receiverId)
        .where(
          'status',
          whereIn: [
            AppConstants.statusUploading, // receiver sees live upload progress
            AppConstants.statusUploaded,
            AppConstants.statusDownloading,
            AppConstants.statusCompleted,
          ],
        )
        .snapshots()
        .map((snap) {
          final list = snap.docs
              .map((d) => TransferModel.fromMap(d.data()))
              .toList();
          // Local sort by createdAt descending to avoid composite index requirement
          list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return list;
        });
  }

  // ─── Stream of outgoing transfers for a sender ────────────────────────────
  Stream<List<TransferModel>> outgoingTransfers(String senderId) {
    debugPrint('📤 [Transfer] Listening for outgoing transfers for: $senderId');
    return _db
        .collection(AppConstants.transfersCollection)
        .where('senderId', isEqualTo: senderId)
        .snapshots()
        .map((snap) {
          final list = snap.docs
              .map((d) => TransferModel.fromMap(d.data()))
              .toList();
          // Local sort by createdAt descending to avoid composite index requirement
          list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return list;
        });
  }

  // ─── Stream for a single transfer (real-time progress) ───────────────────
  Stream<TransferModel?> transferStream(String transferId) {
    return _db
        .collection(AppConstants.transfersCollection)
        .doc(transferId)
        .snapshots()
        .map((snap) {
          if (!snap.exists) return null;
          return TransferModel.fromMap(snap.data()!);
        });
  }

  // ─── Pick files, validate sizes, send ─────────────────────────────────────
  /// [onProgress] receives (fileIndex, totalFiles, bytesUploaded, totalBytes)
  Future<TransferModel> sendFiles({
    required UserModel sender,
    required UserModel receiver,
    required List<PlatformFile> files,
    required Function(int, int, int, int) onProgress,
  }) async {
    debugPrint('📤 [Transfer] sendFiles called — ${files.length} file(s)');
    // Validate file sizes
    for (final f in files) {
      if ((f.size) > AppConstants.maxFileSizeBytes) {
        throw Exception(
          '${f.name} exceeds the 500 MB limit (${_formatBytes(f.size)})',
        );
      }
      if (f.size == 0) {
        throw Exception('${f.name} is a zero-byte file and cannot be sent.');
      }
    }

    final transferId = _uuid.v4();
    final now = DateTime.now();
    final expiresAt = now.add(
      const Duration(hours: AppConstants.transferTtlHours),
    );

    // Compute total bytes for aggregate progress
    final totalBytes = files.fold<int>(0, (total, f) => total + f.size);

    debugPrint('📤 [Transfer] Creating Firestore doc: $transferId');
    // Create transfer document in Firestore with 'uploading' status
    final transferRef = _db
        .collection(AppConstants.transfersCollection)
        .doc(transferId);

    await transferRef.set(
      TransferModel(
        transferId: transferId,
        senderId: sender.uid,
        receiverId: receiver.uid,
        senderCode: sender.shortCode,
        receiverCode: receiver.shortCode,
        files: [],
        status: TransferStatus.uploading,
        createdAt: now,
        expiresAt: expiresAt,
        totalBytes: totalBytes,
        transferredBytes: 0,
      ).toMap(),
    );

    _activeUploadTransferId = transferId;
    _uploadCancelRequested = false;

    final List<FileInfo> uploadedFiles = [];
    int bytesUploadedSoFar = 0;

    try {
      for (int i = 0; i < files.length; i++) {
        _throwIfUploadCancelled(transferId);

        final platformFile = files[i];
        debugPrint(
          '📤 [Transfer] Uploading file ${i + 1}/${files.length}: ${platformFile.name} (${_formatBytes(platformFile.size)})',
        );
        final file = File(platformFile.path!);

        // Hash the file as a stream so large uploads do not need to fit in memory.
        final hash = await sha256.bind(file.openRead()).first;
        _throwIfUploadCancelled(transferId);

        final storagePath = 'transfers/$transferId/${i}_${platformFile.name}';
        final ref = _storage.ref(storagePath);

        final uploadTask = ref.putFile(
          file,
          SettableMetadata(
            contentType: platformFile.extension != null
                ? _mimeFromExtension(platformFile.extension!)
                : 'application/octet-stream',
            customMetadata: {
              'transferId': transferId,
              'fileName': platformFile.name,
              'sha256': hash.toString(),
            },
          ),
        );

        _activeUploadTask = uploadTask;

        uploadTask.snapshotEvents.listen((snapshot) {
          final fileBytesUploaded = snapshot.bytesTransferred;
          final total = bytesUploadedSoFar + fileBytesUploaded;
          onProgress(i + 1, files.length, total, totalBytes);

          final progress = totalBytes > 0 ? total / totalBytes : 0.0;
          transferRef.update({
            'uploadProgress': progress,
            'transferredBytes': total,
          });
        });

        late final TaskSnapshot snapshot;
        try {
          snapshot = await uploadTask;
        } on FirebaseException catch (e) {
          if (_isUploadCancelled(transferId, e)) {
            throw TransferCancelledException('Upload cancelled by user.');
          }
          rethrow;
        } finally {
          if (_activeUploadTransferId == transferId) {
            _activeUploadTask = null;
          }
        }

        _throwIfUploadCancelled(transferId);

        final downloadUrl = await snapshot.ref.getDownloadURL();

        bytesUploadedSoFar += platformFile.size;

        uploadedFiles.add(
          FileInfo(
            name: platformFile.name,
            mimeType: platformFile.extension != null
                ? _mimeFromExtension(platformFile.extension!)
                : 'application/octet-stream',
            sizeBytes: platformFile.size,
            downloadUrl: downloadUrl,
            storagePath: storagePath,
            sha256Hash: hash.toString(),
          ),
        );

        await transferRef.update({
          'files': uploadedFiles.map((f) => f.toMap()).toList(),
          'uploadProgress': bytesUploadedSoFar / totalBytes,
          'transferredBytes': bytesUploadedSoFar,
        });
      }

      debugPrint('✅ [Transfer] All files uploaded. Status → uploaded');
      await transferRef.update({
        'status': AppConstants.statusUploaded,
        'uploadProgress': 1.0,
        'transferredBytes': totalBytes,
        'errorMessage': null,
      });

      final finalDoc = await transferRef.get();
      return TransferModel.fromMap(finalDoc.data()!);
    } catch (e) {
      if (_isUploadCancelled(transferId, e)) {
        for (final file in uploadedFiles) {
          final storagePath = file.storagePath;
          if (storagePath == null) continue;
          try {
            await _storage.ref(storagePath).delete();
          } catch (_) {}
        }

        await transferRef.update({
          'status': AppConstants.statusFailed,
          'files': <Map<String, dynamic>>[],
          'uploadProgress': 0.0,
          'transferredBytes': 0,
          'errorMessage': 'Upload cancelled by user.',
        });
        throw TransferCancelledException('Upload cancelled by user.');
      }

      await transferRef.update({
        'status': AppConstants.statusFailed,
        'errorMessage': e.toString(),
      });
      rethrow;
    } finally {
      if (_activeUploadTransferId == transferId) {
        _activeUploadTask = null;
        _activeUploadTransferId = null;
        _uploadCancelRequested = false;
      }
    }
  }

  // ─── Download a transfer ──────────────────────────────────────────────────
  /// [onProgress] receives (fileIndex, totalFiles, bytesDownloaded, totalBytes)
  Future<List<String>> downloadTransfer({
    required TransferModel transfer,
    required Function(int, int, int, int) onProgress,
    String? customPath,
  }) async {
    final transferRef = _db
        .collection(AppConstants.transfersCollection)
        .doc(transfer.transferId);

    await transferRef.update({'status': AppConstants.statusDownloading});

    final String basePath =
        customPath ?? (await getApplicationDocumentsDirectory()).path;
    final transferDir = Directory('$basePath/FluxDrop/${transfer.transferId}');

    try {
      await transferDir.create(recursive: true);
    } catch (e) {
      // If we can't create the directory, we fail early
      await transferRef.update({
        'status': AppConstants.statusUploaded,
        'downloadProgress': 0.0,
      });
      throw Exception(
        'Could not create download directory. Please try a different location.',
      );
    }

    final List<String> savedPaths = [];
    int bytesDownloadedSoFar = 0;
    final totalBytes = transfer.totalBytes > 0
        ? transfer.totalBytes
        : transfer.files.fold<int>(0, (s, f) => s + f.sizeBytes);

    if (!await _hasEnoughStorage(totalBytes)) {
      await transferRef.update({
        'status': AppConstants.statusUploaded,
        'downloadProgress': 0.0,
      });
      throw Exception('Insufficient storage space to download these files.');
    }

    try {
      int failures = 0;
      for (int i = 0; i < transfer.files.length; i++) {
        _throwIfDownloadCancelled(transfer.transferId);

        final fileInfo = transfer.files[i];
        final savePath = '${transferDir.path}/${fileInfo.name}';

        // Handle filename conflicts
        final resolvedPath = _resolveConflict(savePath);
        final saveFile = File(resolvedPath);

        try {
          final ref = _storage.ref(fileInfo.storagePath!);
          final downloadTask = ref.writeToFile(saveFile);
          _activeDownloadTasks[transfer.transferId] = downloadTask;

          downloadTask.snapshotEvents.listen((snapshot) {
            final fileBytesDownloaded = snapshot.bytesTransferred;
            final total = bytesDownloadedSoFar + fileBytesDownloaded;
            onProgress(i + 1, transfer.files.length, total, totalBytes);

            final progress = totalBytes > 0 ? total / totalBytes : 0.0;
            transferRef.update({'downloadProgress': progress});
          });

          try {
            await downloadTask;
          } on FirebaseException catch (e) {
            if (_isDownloadCancelled(transfer.transferId, e)) {
              throw TransferCancelledException('Download cancelled by user.');
            }
            rethrow;
          } finally {
            _activeDownloadTasks.remove(transfer.transferId);
          }

          _throwIfDownloadCancelled(transfer.transferId);

          // Verify SHA-256 hash
          final downloadedBytes = await saveFile.readAsBytes();
          final computedHash = sha256.convert(downloadedBytes).toString();
          if (fileInfo.sha256Hash.isNotEmpty &&
              computedHash != fileInfo.sha256Hash) {
            await saveFile.delete();
            throw Exception(
              'Integrity check failed for ${fileInfo.name}. File may be corrupted.',
            );
          }

          bytesDownloadedSoFar += fileInfo.sizeBytes;
          savedPaths.add(resolvedPath);
        } catch (e) {
          if (_isDownloadCancelled(transfer.transferId, e)) {
            rethrow;
          }
          debugPrint('❌ [Transfer] Failed to download ${fileInfo.name}: $e');
          failures++;
          // Do NOT rethrow; continue to next file
        }
      }

      if (failures == transfer.files.length) {
        throw Exception('All files failed to download.');
      } else if (failures > 0) {
        debugPrint('⚠️ [Transfer] $failures file(s) failed to download.');
      }

      final completedProgress = totalBytes > 0
          ? bytesDownloadedSoFar / totalBytes
          : (savedPaths.isNotEmpty ? 1.0 : 0.0);

      // Mark as completed
      await transferRef.update({
        'status': AppConstants.statusCompleted,
        'downloadProgress': completedProgress,
        'errorMessage': failures > 0
            ? '$failures file(s) failed to download.'
            : null,
      });

      return savedPaths;
    } catch (e) {
      final cancelled = _isDownloadCancelled(transfer.transferId, e);

      if (cancelled) {
        try {
          if (await transferDir.exists()) {
            await transferDir.delete(recursive: true);
          }
        } catch (_) {}
      }

      // Revert status on failure
      await transferRef.update({
        'status': AppConstants.statusUploaded,
        'downloadProgress': 0.0,
        'errorMessage': cancelled
            ? 'Download cancelled by user.'
            : e.toString(),
      });

      _activeDownloadTasks.remove(transfer.transferId);
      _downloadCancelRequested.remove(transfer.transferId);

      if (cancelled) {
        throw TransferCancelledException('Download cancelled by user.');
      }

      if (e.toString().contains('Operation not permitted')) {
        throw Exception(
          'Android Storage Restriction: The selected folder is restricted. '
          'Please try a different folder or use the Default location.',
        );
      }
      rethrow;
    } finally {
      _activeDownloadTasks.remove(transfer.transferId);
      _downloadCancelRequested.remove(transfer.transferId);
    }
  }

  // ─── Mark a transfer as expired (TTL cleanup) ─────────────────────────────
  Future<void> expireOldTransfers() async {
    try {
      final now = DateTime.now();
      final expired = await _db
          .collection(AppConstants.transfersCollection)
          .where(
            'status',
            whereIn: [AppConstants.statusPending, AppConstants.statusUploaded],
          )
          .where('expiresAt', isLessThan: Timestamp.fromDate(now))
          .get();

      for (final doc in expired.docs) {
        await doc.reference.update({'status': AppConstants.statusExpired});
      }
    } catch (e) {
      // Silently skip if Firestore index is not ready yet
      // Index is being built — will work automatically once complete
      debugPrint('expireOldTransfers skipped: $e');
    }
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────
  String _resolveConflict(String path) {
    final file = File(path);
    if (!file.existsSync()) return path;

    final dir = file.parent.path;
    final name = path.split('/').last.replaceAll(RegExp(r'\.[^.]+$'), '');
    final ext = path.contains('.') ? '.${path.split('.').last}' : '';

    int counter = 1;
    while (File('$dir/${name}_$counter$ext').existsSync()) {
      counter++;
    }
    return '$dir/${name}_$counter$ext';
  }

  String _mimeFromExtension(String ext) {
    switch (ext.toLowerCase()) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'mp4':
        return 'video/mp4';
      case 'mp3':
        return 'audio/mpeg';
      case 'pdf':
        return 'application/pdf';
      case 'doc':
      case 'docx':
        return 'application/msword';
      case 'zip':
        return 'application/zip';
      default:
        return 'application/octet-stream';
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  static String formatBytesStatic(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  bool _isUploadCancelled(String transferId, Object error) {
    if (_uploadCancelRequested && _activeUploadTransferId == transferId) {
      return true;
    }
    if (error is TransferCancelledException) {
      return true;
    }
    return error is FirebaseException && error.code == 'canceled';
  }

  bool _isDownloadCancelled(String transferId, Object error) {
    if (_downloadCancelRequested.contains(transferId)) {
      return true;
    }
    if (error is TransferCancelledException) {
      return true;
    }
    return error is FirebaseException && error.code == 'canceled';
  }

  void _throwIfUploadCancelled(String transferId) {
    if (_uploadCancelRequested && _activeUploadTransferId == transferId) {
      throw TransferCancelledException('Upload cancelled by user.');
    }
  }

  void _throwIfDownloadCancelled(String transferId) {
    if (_downloadCancelRequested.contains(transferId)) {
      throw TransferCancelledException('Download cancelled by user.');
    }
  }
}
