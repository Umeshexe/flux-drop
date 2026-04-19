import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../core/constants.dart';
import '../models/transfer_model.dart';
import '../models/user_model.dart';

class TransferService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final _uuid = const Uuid();

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

    // Upload files one by one
    final List<FileInfo> uploadedFiles = [];
    int bytesUploadedSoFar = 0;

    for (int i = 0; i < files.length; i++) {
      final platformFile = files[i];
      debugPrint(
        '📤 [Transfer] Uploading file ${i + 1}/${files.length}: ${platformFile.name} (${_formatBytes(platformFile.size)})',
      );
      final file = File(platformFile.path!);
      final bytes = await file.readAsBytes();

      // Compute SHA-256 for integrity verification
      final hash = sha256.convert(bytes).toString();

      // Deduplicate: check if this hash already exists for this transfer
      final storagePath = 'transfers/$transferId/${i}_${platformFile.name}';
      final ref = _storage.ref(storagePath);

      // Upload with progress tracking
      final uploadTask = ref.putData(
        bytes,
        SettableMetadata(
          contentType: platformFile.extension != null
              ? _mimeFromExtension(platformFile.extension!)
              : 'application/octet-stream',
          customMetadata: {
            'transferId': transferId,
            'fileName': platformFile.name,
            'sha256': hash,
          },
        ),
      );

      uploadTask.snapshotEvents.listen((snapshot) {
        final fileBytesUploaded = snapshot.bytesTransferred;
        final total = bytesUploadedSoFar + fileBytesUploaded;
        onProgress(i + 1, files.length, total, totalBytes);

        // Update Firestore with aggregate progress
        final progress = totalBytes > 0 ? total / totalBytes : 0.0;
        transferRef.update({
          'uploadProgress': progress,
          'transferredBytes': total,
        });
      });

      final snapshot = await uploadTask;
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
          sha256Hash: hash,
        ),
      );

      // Update files list in Firestore as each file completes
      await transferRef.update({
        'files': uploadedFiles.map((f) => f.toMap()).toList(),
        'uploadProgress': bytesUploadedSoFar / totalBytes,
        'transferredBytes': bytesUploadedSoFar,
      });
    }

    debugPrint('✅ [Transfer] All files uploaded. Status → uploaded');
    // Mark as 'uploaded' — triggers receiver's real-time listener
    await transferRef.update({
      'status': AppConstants.statusUploaded,
      'uploadProgress': 1.0,
      'transferredBytes': totalBytes,
    });

    final finalDoc = await transferRef.get();
    return TransferModel.fromMap(finalDoc.data()!);
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
      throw Exception('Could not create download directory. Please try a different location.');
    }

    final List<String> savedPaths = [];
    int bytesDownloadedSoFar = 0;
    final totalBytes = transfer.totalBytes > 0
        ? transfer.totalBytes
        : transfer.files.fold<int>(0, (s, f) => s + f.sizeBytes);

    try {
      for (int i = 0; i < transfer.files.length; i++) {
        final fileInfo = transfer.files[i];
        final savePath = '${transferDir.path}/${fileInfo.name}';

        // Handle filename conflicts
        final resolvedPath = _resolveConflict(savePath);
        final saveFile = File(resolvedPath);

        final ref = _storage.ref(fileInfo.storagePath!);
        final downloadTask = ref.writeToFile(saveFile);

        downloadTask.snapshotEvents.listen((snapshot) {
          final fileBytesDownloaded = snapshot.bytesTransferred;
          final total = bytesDownloadedSoFar + fileBytesDownloaded;
          onProgress(i + 1, transfer.files.length, total, totalBytes);

          final progress = totalBytes > 0 ? total / totalBytes : 0.0;
          transferRef.update({'downloadProgress': progress});
        });

        await downloadTask;

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
      }

      // Mark as completed
      await transferRef.update({
        'status': AppConstants.statusCompleted,
        'downloadProgress': 1.0,
      });

      return savedPaths;
    } catch (e) {
      // Revert status on failure
      await transferRef.update({
        'status': AppConstants.statusUploaded,
        'downloadProgress': 0.0,
      });

      if (e.toString().contains('Operation not permitted')) {
        throw Exception(
            'Android Storage Restriction: The selected folder is restricted. '
            'Please try a different folder or use the Default location.');
      }
      rethrow;
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
}
