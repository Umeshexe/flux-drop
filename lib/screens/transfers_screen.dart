import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/theme.dart';
import '../models/transfer_model.dart';
import '../models/user_model.dart';
import '../services/notification_service.dart';
import '../services/transfer_service.dart';

class TransfersScreen extends StatefulWidget {
  final UserModel user;
  const TransfersScreen({super.key, required this.user});

  @override
  State<TransfersScreen> createState() => _TransfersScreenState();
}

class _TransfersScreenState extends State<TransfersScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _transferService = TransferService();
  late final Stream<List<TransferModel>> _incomingStream = _transferService
      .incomingTransfers(widget.user.uid);
  late final Stream<List<TransferModel>> _outgoingStream = _transferService
      .outgoingTransfers(widget.user.uid);

  // Track active downloads to show progress
  final Map<String, _DownloadProgress> _activeDownloads = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _downloadTransfer(TransferModel transfer) async {
    if (_activeDownloads.containsKey(transfer.transferId)) return;

    // On Android: check if user has set a default save path in Settings
    String? customPath;
    if (Platform.isAndroid) {
      final prefs = await SharedPreferences.getInstance();
      customPath = prefs.getString('defaultSavePath');
    }

    setState(() {
      _activeDownloads[transfer.transferId] = _DownloadProgress(
        currentFile: 0,
        totalFiles: transfer.files.length,
        bytesTransferred: 0,
        totalBytes: transfer.totalBytes,
      );
    });

    try {
      final paths = await _transferService.downloadTransfer(
        transfer: transfer,
        customPath: customPath,
        onProgress: (fileIndex, totalFiles, bytesDownloaded, totalBytes) {
          if (mounted) {
            setState(() {
              _activeDownloads[transfer.transferId] = _DownloadProgress(
                currentFile: fileIndex,
                totalFiles: totalFiles,
                bytesTransferred: bytesDownloaded,
                totalBytes: totalBytes,
              );
            });
          }
        },
      );

      setState(() => _activeDownloads.remove(transfer.transferId));

      await NotificationService().showLocalNotification(
        title: '✅ Download Complete',
        body:
            '${transfer.files.length} file(s) from ${transfer.senderCode} saved',
      );

      if (mounted && paths.isNotEmpty) {
        final partialFailure = paths.length < transfer.files.length;
        _showSavedSheet(paths, transfer, customPath: customPath);

        if (partialFailure) {
          Fluttertoast.showToast(
            msg:
                'Downloaded ${paths.length}/${transfer.files.length} files. Some files failed.',
            backgroundColor: AppTheme.warning,
            textColor: Colors.white,
            toastLength: Toast.LENGTH_LONG,
          );
        }
      }
    } catch (e) {
      setState(() => _activeDownloads.remove(transfer.transferId));
      Fluttertoast.showToast(
        msg: e is TransferCancelledException
            ? e.toString()
            : 'Download failed: ${e.toString()}',
        backgroundColor: e is TransferCancelledException
            ? AppTheme.warning
            : AppTheme.error,
        textColor: Colors.white,
        toastLength: Toast.LENGTH_LONG,
      );
    }
  }

  Future<void> _cancelDownload(TransferModel transfer) async {
    final cancelled = await _transferService.cancelDownload(
      transfer.transferId,
    );
    if (!cancelled) {
      Fluttertoast.showToast(
        msg: 'No active download to cancel',
        backgroundColor: AppTheme.error,
        textColor: Colors.white,
        toastLength: Toast.LENGTH_LONG,
      );
    }
  }

  Future<void> _cancelOutgoingUpload(TransferModel transfer) async {
    final cancelled = await _transferService.cancelUpload(transfer.transferId);
    if (!cancelled) {
      Fluttertoast.showToast(
        msg: 'No active upload to cancel',
        backgroundColor: AppTheme.error,
        textColor: Colors.white,
        toastLength: Toast.LENGTH_LONG,
      );
    }
  }

  void _declineTransfer(TransferModel transfer) {
    FirebaseFirestore.instance
        .collection('transfers')
        .doc(transfer.transferId)
        .update({'status': 'rejected'});
  }

  void _showSavedSheet(
    List<String> paths,
    TransferModel transfer, {
    String? customPath,
  }) {
    FocusScope.of(context).unfocus();
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    gradient: AppTheme.successGradient,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.download_done_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Text(
                  'Files Saved',
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...paths.map(
              (p) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    const Icon(
                      Icons.check_rounded,
                      color: AppTheme.success,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        p.split('/').last,
                        style: Theme.of(context).textTheme.bodyMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Saved to: ${_savedLocationLabel(paths, customPath: customPath)}',
              style: Theme.of(
                context,
              ).textTheme.bodySmall!.copyWith(color: AppTheme.textMuted),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _shareDownloadedFiles(paths),
                icon: const Icon(Icons.ios_share_rounded),
                label: Text(
                  Platform.isIOS
                      ? 'Save / Share Elsewhere'
                      : 'Share / Save Elsewhere',
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Done'),
              ),
            ),
          ],
        ),
      ),
    ).then((_) {
      // Ensure keyboard never reopens after sheet is dismissed
      FocusManager.instance.primaryFocus?.unfocus();
    });
  }

  Future<void> _shareDownloadedFiles(List<String> paths) async {
    if (paths.isEmpty) return;

    try {
      final size = MediaQuery.of(context).size;
      await Share.shareXFiles(
        paths.map((path) => XFile(path)).toList(),
        sharePositionOrigin: Rect.fromLTWH(0, 0, size.width, size.height / 2),
      );
    } catch (e) {
      Fluttertoast.showToast(
        msg: 'Could not open share sheet: $e',
        backgroundColor: AppTheme.error,
        textColor: Colors.white,
        toastLength: Toast.LENGTH_LONG,
      );
    }
  }

  String _savedLocationLabel(List<String> paths, {String? customPath}) {
    if (customPath != null) {
      return customPath;
    }
    if (paths.isEmpty) {
      return 'FluxDrop folder';
    }
    return paths.first
        .split('/')
        .reversed
        .skip(1)
        .take(2)
        .toList()
        .reversed
        .join('/');
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Transfers',
                style: Theme.of(context).textTheme.displayMedium,
              ),
              const SizedBox(height: 4),
              Text(
                'Incoming and outgoing file transfers',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),
              // Tab bar
              Container(
                decoration: BoxDecoration(
                  color: AppTheme.bgCardElevated,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TabBar(
                  controller: _tabController,
                  indicator: BoxDecoration(
                    gradient: AppTheme.accentGradient,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  labelColor: Colors.white,
                  unselectedLabelColor: AppTheme.textMuted,
                  labelStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  indicatorSize: TabBarIndicatorSize.tab,
                  dividerColor: Colors.transparent,
                  tabs: const [
                    Tab(text: '  Incoming  '),
                    Tab(text: '  Outgoing  '),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Tab content
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              // Incoming
              _buildIncomingList(),
              // Outgoing
              _buildOutgoingList(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildIncomingList() {
    return StreamBuilder<List<TransferModel>>(
      stream: _incomingStream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: AppTheme.accent),
          );
        }
        if (snap.hasError) {
          final err = snap.error.toString();
          // Index still building — show spinner instead of ugly error
          if (err.contains('failed-precondition') || err.contains('index')) {
            return _buildEmptyState(
              icon: Icons.hourglass_top_rounded,
              title: 'Setting things up...',
              subtitle: 'Database indexing in progress. Ready in ~1 min.',
            );
          }
          return _buildEmptyState(
            icon: Icons.inbox_rounded,
            title: 'No incoming transfers',
            subtitle: 'Share your code to receive files',
          );
        }
        final transfers = snap.data ?? [];
        if (transfers.isEmpty) {
          return _buildEmptyState(
            icon: Icons.inbox_rounded,
            title: 'No incoming transfers',
            subtitle: 'Share your code to receive files',
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          itemCount: transfers.length,
          itemBuilder: (_, i) => _TransferCard(
            transfer: transfers[i],
            isIncoming: true,
            downloadProgress: _activeDownloads[transfers[i].transferId],
            onDownload: () => _downloadTransfer(transfers[i]),
            onDecline: () => _declineTransfer(transfers[i]),
            onCancel: () => _cancelDownload(transfers[i]),
          ),
        );
      },
    );
  }

  Widget _buildOutgoingList() {
    return StreamBuilder<List<TransferModel>>(
      stream: _outgoingStream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: AppTheme.accent),
          );
        }
        if (snap.hasError) {
          final err = snap.error.toString();
          // Index still building — show spinner instead of ugly error
          if (err.contains('failed-precondition') || err.contains('index')) {
            return _buildEmptyState(
              icon: Icons.hourglass_top_rounded,
              title: 'Setting things up...',
              subtitle: 'Database indexing in progress. Ready in ~1 min.',
            );
          }
          return _buildEmptyState(
            icon: Icons.upload_rounded,
            title: 'No outgoing transfers',
            subtitle: 'Send files to another device',
          );
        }
        final transfers = snap.data ?? [];
        if (transfers.isEmpty) {
          return _buildEmptyState(
            icon: Icons.upload_rounded,
            title: 'No outgoing transfers',
            subtitle: 'Send files to another device',
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
          itemCount: transfers.length,
          itemBuilder: (_, i) => _TransferCard(
            transfer: transfers[i],
            isIncoming: false,
            downloadProgress: null,
            onDownload: null,
            onDecline: null,
            onCancel: () => _cancelOutgoingUpload(transfers[i]),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppTheme.bgCardElevated,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: AppTheme.textMuted, size: 32),
          ),
          const SizedBox(height: 16),
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 6),
          Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

// ─── Transfer Card ────────────────────────────────────────────────────────────

class _DownloadProgress {
  final int currentFile;
  final int totalFiles;
  final int bytesTransferred;
  final int totalBytes;

  _DownloadProgress({
    required this.currentFile,
    required this.totalFiles,
    required this.bytesTransferred,
    required this.totalBytes,
  });
}

class _TransferCard extends StatelessWidget {
  final TransferModel transfer;
  final bool isIncoming;
  final _DownloadProgress? downloadProgress;
  final VoidCallback? onDownload;
  final VoidCallback? onDecline;
  final VoidCallback? onCancel;

  const _TransferCard({
    required this.transfer,
    required this.isIncoming,
    required this.downloadProgress,
    required this.onDownload,
    required this.onDecline,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final isDownloading = downloadProgress != null;
    final isExpired = transfer.status == TransferStatus.expired;
    final isCompleted = transfer.status == TransferStatus.completed;
    final isFailed = transfer.status == TransferStatus.failed;
    final statusText = _statusText(isIncoming, transfer.status);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isCompleted
              ? AppTheme.success.withAlpha(60)
              : isFailed || isExpired
              ? AppTheme.error.withAlpha(60)
              : AppTheme.border,
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header row
                Row(
                  children: [
                    _StatusIcon(status: transfer.status),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isIncoming
                                ? 'From: ${transfer.senderCode}'
                                : 'To: ${transfer.receiverCode}',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          Text(
                            _formatDate(transfer.createdAt),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    _StatusBadge(
                      status: transfer.status,
                      isIncoming: isIncoming,
                    ),
                  ],
                ),

                // Files list
                if (transfer.files.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  ...transfer.files
                      .take(3)
                      .map(
                        (f) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.insert_drive_file_rounded,
                                size: 14,
                                color: AppTheme.textMuted,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  f.name,
                                  style: Theme.of(context).textTheme.bodySmall,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Text(
                                TransferService.formatBytesStatic(f.sizeBytes),
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ),
                  if (transfer.files.length > 3)
                    Text(
                      '+ ${transfer.files.length - 3} more file(s)',
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall!.copyWith(color: AppTheme.accent),
                    ),
                ],

                // TTL warning for pending transfers
                if (transfer.status == TransferStatus.uploaded &&
                    isIncoming &&
                    !isDownloading) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.warning.withAlpha(30),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.timer_outlined,
                          size: 14,
                          color: AppTheme.warning,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Expires: ${_formatExpiry(transfer.expiresAt)}',
                          style: Theme.of(context).textTheme.bodySmall!
                              .copyWith(color: AppTheme.warning),
                        ),
                      ],
                    ),
                  ),
                ],

                if (isExpired) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.errorGlow,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.error_outline,
                          size: 14,
                          color: AppTheme.error,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'This transfer has expired (24h TTL)',
                          style: Theme.of(context).textTheme.bodySmall!
                              .copyWith(color: AppTheme.error),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Progress bar (receiver downloading)
          if (isDownloading && downloadProgress != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isIncoming
                        ? 'Downloading file ${downloadProgress!.currentFile} of ${downloadProgress!.totalFiles}...'
                        : 'Receiver is downloading the files...',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: downloadProgress!.totalBytes > 0
                          ? downloadProgress!.bytesTransferred /
                                downloadProgress!.totalBytes
                          : null,
                      backgroundColor: AppTheme.bgCardElevated,
                      color: AppTheme.success,
                      minHeight: 6,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: onCancel,
                      icon: const Icon(Icons.close_rounded, size: 18),
                      label: const Text('Cancel Download'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.error,
                        side: const BorderSide(color: AppTheme.error),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Receiver-side: sender is still uploading — show live progress
          if (isIncoming && transfer.status == TransferStatus.uploading) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const SizedBox(
                        width: 10,
                        height: 10,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppTheme.accent,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Receiving… ${(transfer.uploadProgress * 100).toStringAsFixed(0)}%',
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall!.copyWith(color: AppTheme.accent),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: transfer.uploadProgress > 0
                          ? transfer.uploadProgress
                          : null,
                      backgroundColor: AppTheme.bgCardElevated,
                      color: AppTheme.accent,
                      minHeight: 6,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Download will be available once upload completes',
                    style: Theme.of(context).textTheme.bodySmall!.copyWith(
                      fontSize: 10,
                      color: AppTheme.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Upload progress (sender side only)
          if (!isIncoming &&
              transfer.status == TransferStatus.uploading &&
              transfer.uploadProgress < 1.0) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$statusText ${(transfer.uploadProgress * 100).toStringAsFixed(1)}%',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: transfer.uploadProgress,
                      backgroundColor: AppTheme.bgCardElevated,
                      color: AppTheme.accent,
                      minHeight: 6,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: onCancel,
                      icon: const Icon(Icons.close_rounded, size: 18),
                      label: const Text('Cancel Upload'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.error,
                        side: const BorderSide(color: AppTheme.error),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Download button (for incoming uploaded or completed)
          if (isIncoming &&
              (transfer.status == TransferStatus.uploaded ||
                  transfer.status == TransferStatus.completed) &&
              !isDownloading) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                children: [
                  if (transfer.status == TransferStatus.uploaded) ...[
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: onDecline,
                        icon: const Icon(Icons.close_rounded, size: 18),
                        label: const Text('Decline'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppTheme.error,
                          side: const BorderSide(color: AppTheme.error),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: onDownload,
                      icon: Icon(
                        isCompleted
                            ? Icons.replay_rounded
                            : Icons.check_circle_rounded,
                        size: 18,
                      ),
                      label: Text(isCompleted ? 'Download Again' : 'Accept'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.success,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  String _formatExpiry(DateTime expiresAt) {
    final diff = expiresAt.difference(DateTime.now());
    if (diff.isNegative) return 'Expired';
    if (diff.inHours > 0) return 'in ${diff.inHours}h ${diff.inMinutes % 60}m';
    return 'in ${diff.inMinutes}m';
  }

  String _statusText(bool isIncoming, TransferStatus status) {
    if (isIncoming) {
      switch (status) {
        case TransferStatus.uploading:
          return 'Receiving';
        case TransferStatus.uploaded:
          return 'Ready to accept';
        case TransferStatus.downloading:
          return 'Downloading';
        case TransferStatus.completed:
          return 'Download complete';
        case TransferStatus.rejected:
          return 'Declined';
        default:
          return 'Pending';
      }
    }

    switch (status) {
      case TransferStatus.uploading:
        return 'Uploading...';
      case TransferStatus.uploaded:
        return 'Waiting for receiver';
      case TransferStatus.downloading:
        return 'Receiver downloading';
      case TransferStatus.completed:
        return 'Received';
      case TransferStatus.rejected:
        return 'Declined';
      default:
        return 'Pending';
    }
  }
}

class _StatusIcon extends StatelessWidget {
  final TransferStatus status;
  const _StatusIcon({required this.status});

  @override
  Widget build(BuildContext context) {
    Color color;
    IconData icon;
    switch (status) {
      case TransferStatus.completed:
        color = AppTheme.success;
        icon = Icons.check_circle_rounded;
      case TransferStatus.uploading:
      case TransferStatus.downloading:
        color = AppTheme.accent;
        icon = Icons.sync_rounded;
      case TransferStatus.failed:
        color = AppTheme.error;
        icon = Icons.error_rounded;
      case TransferStatus.expired:
        color = AppTheme.error;
        icon = Icons.timer_off_rounded;
      case TransferStatus.rejected:
        color = AppTheme.error;
        icon = Icons.block_rounded;
      default:
        color = AppTheme.warning;
        icon = Icons.schedule_rounded;
    }
    return Icon(icon, color: color, size: 22);
  }
}

class _StatusBadge extends StatelessWidget {
  final TransferStatus status;
  final bool isIncoming;
  const _StatusBadge({required this.status, required this.isIncoming});

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    String label;
    switch (status) {
      case TransferStatus.completed:
        bg = AppTheme.successGlow;
        fg = AppTheme.success;
        label = isIncoming ? 'Done' : 'Received';
      case TransferStatus.uploading:
        bg = AppTheme.accentGlow;
        fg = AppTheme.accent;
        label = isIncoming ? 'Receiving' : 'Uploading';
      case TransferStatus.uploaded:
        bg = AppTheme.warning.withAlpha(30);
        fg = AppTheme.warning;
        label = isIncoming ? 'Ready' : 'Waiting';
      case TransferStatus.downloading:
        bg = AppTheme.successGlow;
        fg = AppTheme.success;
        label = isIncoming ? 'Downloading' : 'Receiving';
      case TransferStatus.failed:
        bg = AppTheme.errorGlow;
        fg = AppTheme.error;
        label = 'Failed';
      case TransferStatus.expired:
        bg = AppTheme.errorGlow;
        fg = AppTheme.error;
        label = 'Expired';
      case TransferStatus.rejected:
        bg = AppTheme.errorGlow;
        fg = AppTheme.error;
        label = 'Rejected';
      default:
        bg = AppTheme.bgCardElevated;
        fg = AppTheme.textMuted;
        label = 'Pending';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg),
      ),
    );
  }
}
