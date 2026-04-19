import 'dart:io';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';

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
        // Native Share Sheet on both iOS and Android
        final size = MediaQuery.of(context).size;
        final result = await Share.shareXFiles(
          paths.map((p) => XFile(p)).toList(),
          sharePositionOrigin: Rect.fromLTWH(0, 0, size.width, size.height / 2),
        );

        // Always delete the temp file from app's private storage after Share Sheet closes.
        // User either saved it to their preferred location, or dismissed (in which case
        // we revert so they can try again). Either way, temp copy is no longer needed.
        for (final p in paths) {
          try { await File(p).delete(); } catch (_) {}
        }
        // Also try to clean up the parent transfer dir (if empty)
        if (paths.isNotEmpty) {
          try {
            final parentDir = Directory(paths.first).parent;
            if (await parentDir.exists()) await parentDir.delete(recursive: true);
          } catch (_) {}
        }

        if (result.status == ShareResultStatus.dismissed && mounted) {
          // User dismissed — revert status so they can download again
          Fluttertoast.showToast(
            msg: 'Dismissed. Tap "Download Again" to retry.',
            backgroundColor: AppTheme.bgCard,
            textColor: Colors.white,
            toastLength: Toast.LENGTH_LONG,
          );
        }
      }
    } catch (e) {
      setState(() => _activeDownloads.remove(transfer.transferId));
      Fluttertoast.showToast(
        msg: 'Download failed: ${e.toString()}',
        backgroundColor: AppTheme.error,
        textColor: Colors.white,
        toastLength: Toast.LENGTH_LONG,
      );
    }
  }

  Future<String?> _showDownloadOptionsSheet() {
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Download Location',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Where would you like to save these files?',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            ListTile(
              leading: const Icon(Icons.folder_shared_rounded,
                  color: AppTheme.accent),
              title: const Text('Default Private Folder'),
              subtitle: Text(Platform.isIOS ? 'Access via "Files" app > On My iPhone > FluxDrop' : 'Safe, app-internal storage'),
              onTap: () => Navigator.pop(context, 'default'),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            if (!Platform.isIOS) ...[
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.folder_open_rounded,
                    color: AppTheme.warning),
                title: const Text('Choose Custom Folder'),
                subtitle: const Text('Pick a folder (e.g., Downloads, Documents)'),
                onTap: () => Navigator.pop(context, 'custom'),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ],
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }


  void _showSavedSheet(List<String> paths, TransferModel transfer) {
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
              'Saved to: ${paths.isNotEmpty ? paths.first.split('/').reversed.skip(1).take(2).toList().reversed.join('/') : 'FluxDrop folder'}',
              style: Theme.of(
                context,
              ).textTheme.bodySmall!.copyWith(color: AppTheme.textMuted),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Done'),
              ),
            ),
          ],
        ),
      ),
    );
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

  const _TransferCard({
    required this.transfer,
    required this.isIncoming,
    required this.downloadProgress,
    required this.onDownload,
  });

  @override
  Widget build(BuildContext context) {
    final isDownloading = downloadProgress != null;
    final isExpired = transfer.status == TransferStatus.expired;
    final isCompleted = transfer.status == TransferStatus.completed;
    final isFailed = transfer.status == TransferStatus.failed;

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
                    _StatusBadge(status: transfer.status),
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

          // Progress bar
          if (isDownloading && downloadProgress != null) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Downloading file ${downloadProgress!.currentFile} of ${downloadProgress!.totalFiles}...',
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
                ],
              ),
            ),
          ],

          // Upload progress (for outgoing)
          if (transfer.status == TransferStatus.uploading &&
              transfer.uploadProgress < 1.0) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Uploading... ${(transfer.uploadProgress * 100).toStringAsFixed(1)}%',
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
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: onDownload,
                  icon: Icon(
                    isCompleted
                        ? Icons.replay_rounded
                        : Icons.download_rounded,
                    size: 18,
                  ),
                  label: Text(
                    isCompleted
                        ? 'Download Again'
                        : 'Download ${transfer.files.length} file(s) · ${TransferService.formatBytesStatic(transfer.totalBytes)}',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isCompleted ? AppTheme.accent : AppTheme.success,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
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
      default:
        color = AppTheme.warning;
        icon = Icons.schedule_rounded;
    }
    return Icon(icon, color: color, size: 22);
  }
}

class _StatusBadge extends StatelessWidget {
  final TransferStatus status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    String label;
    switch (status) {
      case TransferStatus.completed:
        bg = AppTheme.successGlow;
        fg = AppTheme.success;
        label = 'Done';
      case TransferStatus.uploading:
        bg = AppTheme.accentGlow;
        fg = AppTheme.accent;
        label = 'Uploading';
      case TransferStatus.uploaded:
        bg = AppTheme.accentGlow;
        fg = AppTheme.accent;
        label = 'Ready';
      case TransferStatus.downloading:
        bg = AppTheme.successGlow;
        fg = AppTheme.success;
        label = 'Downloading';
      case TransferStatus.failed:
        bg = AppTheme.errorGlow;
        fg = AppTheme.error;
        label = 'Failed';
      case TransferStatus.expired:
        bg = AppTheme.errorGlow;
        fg = AppTheme.error;
        label = 'Expired';
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
