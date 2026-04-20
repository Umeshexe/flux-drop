import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/theme.dart';
import '../models/transfer_model.dart';
import '../models/user_model.dart';
import '../services/notification_service.dart';
import '../services/transfer_service.dart';
import 'send_screen.dart';
import 'settings_screen.dart';
import 'transfers_screen.dart';

class HomeScreen extends StatefulWidget {
  final UserModel user;
  final int initialTabIndex;

  const HomeScreen({super.key, required this.user, this.initialTabIndex = 0});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  int _selectedIndex = 0;
  late AnimationController _codeRevealController;
  late Animation<double> _codeReveal;
  bool _codeCopied = false;
  String? _autoStartTransferId;

  // Global incoming transfer state
  Stream<List<TransferModel>>? _incomingStream;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialTabIndex;
    _codeRevealController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..forward();
    _codeReveal = CurvedAnimation(
      parent: _codeRevealController,
      curve: Curves.easeOutCubic,
    );

    // Listen globally for active incoming transfers
    _incomingStream = TransferService().incomingTransfers(widget.user.uid);

    // Expire old transfers on launch
    TransferService().expireOldTransfers();

    NotificationService().openTransfersRequests.listen((_) {
      if (mounted) {
        setState(() => _selectedIndex = 2);
      }
    });
  }

  @override
  void dispose() {
    _codeRevealController.dispose();
    super.dispose();
  }

  String _fmtSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Widget _buildPage(List<TransferModel> active, TransferModel? pendingReady) {
    switch (_selectedIndex) {
      case 0:
        return _buildHome(active, pendingReady);
      case 1:
        return SendScreen(user: widget.user);
      case 2:
        return TransfersScreen(
          user: widget.user,
          autoStartTransferId: _autoStartTransferId,
          onAutoStartConsumed: () {
            if (mounted) {
              setState(() => _autoStartTransferId = null);
            }
          },
        );
      default:
        return _buildHome(active, pendingReady);
    }
  }

  Future<void> _acceptIncomingTransfer(TransferModel transfer) async {
    setState(() {
      _autoStartTransferId = transfer.transferId;
      _selectedIndex = 2;
    });
    Fluttertoast.showToast(
      msg: 'Opening Transfers to start download...',
      backgroundColor: AppTheme.success,
      textColor: Colors.white,
      toastLength: Toast.LENGTH_SHORT,
    );
  }

  Future<void> _declineIncomingTransfer(TransferModel transfer) async {
    await FirebaseFirestore.instance
        .collection('transfers')
        .doc(transfer.transferId)
        .update({'status': 'rejected'});
    if (!mounted) return;
    Fluttertoast.showToast(
      msg: 'Transfer declined',
      backgroundColor: AppTheme.error,
      textColor: Colors.white,
      toastLength: Toast.LENGTH_SHORT,
    );
  }

  Widget _buildHome(List<TransferModel> active, TransferModel? pendingReady) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 8),
          // Header — tap logo to open Drawer
          GestureDetector(
            onTap: () => _scaffoldKey.currentState?.openDrawer(),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: AppTheme.accentGradient,
                  ),
                  child: const Icon(
                    Icons.bolt_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'FluxDrop',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    Text(
                      'Real-time file sharing',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
                const Spacer(),
                const Icon(
                  Icons.settings_rounded,
                  color: AppTheme.textMuted,
                  size: 20,
                ),
              ],
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            child: pendingReady == null
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: _IncomingReadyCard(
                      transfer: pendingReady,
                      formatSize: _fmtSize,
                      onAccept: () => _acceptIncomingTransfer(pendingReady),
                      onDecline: () => _declineIncomingTransfer(pendingReady),
                      onOpenTransfers: () => setState(() => _selectedIndex = 2),
                    ),
                  ),
          ),
          // ─── Active transfer card (matches Transfers screen style) ────
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
            child: active.isEmpty
                ? const SizedBox.shrink()
                : GestureDetector(
                    onTap: () => setState(() => _selectedIndex = 2),
                    child: Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppTheme.bgCard,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: AppTheme.accent.withAlpha(80),
                          ),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                // Pulsing dot
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: AppTheme.accent,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: AppTheme.accent.withAlpha(120),
                                        blurRadius: 4,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    active.first.status ==
                                            TransferStatus.uploading
                                        ? 'Receiving from ${active.first.senderCode}'
                                        : 'Downloading from ${active.first.senderCode}',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.textPrimary,
                                    ),
                                  ),
                                ),
                                Text(
                                  active.first.status ==
                                          TransferStatus.uploading
                                      ? _fmtSize(active.first.totalBytes)
                                      : _fmtSize(active.first.totalBytes),
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.accent,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            // Progress bar
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value:
                                    active.first.status ==
                                        TransferStatus.uploading
                                    ? (active.first.uploadProgress > 0
                                          ? active.first.uploadProgress
                                          : null)
                                    : null,
                                backgroundColor: AppTheme.bgCardElevated,
                                color: AppTheme.accent,
                                minHeight: 4,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  active.first.status ==
                                          TransferStatus.uploading
                                      ? 'Receiving… ${(active.first.uploadProgress * 100).toStringAsFixed(0)}%'
                                      : 'Downloading files…',
                                  style: Theme.of(context).textTheme.bodySmall!
                                      .copyWith(
                                        color: AppTheme.accent,
                                        fontSize: 11,
                                      ),
                                ),
                                Text(
                                  '${active.first.files.length} file(s)',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.bodySmall!.copyWith(fontSize: 11),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: 20),

          // Your code card
          _YourCodeCard(
            user: widget.user,
            animation: _codeReveal,
            copied: _codeCopied,
            onCopy: () async {
              await Clipboard.setData(
                ClipboardData(text: widget.user.shortCode),
              );
              setState(() => _codeCopied = true);
              await Future.delayed(const Duration(seconds: 2));
              if (mounted) setState(() => _codeCopied = false);
            },
          ),

          const SizedBox(height: 24),

          // Quick actions
          Text('Quick Actions', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _ActionCard(
                  icon: Icons.upload_rounded,
                  label: 'Send Files',
                  subtitle: 'Share to any device',
                  gradient: AppTheme.accentGradient,
                  onTap: () => setState(() => _selectedIndex = 1),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _ActionCard(
                  icon: Icons.history_rounded,
                  label: 'Transfers',
                  subtitle: 'View history',
                  gradient: AppTheme.successGradient,
                  onTap: () => setState(() => _selectedIndex = 2),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Info cards
          _InfoCard(
            icon: Icons.shield_rounded,
            title: 'End-to-End Secure',
            body:
                'All transfers use TLS encryption. Files are verified with SHA-256 checksums.',
          ),
          const SizedBox(height: 12),
          _InfoCard(
            icon: Icons.access_time_rounded,
            title: '24-Hour Queue',
            body:
                'If the recipient is offline, your transfer waits up to 24 hours before expiring.',
          ),
          const SizedBox(height: 12),
          _InfoCard(
            icon: Icons.storage_rounded,
            title: 'Up to 500 MB',
            body:
                'Send files up to 500 MB in a single transfer. Multiple files supported.',
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<TransferModel>>(
      stream: _incomingStream,
      builder: (context, snap) {
        final incoming = snap.data ?? [];
        final active = incoming
            .where(
              (t) =>
                  t.status == TransferStatus.uploading ||
                  t.status == TransferStatus.downloading,
            )
            .toList();
        final ready = incoming
            .where((t) => t.status == TransferStatus.uploaded)
            .toList();
        final TransferModel? latestActive = active.isEmpty
            ? null
            : active.first;
        final TransferModel? latestReady = ready.isEmpty ? null : ready.first;
        final TransferModel? homePendingReady = latestActive == null
            ? latestReady
            : null;
        final hasBadge = incoming.any(
          (t) =>
              t.status == TransferStatus.uploading ||
              t.status == TransferStatus.uploaded,
        );
        return Scaffold(
          key: _scaffoldKey,
          backgroundColor: AppTheme.bg,
          drawer: _buildDrawer(),
          body: SafeArea(child: _buildPage(active, homePendingReady)),
          bottomNavigationBar: _buildNavBar(hasBadge: hasBadge),
        );
      },
    );
  }

  Widget _buildNavBar({bool hasBadge = false}) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppTheme.border, width: 1)),
        color: AppTheme.bgCard,
      ),
      child: SafeArea(
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              _NavItem(
                icon: Icons.home_rounded,
                label: 'Home',
                selected: _selectedIndex == 0,
                onTap: () => setState(() => _selectedIndex = 0),
              ),
              _NavItem(
                icon: Icons.upload_rounded,
                label: 'Send',
                selected: _selectedIndex == 1,
                onTap: () => setState(() => _selectedIndex = 1),
              ),
              _NavItem(
                icon: Icons.history_rounded,
                label: 'Transfers',
                selected: _selectedIndex == 2,
                showBadge: hasBadge,
                onTap: () => setState(() => _selectedIndex = 2),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      backgroundColor: AppTheme.bgCard,
      width: MediaQuery.of(context).size.width * 0.75, // 75% of screen
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: AppTheme.accentGradient,
                    ),
                    child: const Icon(
                      Icons.bolt_rounded,
                      color: Colors.white,
                      size: 30,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'FluxDrop',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 30,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.successGlow,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 9,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: AppTheme.success,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Flexible(
                          child: Text(
                            'Firebase Connected',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: AppTheme.success,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: AppTheme.border, height: 1),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 8,
              ),
              leading: const Icon(
                Icons.settings_rounded,
                color: AppTheme.textPrimary,
              ),
              title: const Text(
                'Settings',
                style: TextStyle(color: AppTheme.textPrimary, fontSize: 16),
              ),
              onTap: () {
                Navigator.pop(context); // close drawer
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SettingsPanel()),
                );
              },
            ),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 8,
              ),
              leading: const Icon(
                Icons.info_outline_rounded,
                color: AppTheme.textPrimary,
              ),
              title: const Text(
                'About FluxDrop',
                style: TextStyle(color: AppTheme.textPrimary, fontSize: 16),
              ),
              onTap: () {
                Navigator.pop(context);
                // Can show an about dialog here
              },
            ),
            const Spacer(),
            const Padding(
              padding: EdgeInsets.all(24.0),
              child: Text(
                'Version 1.0.0',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Sub-widgets ──────────────────────────────────────────────────────────────

class _YourCodeCard extends StatelessWidget {
  final UserModel user;
  final Animation<double> animation;
  final bool copied;
  final VoidCallback onCopy;

  const _YourCodeCard({
    required this.user,
    required this.animation,
    required this.copied,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (_, child) => Transform.translate(
        offset: Offset(0, 20 * (1 - animation.value)),
        child: Opacity(opacity: animation.value, child: child),
      ),
      child: Container(
        decoration: BoxDecoration(
          gradient: AppTheme.accentGradient,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: AppTheme.accent.withAlpha(80),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.fingerprint_rounded,
                  color: Colors.white70,
                  size: 18,
                ),
                const SizedBox(width: 6),
                Text(
                  'Your FluxDrop Code',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall!.copyWith(color: Colors.white70),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    user.shortCode,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 36,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: 8,
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: onCopy,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: copied
                          ? AppTheme.success.withAlpha(60)
                          : Colors.white.withAlpha(30),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          copied ? Icons.check_rounded : Icons.copy_rounded,
                          color: Colors.white,
                          size: 16,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          copied ? 'Copied!' : 'Copy',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Share this code with anyone to receive files',
              style: Theme.of(
                context,
              ).textTheme.bodySmall!.copyWith(color: Colors.white60),
            ),
          ],
        ),
      ),
    );
  }
}

class _IncomingReadyCard extends StatelessWidget {
  final TransferModel transfer;
  final String Function(int bytes) formatSize;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  final VoidCallback onOpenTransfers;

  const _IncomingReadyCard({
    required this.transfer,
    required this.formatSize,
    required this.onAccept,
    required this.onDecline,
    required this.onOpenTransfers,
  });

  String _formatExpiry(DateTime expiresAt) {
    final diff = expiresAt.difference(DateTime.now());
    if (diff.isNegative) return 'Expired';
    if (diff.inHours > 0) {
      return 'Expires in ${diff.inHours}h ${diff.inMinutes % 60}m';
    }
    return 'Expires in ${diff.inMinutes}m';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.warning.withAlpha(90)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppTheme.warning.withAlpha(28),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.inbox_rounded, color: AppTheme.warning),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'New transfer from ${transfer.senderCode}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${transfer.files.length} file(s) • ${formatSize(transfer.totalBytes)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppTheme.bgCardElevated,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ready to download',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium!.copyWith(color: AppTheme.textPrimary),
                ),
                const SizedBox(height: 4),
                Text(
                  'Accept to download this transfer to your device, or decline to reject it.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Text(
                  _formatExpiry(transfer.expiresAt),
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall!.copyWith(color: AppTheme.warning),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
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
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onAccept,
                  icon: const Icon(Icons.check_circle_rounded, size: 18),
                  label: const Text('Accept'),
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
          const SizedBox(height: 10),
          TextButton(
            onPressed: onOpenTransfers,
            child: const Text('Open Transfers for details'),
          ),
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final LinearGradient gradient;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.gradient,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppTheme.bgCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                gradient: gradient,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: Colors.white, size: 22),
            ),
            const SizedBox(height: 12),
            Text(label, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;

  const _InfoCard({
    required this.icon,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppTheme.accentGlow,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: AppTheme.accent, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(body, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final bool showBadge;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.showBadge = false,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: selected ? AppTheme.accentGlow : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Icon(
                    icon,
                    color: selected ? AppTheme.accent : AppTheme.textMuted,
                    size: 24,
                  ),
                  if (showBadge)
                    Positioned(
                      top: -2,
                      right: -4,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: AppTheme.accent,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? AppTheme.accent : AppTheme.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
