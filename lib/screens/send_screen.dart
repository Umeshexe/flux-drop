import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/constants.dart';
import '../core/theme.dart';
import '../models/transfer_model.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/network_service.dart';
import '../services/transfer_service.dart';
import '../widgets/flux_ui.dart';

class SendScreen extends StatefulWidget {
  final UserModel user;
  const SendScreen({super.key, required this.user});

  @override
  State<SendScreen> createState() => _SendScreenState();
}

class _SendScreenState extends State<SendScreen> {
  final _codeController = TextEditingController();
  final _transferService = TransferService();
  final _authService = AuthService();
  final _networkService = NetworkService();

  List<PlatformFile> _selectedFiles = [];
  UserModel? _recipient;
  bool _lookingUp = false;
  bool _sending = false;
  String? _recipientError;

  // Per-file + aggregate progress
  int _currentFileIndex = 0;
  int _totalFiles = 0;
  int _bytesTransferred = 0;
  int _totalBytes = 0;
  bool _cancelling = false;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  // ─── Recipient lookup ─────────────────────────────────────────────────────
  Future<void> _lookupRecipient() async {
    FocusScope.of(context).unfocus();
    final code = _codeController.text.trim().toUpperCase();

    // ★ Invalid code – fast fail
    if (code.isEmpty) {
      setState(() => _recipientError = 'Please enter a recipient code');
      return;
    }
    if (code.length != AppConstants.shortCodeLength) {
      setState(
        () => _recipientError =
            'Code must be ${AppConstants.shortCodeLength} characters (got ${code.length})',
      );
      return;
    }
    // Check for invalid characters
    for (final c in code.split('')) {
      if (!AppConstants.shortCodeAlphabet.contains(c)) {
        setState(
          () => _recipientError =
              'Invalid character "$c" — avoid O, I, L (use 0, 1, 1 equivalents)',
        );
        return;
      }
    }
    // ★ Cannot send to yourself
    if (code == widget.user.shortCode) {
      setState(() => _recipientError = 'You cannot send files to yourself');
      return;
    }

    setState(() {
      _lookingUp = true;
      _recipientError = null;
      _recipient = null;
    });

    try {
      final found = await _authService.lookupByShortCode(code);
      if (found == null) {
        setState(() => _recipientError = '❌ No user found with code "$code"');
      } else {
        setState(() => _recipient = found);
      }
    } catch (e) {
      setState(() => _recipientError = 'Lookup failed: ${e.toString()}');
    } finally {
      setState(() => _lookingUp = false);
    }
  }

  // ─── File picker ──────────────────────────────────────────────────────────
  Future<void> _pickFiles() async {
    // ★ Permission handling — degrade gracefully
    if (Platform.isAndroid) {
      final status = await Permission.storage.request();
      if (status.isPermanentlyDenied) {
        _showPermissionDialog();
        return;
      }
    }

    try {
      final result = await FilePicker.pickFiles(
        allowMultiple: true,
        withData: false,
        withReadStream: false,
      );

      if (result == null || result.files.isEmpty) return;

      // Filter files that exceed 500 MB
      final oversized = result.files
          .where((f) => f.size > AppConstants.maxFileSizeBytes)
          .toList();

      if (oversized.isNotEmpty) {
        final names = oversized.map((f) => f.name).join(', ');
        _showSnack('⚠️ Files exceed 500 MB limit: $names', isError: true);
        final valid = result.files
            .where((f) => f.size <= AppConstants.maxFileSizeBytes)
            .toList();
        setState(() => _selectedFiles = valid);
      } else {
        setState(() => _selectedFiles = result.files);
      }

      // ★ Zero-byte file warning
      final empty = _selectedFiles.where((f) => f.size == 0).toList();
      if (empty.isNotEmpty) {
        _showSnack(
          '⚠️ ${empty.length} zero-byte file(s) removed',
          isError: false,
        );
        _selectedFiles.removeWhere((f) => f.size == 0);
      }
    } catch (e) {
      _showSnack('Failed to pick files: ${e.toString()}', isError: true);
    }
  }

  void _showPermissionDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        title: Text('Storage Permission Needed'),
        content: Text(
          'FluxDrop needs storage access to pick files. Please enable it in Settings.',
        ),
        actions: [
          FluxButton(
            onPressed: () => Navigator.pop(context),
            fullWidth: false,
            outlined: true,
            tone: FluxButtonTone.neutral,
            child: Text('Cancel'),
          ),
          FluxButton(
            onPressed: () {
              Navigator.pop(context);
              openAppSettings();
            },
            fullWidth: false,
            child: Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  // ─── Send ─────────────────────────────────────────────────────────────────
  Future<void> _send() async {
    if (_recipient == null) {
      _showSnack('Please find a recipient first', isError: true);
      return;
    }
    if (_selectedFiles.isEmpty) {
      _showSnack('Please select at least one file', isError: true);
      return;
    }

    final totalBytes = _selectedFiles.fold<int>(
      0,
      (sum, file) => sum + file.size,
    );
    if (totalBytes > 50 * 1024 * 1024 &&
        await _networkService.isLikelyMeteredConnection()) {
      final confirmed = await _showMeteredWarning(
        TransferService.formatBytesStatic(totalBytes),
      );
      if (!confirmed) return;
    }

    setState(() {
      _sending = true;
      _cancelling = false;
      _bytesTransferred = 0;
      _totalBytes = 0;
      _currentFileIndex = 0;
      _totalFiles = _selectedFiles.length;
    });

    try {
      final transfer = await _transferService.sendFiles(
        sender: widget.user,
        receiver: _recipient!,
        files: _selectedFiles,
        onProgress: (fileIndex, totalFiles, bytesUploaded, totalBytes) {
          if (mounted) {
            setState(() {
              _currentFileIndex = fileIndex;
              _totalFiles = totalFiles;
              _bytesTransferred = bytesUploaded;
              _totalBytes = totalBytes;
            });
          }
        },
      );

      setState(() => _sending = false);
      _showSuccessSheet(transfer);
    } catch (e) {
      setState(() {
        _sending = false;
        _cancelling = false;
      });
      if (e is TransferCancelledException) {
        _showSnack(e.toString(), isError: false);
      } else {
        _showSnack('Transfer failed: ${e.toString()}', isError: true);
      }
    }
  }

  Future<void> _cancelUpload() async {
    if (_cancelling) return;
    setState(() => _cancelling = true);
    final cancelled = await _transferService.cancelCurrentUpload();
    if (!cancelled && mounted) {
      setState(() => _cancelling = false);
      _showSnack('No active upload to cancel', isError: true);
    }
  }

  Future<bool> _showMeteredWarning(String sizeLabel) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.bgCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(
              Icons.signal_cellular_alt_rounded,
              color: AppTheme.warning,
              size: 22,
            ),
            SizedBox(width: 10),
            Text('Large Upload'),
          ],
        ),
        content: Text(
          'This transfer is $sizeLabel. Uploading on mobile data may use significant cellular quota.\n\nProceed anyway?',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        actions: [
          FluxButton(
            onPressed: () => Navigator.pop(ctx, false),
            fullWidth: false,
            outlined: true,
            tone: FluxButtonTone.neutral,
            child: Text('Cancel'),
          ),
          FluxButton(
            onPressed: () => Navigator.pop(ctx, true),
            fullWidth: false,
            child: Text('Upload Anyway'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  void _showSuccessSheet(TransferModel transfer) {
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: AppTheme.bgCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            28,
            28,
            28,
            28 + MediaQuery.viewPaddingOf(context).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  gradient: AppTheme.successGradient,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.success.withAlpha(80),
                      blurRadius: 20,
                    ),
                  ],
                ),
                child: Icon(Icons.check_rounded, color: Colors.white, size: 30),
              ),
              SizedBox(height: 16),
              Text(
                'Transfer Complete!',
                style: Theme.of(context).textTheme.headlineLarge,
              ),
              SizedBox(height: 8),
              Text(
                '${transfer.files.length} file(s) sent to ${transfer.receiverCode}',
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 8),
              Text(
                '${TransferService.formatBytesStatic(transfer.totalBytes)} transferred',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall!.copyWith(color: AppTheme.success),
              ),
              SizedBox(height: 24),
              FluxButton(
                onPressed: () {
                  Navigator.pop(context);
                  setState(() {
                    _selectedFiles = [];
                    _recipient = null;
                    _codeController.clear();
                  });
                },
                child: Text('Send More Files'),
              ),
            ],
          ),
        ),
      ),
    ).then((_) {
      if (mounted) {
        FocusScope.of(context).unfocus();
        FocusManager.instance.primaryFocus?.unfocus();
      }
    });
  }

  void _showSnack(String msg, {required bool isError}) {
    Fluttertoast.showToast(
      msg: msg,
      backgroundColor: isError ? AppTheme.error : AppTheme.success,
      textColor: Colors.white,
      toastLength: Toast.LENGTH_LONG,
    );
  }

  // ─── UI ───────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      behavior: HitTestBehavior.opaque,
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: 8),
            Text(
              'Send Files',
              style: Theme.of(context).textTheme.displayMedium,
            ),
            SizedBox(height: 4),
            Text(
              'Enter the recipient\'s code and select files',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            SizedBox(height: 32),

            // ─── Recipient code input ─────────────────────────────────────────
            Text(
              'Recipient Code',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            SizedBox(height: 10),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Builder(builder: (ctx) {
                      final isNeo = AppTheme.isNeoPop;
                      final field = TextField(
                        controller: _codeController,
                        textCapitalization: TextCapitalization.characters,
                        maxLength: AppConstants.shortCodeLength,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 4,
                          color: isNeo ? AppTheme.accent : AppTheme.textPrimary,
                        ),
                        decoration: InputDecoration(
                          hintText: 'A4X9K2',
                          counterText: '',
                          enabledBorder: isNeo
                              ? OutlineInputBorder(
                                  borderRadius: BorderRadius.zero,
                                  borderSide: BorderSide(color: AppTheme.accent, width: 2),
                                )
                              : null,
                          focusedBorder: isNeo
                              ? OutlineInputBorder(
                                  borderRadius: BorderRadius.zero,
                                  borderSide: BorderSide(color: AppTheme.accent, width: 2.5),
                                )
                              : null,
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 16,
                          ),
                          prefixIcon: Icon(
                            Icons.tag_rounded,
                            color: isNeo ? AppTheme.accent : AppTheme.textMuted,
                          ),
                          filled: isNeo,
                          fillColor: isNeo ? Colors.black : null,
                        ),
                        onChanged: (_) {
                          if (_recipientError != null) {
                            setState(() {
                              _recipientError = null;
                              _recipient = null;
                            });
                          }
                        },
                        onSubmitted: (_) => _lookupRecipient(),
                      );
                      if (!isNeo) return field;
                      return Container(
                        decoration: BoxDecoration(
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black,
                              offset: Offset(3, 3),
                              blurRadius: 0,
                            ),
                          ],
                        ),
                        child: field,
                      );
                    }),
                  ),
                  SizedBox(width: 12),
                  FluxButton(
                    onPressed: _lookingUp ? null : _lookupRecipient,
                    fullWidth: false,
                    padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    child: _lookingUp
                        ? SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppTheme.isNeoPop
                                  ? Colors.black
                                  : Colors.white,
                            ),
                          )
                        : Text('Find', style: TextStyle(fontSize: 16)),
                  ),
                ],
              ),
            ),

            if (_recipientError != null)
              Padding(
                padding: EdgeInsets.only(top: 8, left: 4),
                child: Text(
                  _recipientError!,
                  style: TextStyle(color: AppTheme.error, fontSize: 13),
                ),
              ),

            // Recipient found indicator
            if (_recipient != null) ...[
              SizedBox(height: 12),
              Container(
                padding: EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: AppTheme.successGlow,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppTheme.success.withAlpha(100)),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.check_circle_rounded,
                      color: AppTheme.success,
                      size: 20,
                    ),
                    SizedBox(width: 10),
                    Text(
                      'Recipient found: ${_recipient!.shortCode}',
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium!.copyWith(color: AppTheme.success),
                    ),
                  ],
                ),
              ),
            ],

            SizedBox(height: 28),

            // ─── File picker ──────────────────────────────────────────────────
            Text('Select Files', style: Theme.of(context).textTheme.titleLarge),
            SizedBox(height: 10),
            if (_selectedFiles.isEmpty)
              GestureDetector(
                onTap: _pickFiles,
                child: FluxSurface(
                  color: AppTheme.bgCardElevated,
                  padding: EdgeInsets.symmetric(vertical: 32, horizontal: 20),
                  child: Column(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: AppTheme.accentGlow,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.add_rounded,
                          color: AppTheme.accent,
                          size: 30,
                        ),
                      ),
                      SizedBox(height: 12),
                      Text(
                        'Tap to select files',
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Images, videos, documents, any format • Max 500 MB',
                        style: Theme.of(context).textTheme.bodySmall,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              )
            else ...[
              // Show selected files
              ..._selectedFiles.map(
                (f) => _FileChip(
                  file: f,
                  onRemove: () => setState(() => _selectedFiles.remove(f)),
                ),
              ),
              SizedBox(height: 10),
              FluxButton(
                onPressed: _pickFiles,
                fullWidth: false,
                outlined: true,
                tone: FluxButtonTone.neutral,
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.add_rounded, size: 18),
                    SizedBox(width: 6),
                    Text('Add More Files'),
                  ],
                ),
              ),
            ],

            SizedBox(height: 32),

            // ─── Progress bar (shown during send) ─────────────────────────────
            if (_sending) ...[
              _ProgressSection(
                currentFile: _currentFileIndex,
                totalFiles: _totalFiles,
                bytesTransferred: _bytesTransferred,
                totalBytes: _totalBytes,
                cancelling: _cancelling,
                onCancel: _cancelUpload,
              ),
              SizedBox(height: 24),
            ],

            // ─── Send button ──────────────────────────────────────────────────
            if (!_sending)
              FluxButton(
                onPressed:
                    (_recipient != null &&
                        _selectedFiles.isNotEmpty &&
                        !_sending)
                    ? _send
                    : null,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.upload_rounded),
                    SizedBox(width: 8),
                    Text(
                      _selectedFiles.isEmpty
                          ? 'Select files to send'
                          : _recipient == null
                          ? 'Find a recipient first'
                          : 'Send ${_selectedFiles.length} file(s)',
                    ),
                  ],
                ),
              ),

            SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

// ─── Sub-widgets ──────────────────────────────────────────────────────────────

class _FileChip extends StatelessWidget {
  final PlatformFile file;
  final VoidCallback onRemove;

  const _FileChip({required this.file, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final isOversized = file.size > AppConstants.maxFileSizeBytes;

    return Container(
      margin: EdgeInsets.only(bottom: 8),
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isOversized ? AppTheme.errorGlow : AppTheme.bgCardElevated,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isOversized ? AppTheme.error : AppTheme.border,
        ),
      ),
      child: Row(
        children: [
          Icon(
            _iconForFile(file.extension ?? ''),
            color: isOversized ? AppTheme.error : AppTheme.accent,
            size: 22,
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  file.name,
                  style: Theme.of(context).textTheme.bodyLarge,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  TransferService.formatBytesStatic(file.size) +
                      (isOversized ? ' — EXCEEDS 500 MB LIMIT' : ''),
                  style: Theme.of(context).textTheme.bodySmall!.copyWith(
                    color: isOversized ? AppTheme.error : AppTheme.textMuted,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onRemove,
            icon: Icon(Icons.close_rounded, size: 18),
            color: AppTheme.textMuted,
          ),
        ],
      ),
    );
  }

  IconData _iconForFile(String ext) {
    switch (ext.toLowerCase()) {
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'webp':
        return Icons.image_rounded;
      case 'mp4':
      case 'mov':
      case 'avi':
        return Icons.videocam_rounded;
      case 'mp3':
      case 'aac':
      case 'wav':
        return Icons.audiotrack_rounded;
      case 'pdf':
        return Icons.picture_as_pdf_rounded;
      case 'zip':
      case 'rar':
      case '7z':
        return Icons.folder_zip_rounded;
      default:
        return Icons.insert_drive_file_rounded;
    }
  }
}

class _ProgressSection extends StatelessWidget {
  final int currentFile;
  final int totalFiles;
  final int bytesTransferred;
  final int totalBytes;
  final bool cancelling;
  final VoidCallback onCancel;

  const _ProgressSection({
    required this.currentFile,
    required this.totalFiles,
    required this.bytesTransferred,
    required this.totalBytes,
    required this.cancelling,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final progress = totalBytes > 0 ? bytesTransferred / totalBytes : 0.0;
    final percent = (progress * 100).toStringAsFixed(1);

    return Container(
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppTheme.accent,
                ),
              ),
              SizedBox(width: 12),
              Text(
                cancelling
                    ? 'Cancelling upload...'
                    : 'Uploading file $currentFile of $totalFiles',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              Spacer(),
              Text(
                '$percent%',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge!.copyWith(color: AppTheme.accent),
              ),
            ],
          ),
          SizedBox(height: 16),
          // Aggregate progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: AppTheme.bgCardElevated,
              color: AppTheme.accent,
              minHeight: 8,
            ),
          ),
          SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                TransferService.formatBytesStatic(bytesTransferred),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Text(
                TransferService.formatBytesStatic(totalBytes),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          SizedBox(height: 16),
          FluxButton(
            onPressed: cancelling ? null : onCancel,
            tone: FluxButtonTone.danger,
            outlined: true,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  cancelling
                      ? Icons.hourglass_top_rounded
                      : Icons.close_rounded,
                  size: 18,
                ),
                SizedBox(width: 8),
                Text(cancelling ? 'Cancelling...' : 'Cancel Transfer'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
