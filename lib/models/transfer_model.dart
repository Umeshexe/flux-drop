import 'package:cloud_firestore/cloud_firestore.dart';

enum TransferStatus {
  pending,
  uploading,
  uploaded,
  downloading,
  completed,
  failed,
  expired,
  rejected,
}

class FileInfo {
  final String name;
  final String mimeType;
  final int sizeBytes;
  final String? downloadUrl;
  final String? storagePath;
  final String sha256Hash;

  FileInfo({
    required this.name,
    required this.mimeType,
    required this.sizeBytes,
    this.downloadUrl,
    this.storagePath,
    required this.sha256Hash,
  });

  Map<String, dynamic> toMap() => {
        'name': name,
        'mimeType': mimeType,
        'sizeBytes': sizeBytes,
        'downloadUrl': downloadUrl,
        'storagePath': storagePath,
        'sha256Hash': sha256Hash,
      };

  factory FileInfo.fromMap(Map<String, dynamic> map) => FileInfo(
        name: map['name'] as String,
        mimeType: map['mimeType'] as String? ?? 'application/octet-stream',
        sizeBytes: (map['sizeBytes'] as num).toInt(),
        downloadUrl: map['downloadUrl'] as String?,
        storagePath: map['storagePath'] as String?,
        sha256Hash: map['sha256Hash'] as String? ?? '',
      );
}

class TransferModel {
  final String transferId;
  final String senderId;
  final String receiverId;
  final String senderCode;
  final String receiverCode;
  final List<FileInfo> files;
  final TransferStatus status;
  final double uploadProgress; // 0.0 – 1.0 aggregate
  final double downloadProgress; // 0.0 – 1.0 aggregate
  final DateTime createdAt;
  final DateTime expiresAt; // TTL: createdAt + 24h
  final String? errorMessage;
  final int totalBytes;
  final int transferredBytes;
  // Nearby / LAN fast-path: sender's local TCP server endpoint
  final String? lanIp;
  final int? lanPort;

  TransferModel({
    required this.transferId,
    required this.senderId,
    required this.receiverId,
    required this.senderCode,
    required this.receiverCode,
    required this.files,
    required this.status,
    this.uploadProgress = 0.0,
    this.downloadProgress = 0.0,
    required this.createdAt,
    required this.expiresAt,
    this.errorMessage,
    this.totalBytes = 0,
    this.transferredBytes = 0,
    this.lanIp,
    this.lanPort,
  });

  static TransferStatus _statusFromString(String s) {
    switch (s) {
      case 'uploading':
        return TransferStatus.uploading;
      case 'uploaded':
        return TransferStatus.uploaded;
      case 'downloading':
        return TransferStatus.downloading;
      case 'completed':
        return TransferStatus.completed;
      case 'failed':
        return TransferStatus.failed;
      case 'expired':
        return TransferStatus.expired;
      case 'rejected':
        return TransferStatus.rejected;
      default:
        return TransferStatus.pending;
    }
  }

  static String _statusToString(TransferStatus s) {
    switch (s) {
      case TransferStatus.uploading:
        return 'uploading';
      case TransferStatus.uploaded:
        return 'uploaded';
      case TransferStatus.downloading:
        return 'downloading';
      case TransferStatus.completed:
        return 'completed';
      case TransferStatus.failed:
        return 'failed';
      case TransferStatus.expired:
        return 'expired';
      case TransferStatus.rejected:
        return 'rejected';
      default:
        return 'pending';
    }
  }

  Map<String, dynamic> toMap() => {
        'transferId': transferId,
        'senderId': senderId,
        'receiverId': receiverId,
        'senderCode': senderCode,
        'receiverCode': receiverCode,
        'files': files.map((f) => f.toMap()).toList(),
        'status': _statusToString(status),
        'uploadProgress': uploadProgress,
        'downloadProgress': downloadProgress,
        'createdAt': Timestamp.fromDate(createdAt),
        'expiresAt': Timestamp.fromDate(expiresAt),
        'errorMessage': errorMessage,
        'totalBytes': totalBytes,
        'transferredBytes': transferredBytes,
        if (lanIp != null) 'lanIp': lanIp,
        if (lanPort != null) 'lanPort': lanPort,
      };

  factory TransferModel.fromMap(Map<String, dynamic> map) => TransferModel(
        transferId: map['transferId'] as String,
        senderId: map['senderId'] as String,
        receiverId: map['receiverId'] as String,
        senderCode: map['senderCode'] as String? ?? '',
        receiverCode: map['receiverCode'] as String? ?? '',
        files: (map['files'] as List<dynamic>? ?? [])
            .map((f) => FileInfo.fromMap(f as Map<String, dynamic>))
            .toList(),
        status: _statusFromString(map['status'] as String? ?? 'pending'),
        uploadProgress: (map['uploadProgress'] as num?)?.toDouble() ?? 0.0,
        downloadProgress:
            (map['downloadProgress'] as num?)?.toDouble() ?? 0.0,
        createdAt: (map['createdAt'] as Timestamp).toDate(),
        expiresAt: (map['expiresAt'] as Timestamp).toDate(),
        errorMessage: map['errorMessage'] as String?,
        totalBytes: (map['totalBytes'] as num?)?.toInt() ?? 0,
        transferredBytes: (map['transferredBytes'] as num?)?.toInt() ?? 0,
        lanIp: map['lanIp'] as String?,
        lanPort: (map['lanPort'] as num?)?.toInt(),
      );

  TransferModel copyWith({
    TransferStatus? status,
    double? uploadProgress,
    double? downloadProgress,
    List<FileInfo>? files,
    String? errorMessage,
    int? transferredBytes,
    String? lanIp,
    int? lanPort,
  }) =>
      TransferModel(
        transferId: transferId,
        senderId: senderId,
        receiverId: receiverId,
        senderCode: senderCode,
        receiverCode: receiverCode,
        files: files ?? this.files,
        status: status ?? this.status,
        uploadProgress: uploadProgress ?? this.uploadProgress,
        downloadProgress: downloadProgress ?? this.downloadProgress,
        createdAt: createdAt,
        expiresAt: expiresAt,
        errorMessage: errorMessage ?? this.errorMessage,
        totalBytes: totalBytes,
        transferredBytes: transferredBytes ?? this.transferredBytes,
        lanIp: lanIp ?? this.lanIp,
        lanPort: lanPort ?? this.lanPort,
      );
}
