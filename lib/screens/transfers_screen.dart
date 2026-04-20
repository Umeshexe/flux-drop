import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/theme.dart';
import '../models/transfer_model.dart';
import '../models/user_model.dart';
import 'file_preview_screen.dart';
import '../services/network_service.dart';
import '../services/notification_service.dart';
import '../services/transfer_service.dart';

class TransfersScreen extends StatefulWidget {
  final UserModel user;
  final String? autoStartTransferId;
  final VoidCallback? onAutoStartConsumed;

  const TransfersScreen({
    super.key,
    required this.user,
    this.autoStartTransferId,
    this.onAutoStartConsumed,
  });

  @override
  State<TransfersScreen> createState() => _TransfersScreenState();
}

class _TransfersScreenState extends State<TransfersScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _transferService = TransferService();
  final _networkService = NetworkService();
  late final Stream<List<TransferModel>> _incomingStream = _transferService
      .incomingTransfers(widget.user.uid);
  late final Stream<List<TransferModel>> _outgoingStream = _transferService
      .outgoingTransfers(widget.user.uid);

  // Track active downloads to show progress
  final Map<String, _DownloadProgress> _activeDownloads = {};
  // Track transfers already fully downloaded — prevent duplicate saves
  final Set<String> _completedDownloads = {};
  String? _lastAutoStartedTransferId;
  static const _storageChannel = MethodChannel('fluxdrop/storage');

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

  Future<void> _downloadTransfer(
    TransferModel transfer, {
    bool allowDuplicate = false,
  }) async {
    if (_activeDownloads.containsKey(transfer.transferId)) return;

    // Duplicate protection: if already downloaded in this session, skip silently
    // (the user explicitly hit "Download Again" from the card for re-downloads)
    final prefs = await SharedPreferences.getInstance();
    final downloaded = prefs.getStringList('downloaded_transfers') ?? [];
    if (!allowDuplicate &&
        (_completedDownloads.contains(transfer.transferId) ||
            downloaded.contains(transfer.transferId))) {
      // Already downloaded — show a toast and skip (unless it was a re-attempt)
      Fluttertoast.showToast(
        msg: 'Already saved to your device',
        backgroundColor: AppTheme.success,
        textColor: Colors.white,
        toastLength: Toast.LENGTH_SHORT,
      );
      return;
    }

    // Warn only when the device is actually on a likely metered connection.
    if (transfer.totalBytes > 50 * 1024 * 1024 &&
        await _networkService.isLikelyMeteredConnection()) {
      final sizeLabel = TransferService.formatBytesStatic(transfer.totalBytes);
      final confirmed = await _showMeteredWarning(
        sizeLabel,
        actionLabel: 'Download Anyway',
      );
      if (!confirmed) return;
    }

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

      // Mark as downloaded to prevent duplicate save
      _completedDownloads.add(transfer.transferId);
      final prefs2 = await SharedPreferences.getInstance();
      final downloaded2 = prefs2.getStringList('downloaded_transfers') ?? [];
      downloaded2.add(transfer.transferId);
      await prefs2.setStringList('downloaded_transfers', downloaded2);

      await NotificationService().showLocalNotification(
        title: '✅ Download Complete',
        body:
            '${transfer.files.length} file(s) from ${transfer.senderCode} saved',
      );

      if (mounted && paths.isNotEmpty) {
        final partialFailure = paths.length < transfer.files.length;
        _showSavedSheet(paths, customPath: customPath);

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

  void _maybeAutoStartTransfer(List<TransferModel> transfers) {
    final targetId = widget.autoStartTransferId;
    if (targetId == null || _lastAutoStartedTransferId == targetId) {
      return;
    }

    TransferModel? transfer;
    for (final item in transfers) {
      if (item.transferId == targetId) {
        transfer = item;
        break;
      }
    }
    if (transfer == null) {
      return;
    }

    if (transfer.status != TransferStatus.uploaded) {
      widget.onAutoStartConsumed?.call();
      _lastAutoStartedTransferId = targetId;
      return;
    }

    _lastAutoStartedTransferId = targetId;
    widget.onAutoStartConsumed?.call();
    final transferToStart = transfer;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _downloadTransfer(transferToStart);
      }
    });
  }

  /// Shows a cellular data warning for large transfers.
  /// Returns true if user confirms, false if cancelled.
  Future<bool> _showMeteredWarning(
    String sizeLabel, {
    required String actionLabel,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(
              Icons.signal_cellular_alt_rounded,
              color: AppTheme.warning,
              size: 22,
            ),
            const SizedBox(width: 10),
            const Text('Large Download'),
          ],
        ),
        content: Text(
          'This transfer is $sizeLabel. Large downloads can use significant data on metered connections.\n\nProceed anyway?',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: AppTheme.textMuted),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.accent),
            child: Text(actionLabel),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  void _declineTransfer(TransferModel transfer) {
    FirebaseFirestore.instance
        .collection('transfers')
        .doc(transfer.transferId)
        .update({'status': 'rejected'});
  }

  void _showSavedSheet(List<String> paths, {String? customPath}) {
    FocusScope.of(context).unfocus();
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: AppTheme.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Padding(
        padding: EdgeInsets.fromLTRB(
          24,
          24,
          24,
          24 + MediaQuery.viewPaddingOf(context).bottom,
        ),
        child: SafeArea(
          top: false,
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
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Platform.isIOS
                      ? Colors.white.withAlpha(10)
                      : AppTheme.bgCardElevated,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _savedLocationTitle(customPath: customPath),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _savedLocationSubtitle(customPath: customPath),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
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
              const SizedBox(height: 16),
              if (paths.length == 1 && _canPreview(paths.first)) ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      _openPreview(paths.first);
                    },
                    icon: const Icon(Icons.visibility_rounded, size: 18),
                    label: const Text('Open'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.success,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              if (_hasMediaFiles(paths)) ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _saveToGallery(paths),
                    icon: const Icon(Icons.photo_library_rounded, size: 18),
                    label: Text(
                      Platform.isIOS ? 'Save to Photos' : 'Save to Gallery',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _shareDownloadedFiles(paths),
                  icon: const Icon(Icons.ios_share_rounded),
                  label: Text(
                    Platform.isIOS
                        ? 'Save to Files / Share'
                        : 'Save / Share Elsewhere',
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

  void _openPreview(String path) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => FilePreviewScreen(path: path)));
  }

  bool _canPreview(String path) => supportsFilePreview(path);

  /// Returns true if any of the saved paths are image or video files.
  bool _hasMediaFiles(List<String> paths) {
    const mediaExts = {
      'jpg',
      'jpeg',
      'png',
      'gif',
      'webp',
      'heic',
      'heif',
      'mp4',
      'mov',
      'avi',
      'mkv',
      'webm',
      '3gp',
    };
    return paths.any((p) {
      final ext = p.split('.').last.toLowerCase();
      return mediaExts.contains(ext);
    });
  }

  /// Saves media files to the device gallery via the native platform channel.
  /// This exercises the `fluxdrop/storage` method channel bonus integration.
  Future<void> _saveToGallery(List<String> paths) async {
    final mediaExts = {
      'jpg',
      'jpeg',
      'png',
      'gif',
      'webp',
      'heic',
      'heif',
      'mp4',
      'mov',
      'avi',
      'mkv',
      'webm',
      '3gp',
    };
    final mediaPaths = paths
        .where((p) => mediaExts.contains(p.split('.').last.toLowerCase()))
        .toList();

    int saved = 0;
    for (final path in mediaPaths) {
      try {
        await _storageChannel.invokeMethod('saveToGallery', {'path': path});
        saved++;
      } catch (e) {
        debugPrint('⚠️ Gallery save failed for $path: $e');
      }
    }

    if (saved > 0) {
      Fluttertoast.showToast(
        msg: saved == 1
            ? 'Saved to ${Platform.isIOS ? "Photos" : "Gallery"}'
            : '$saved files saved to ${Platform.isIOS ? "Photos" : "Gallery"}',
        backgroundColor: AppTheme.success,
        textColor: Colors.white,
        toastLength: Toast.LENGTH_SHORT,
      );
    } else {
      Fluttertoast.showToast(
        msg: 'Could not save to gallery. Try sharing instead.',
        backgroundColor: AppTheme.error,
        textColor: Colors.white,
        toastLength: Toast.LENGTH_LONG,
      );
    }
  }

  String _storageDestinationLabel({String? customPath}) {
    if (customPath != null && customPath.isNotEmpty) {
      final parts = customPath
          .split('/')
          .where((part) => part.isNotEmpty)
          .toList();
      return parts.isEmpty ? 'your chosen device folder' : parts.last;
    }
    return 'FluxDrop app storage';
  }

  String _savedLocationTitle({String? customPath}) {
    if (customPath != null && customPath.isNotEmpty) {
      return Platform.isIOS
          ? 'Saved to your chosen location'
          : 'Saved to your device folder';
    }
    return 'Stored inside FluxDrop';
  }

  String _savedLocationSubtitle({String? customPath}) {
    if (customPath != null && customPath.isNotEmpty) {
      return 'Saved in ${_storageDestinationLabel(customPath: customPath)}. You can still open or share it below.';
    }
    return 'Available from Transfers. Use Open, Photos/Gallery, or Save to Files / Share to move it elsewhere.';
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
        _maybeAutoStartTransfer(transfers);
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
            onDownload: () => _downloadTransfer(
              transfers[i],
              allowDuplicate: transfers[i].status == TransferStatus.completed,
            ),
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
                    child: OutlinedButton.icon(
                      onPressed: transfer.status == TransferStatus.completed
                          ? () => onDownload?.call()
                          : onDownload,
                      icon: Icon(
                        isCompleted
                            ? Icons.replay_rounded
                            : Icons.check_circle_rounded,
                        size: 18,
                      ),
                      label: Text(isCompleted ? 'Download Again' : 'Download'),
                      style: OutlinedButton.styleFrom(
                        backgroundColor: AppTheme.success,
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: AppTheme.success),
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
          return 'Ready to download';
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
        return 'Waiting for download';
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
