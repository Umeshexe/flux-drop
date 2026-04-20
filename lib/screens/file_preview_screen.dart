import 'dart:io';

import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:share_plus/share_plus.dart';

import '../core/theme.dart';

const Set<String> previewableImageExtensions = {
  'jpg',
  'jpeg',
  'png',
  'gif',
  'webp',
  'heic',
  'heif',
};

const Set<String> previewableTextExtensions = {
  'txt',
  'md',
  'json',
  'csv',
  'log',
  'yaml',
  'yml',
  'xml',
};

bool supportsFilePreview(String path) {
  final ext = path.split('.').last.toLowerCase();
  return previewableImageExtensions.contains(ext) ||
      previewableTextExtensions.contains(ext);
}

class FilePreviewScreen extends StatefulWidget {
  final String path;

  const FilePreviewScreen({super.key, required this.path});

  @override
  State<FilePreviewScreen> createState() => _FilePreviewScreenState();
}

class _FilePreviewScreenState extends State<FilePreviewScreen> {
  late final String _extension = widget.path.split('.').last.toLowerCase();

  bool get _isImage => previewableImageExtensions.contains(_extension);
  bool get _isText => previewableTextExtensions.contains(_extension);

  Future<void> _shareFile() async {
    try {
      final size = MediaQuery.of(context).size;
      await Share.shareXFiles([
        XFile(widget.path),
      ], sharePositionOrigin: Rect.fromLTWH(0, 0, size.width, size.height / 2));
    } catch (e) {
      Fluttertoast.showToast(
        msg: 'Could not open share sheet: $e',
        backgroundColor: AppTheme.error,
        textColor: Colors.white,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: Text(
          widget.path.split('/').last,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            onPressed: _shareFile,
            icon: const Icon(Icons.ios_share_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(padding: const EdgeInsets.all(20), child: _buildBody()),
      ),
    );
  }

  Widget _buildBody() {
    if (_isImage) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: Container(
          width: double.infinity,
          color: AppTheme.bgCard,
          child: InteractiveViewer(
            minScale: 0.8,
            maxScale: 5,
            child: Center(
              child: Image.file(
                File(widget.path),
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) =>
                    _buildUnsupported('This image could not be rendered.'),
              ),
            ),
          ),
        ),
      );
    }

    if (_isText) {
      return FutureBuilder<String>(
        future: File(widget.path).readAsString(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: AppTheme.accent),
            );
          }
          if (snapshot.hasError) {
            return _buildUnsupported('This file could not be opened as text.');
          }

          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppTheme.bgCard,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppTheme.border),
            ),
            child: SingleChildScrollView(
              child: SelectableText(
                snapshot.data ?? '',
                style: ThemeData.dark().textTheme.bodyMedium?.copyWith(
                  color: AppTheme.textPrimary,
                  height: 1.5,
                ),
              ),
            ),
          );
        },
      );
    }

    return _buildUnsupported(
      'Preview is available for images and text-based files. Use Share to open this elsewhere.',
    );
  }

  Widget _buildUnsupported(String message) {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppTheme.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.insert_drive_file_rounded,
              size: 44,
              color: AppTheme.textMuted,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: ThemeData.dark().textTheme.bodyMedium?.copyWith(
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
