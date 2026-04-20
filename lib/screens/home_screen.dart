import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:neopop/neopop.dart';

import '../core/theme.dart';
import '../models/transfer_model.dart';
import '../models/user_model.dart';
import '../services/notification_service.dart';
import '../services/transfer_service.dart';
import '../widgets/flux_ui.dart';
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

  // Live connectivity state
  bool _isOnline = true;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  // Global incoming transfer state
  Stream<List<TransferModel>>? _incomingStream;

  @override
  void initState() {
    super.initState();
    _selectedIndex = widget.initialTabIndex;
    _codeRevealController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 700),
    )..forward();
    _codeReveal = CurvedAnimation(
      parent: _codeRevealController,
      curve: Curves.easeOutCubic,
    );

    // Listen globally for active incoming transfers
    _incomingStream = TransferService().incomingTransfers(widget.user.uid);

    // Expire old transfers on launch
    TransferService().expireOldTransfers();

    // Live connectivity monitoring
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final online = results.any((r) => r != ConnectivityResult.none);
      if (mounted && online != _isOnline) {
        setState(() => _isOnline = online);
      }
    });
    // Seed initial state
    Connectivity().checkConnectivity().then((results) {
      if (mounted) {
        setState(
          () => _isOnline = results.any((r) => r != ConnectivityResult.none),
        );
      }
    });

    NotificationService().openTransfersRequests.listen((_) {
      if (mounted) {
        setState(() => _selectedIndex = 2);
      }
    });
  }

  @override
  void dispose() {
    _codeRevealController.dispose();
    _connectivitySub?.cancel();
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

  Future<void> _showThemeSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppTheme.bgCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppTheme.cardRadiusLarge),
        ),
      ),
      builder: (ctx) => ValueListenableBuilder<FluxThemeMode>(
        valueListenable: AppTheme.modeNotifier,
        builder: (context, currentMode, _) {
          return SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'App Theme',
                    style: Theme.of(context).textTheme.headlineLarge,
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Switch between the current FluxDrop look and a NeoPOP visual mode.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  SizedBox(height: 18),
                  _ThemeOptionCard(
                    mode: FluxThemeMode.classic,
                    currentMode: currentMode,
                    title: 'Current',
                    subtitle: 'Rounded, softer, neon-glow focused.',
                    previewGradient: LinearGradient(
                      colors: [Color(0xFF6C63FF), Color(0xFF9D55FF)],
                    ),
                    onTap: () async {
                      await AppTheme.setThemeMode(FluxThemeMode.classic);
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                  ),
                  SizedBox(height: 12),
                  _ThemeOptionCard(
                    mode: FluxThemeMode.neoPop,
                    currentMode: currentMode,
                    title: 'NeoPOP',
                    subtitle: 'Sharper edges, harder shadows, louder contrast.',
                    previewGradient: LinearGradient(
                      colors: [Color(0xFFFFF176), Color(0xFFFFC107)],
                    ),
                    onTap: () async {
                      await AppTheme.setThemeMode(FluxThemeMode.neoPop);
                      if (ctx.mounted) Navigator.pop(ctx);
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHome(List<TransferModel> active, TransferModel? pendingReady) {
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: 8),
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
                  child: Icon(
                    Icons.bolt_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                SizedBox(width: 12),
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
                Spacer(),
                Icon(
                  Icons.settings_rounded,
                  color: AppTheme.textMuted,
                  size: 20,
                ),
              ],
            ),
          ),
          AnimatedSize(
            duration: Duration(milliseconds: 300),
            curve: Curves.easeOut,
            child: pendingReady == null
                ? SizedBox.shrink()
                : Padding(
                    padding: EdgeInsets.only(top: 16),
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
            duration: Duration(milliseconds: 300),
            curve: Curves.easeOut,
            child: active.isEmpty
                ? SizedBox.shrink()
                : GestureDetector(
                    onTap: () => setState(() => _selectedIndex = 2),
                    child: Padding(
                      padding: EdgeInsets.only(top: 16),
                      child: FluxSurface(
                        borderColor: AppTheme.accent.withAlpha(80),
                        padding: EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
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
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    active.first.status ==
                                            TransferStatus.uploading
                                        ? 'Receiving from ${active.first.senderCode}'
                                        : 'Downloading from ${active.first.senderCode}',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: AppTheme.textPrimary,
                                    ),
                                  ),
                                ),
                                Text(
                                  _fmtSize(active.first.totalBytes),
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.accent,
                                  ),
                                ),
                              ],
                            ),
                            SizedBox(height: 8),
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
                            SizedBox(height: 6),
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
          SizedBox(height: 20),

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
              await Future.delayed(Duration(seconds: 2));
              if (mounted) setState(() => _codeCopied = false);
            },
          ),

          SizedBox(height: 24),

          // Quick actions
          Text('Quick Actions', style: Theme.of(context).textTheme.titleLarge),
          SizedBox(height: 16),
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
              SizedBox(width: 12),
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
          SizedBox(height: 24),

          // Info cards
          _InfoCard(
            icon: Icons.shield_rounded,
            title: 'End-to-End Secure',
            body:
                'All transfers use TLS encryption. Files are verified with SHA-256 checksums.',
          ),
          SizedBox(height: 12),
          _InfoCard(
            icon: Icons.access_time_rounded,
            title: '24-Hour Queue',
            body:
                'If the recipient is offline, your transfer waits up to 24 hours before expiring.',
          ),
          SizedBox(height: 12),
          _InfoCard(
            icon: Icons.storage_rounded,
            title: 'Up to 500 MB',
            body:
                'Send files up to 500 MB in a single transfer. Multiple files supported.',
          ),
          SizedBox(height: 32),
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
    final isNeo = AppTheme.isNeoPop;
    if (!isNeo) {
      return Container(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: AppTheme.border, width: 1)),
          color: AppTheme.bgCard,
        ),
        child: SafeArea(
          top: false,
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

    return Container(
      color: AppTheme.bg,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.transparent,
              borderRadius: BorderRadius.zero,
            ),
            padding: EdgeInsets.zero,
            child: Row(
              children: [
                _NavItem(
                  icon: Icons.home_rounded,
                  label: 'Home',
                  selected: _selectedIndex == 0,
                  onTap: () => setState(() => _selectedIndex = 0),
                ),
                SizedBox(width: 10),
                _NavItem(
                  icon: Icons.upload_rounded,
                  label: 'Send',
                  selected: _selectedIndex == 1,
                  onTap: () => setState(() => _selectedIndex = 1),
                ),
                SizedBox(width: 10),
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
      ),
    );
  }

  Widget _buildDrawer() {
    final isNeo = AppTheme.isNeoPop;
    return Drawer(
      backgroundColor: isNeo ? Colors.black : AppTheme.bgCard,
      shape: isNeo
          ? const RoundedRectangleBorder(borderRadius: BorderRadius.zero)
          : null,
      width: MediaQuery.of(context).size.width * 0.75,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 24),
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
                    child: Icon(
                      Icons.bolt_rounded,
                      color: Colors.white,
                      size: 30,
                    ),
                  ),
                  SizedBox(height: 16),
                  Text(
                    'FluxDrop',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  SizedBox(height: 6),
                  // Live connectivity chip
                  _ConnectivityChip(isOnline: _isOnline, isNeo: isNeo),
                ],
              ),
            ),
            Divider(color: AppTheme.border, height: 1),
            ListTile(
              contentPadding: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              leading: Icon(
                Icons.settings_rounded,
                color: AppTheme.textPrimary,
              ),
              title: Text(
                'Settings',
                style: TextStyle(color: AppTheme.textPrimary, fontSize: 16),
              ),
              onTap: () {
                Navigator.pop(context); // close drawer
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => SettingsPanel()),
                );
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              leading: Icon(Icons.palette_rounded, color: AppTheme.textPrimary),
              title: Text(
                'App Theme',
                style: TextStyle(color: AppTheme.textPrimary, fontSize: 16),
              ),
              subtitle: ValueListenableBuilder<FluxThemeMode>(
                valueListenable: AppTheme.modeNotifier,
                builder: (context, mode, _) => Text(
                  mode.label,
                  style: TextStyle(
                    color: AppTheme.textMuted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              onTap: () {
                Navigator.pop(context);
                Future<void>.delayed(Duration.zero, _showThemeSheet);
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              leading: Icon(
                Icons.info_outline_rounded,
                color: AppTheme.textPrimary,
              ),
              title: Text(
                'About FluxDrop',
                style: TextStyle(color: AppTheme.textPrimary, fontSize: 16),
              ),
              onTap: () {
                Navigator.pop(context);
                // Can show an about dialog here
              },
            ),
            Spacer(),
            Padding(
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
    final isNeo = AppTheme.isNeoPop;
    return AnimatedBuilder(
      animation: animation,
      builder: (_, child) => Transform.translate(
        offset: Offset(0, 20 * (1 - animation.value)),
        child: Opacity(opacity: animation.value, child: child),
      ),
      child: Container(
        decoration: BoxDecoration(
          // NeoPOP: flat bg with hard accent border. Classic: gradient with glow.
          gradient: isNeo ? null : AppTheme.accentGradient,
          color: isNeo ? AppTheme.bgCard : null,
          borderRadius: isNeo ? BorderRadius.zero : BorderRadius.circular(20),
          border: isNeo ? Border.all(color: AppTheme.accent, width: 2) : null,
          boxShadow: isNeo
              ? [
                  BoxShadow(
                    color: Colors.black,
                    offset: Offset(4, 4),
                    blurRadius: 0,
                  ),
                ]
              : [
                  BoxShadow(
                    color: AppTheme.accent.withAlpha(80),
                    blurRadius: 24,
                    offset: Offset(0, 8),
                  ),
                ],
        ),
        padding: EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.fingerprint_rounded,
                  color: isNeo ? AppTheme.accent : Colors.white70,
                  size: 18,
                ),
                SizedBox(width: 6),
                Text(
                  'Your FluxDrop Code',
                  style: Theme.of(context).textTheme.bodySmall!.copyWith(
                    color: isNeo ? AppTheme.textMuted : Colors.white70,
                  ),
                ),
              ],
            ),
            SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    user.shortCode,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 36,
                      fontWeight: FontWeight.w800,
                      color: isNeo ? AppTheme.accent : Colors.white,
                      letterSpacing: 8,
                    ),
                  ),
                ),
                // Copy button — FluxButton in NeoPOP, animated tile in classic
                if (isNeo)
                  FluxButton(
                    onPressed: onCopy,
                    fullWidth: false,
                    tone: copied
                        ? FluxButtonTone.success
                        : FluxButtonTone.primary,
                    padding: EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          copied ? Icons.check_rounded : Icons.copy_rounded,
                          size: 16,
                        ),
                        SizedBox(width: 4),
                        Text(copied ? 'Copied!' : 'Copy'),
                      ],
                    ),
                  )
                else
                  GestureDetector(
                    onTap: onCopy,
                    child: AnimatedContainer(
                      duration: Duration(milliseconds: 200),
                      padding: EdgeInsets.symmetric(
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
                          SizedBox(width: 4),
                          Text(
                            copied ? 'Copied!' : 'Copy',
                            style: TextStyle(
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
            SizedBox(height: 8),
            Text(
              'Share this code with anyone to receive files',
              style: Theme.of(context).textTheme.bodySmall!.copyWith(
                color: isNeo ? AppTheme.textMuted : Colors.white60,
              ),
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
    return FluxSurface(
      color: AppTheme.bgCard,
      borderColor: AppTheme.warning.withAlpha(90),
      padding: EdgeInsets.all(16),
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
                child: Icon(Icons.inbox_rounded, color: AppTheme.warning),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'New transfer from ${transfer.senderCode}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    SizedBox(height: 2),
                    Text(
                      '${transfer.files.length} file(s) • ${formatSize(transfer.totalBytes)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(12),
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
                SizedBox(height: 4),
                Text(
                  'Accept to download this transfer to your device, or decline to reject it.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                SizedBox(height: 8),
                Text(
                  _formatExpiry(transfer.expiresAt),
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall!.copyWith(color: AppTheme.warning),
                ),
              ],
            ),
          ),
          SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final shouldStack =
                  constraints.maxWidth < 320 ||
                  MediaQuery.textScalerOf(context).scale(1) > 1.1;
              final declineButton = FluxButton(
                onPressed: onDecline,
                tone: FluxButtonTone.danger,
                outlined: true,
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.close_rounded, size: 18),
                    SizedBox(width: 6),
                    Flexible(child: Text('Decline', overflow: TextOverflow.fade)),
                  ],
                ),
              );
              final acceptButton = FluxButton(
                onPressed: onAccept,
                tone: FluxButtonTone.success,
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(Icons.check_circle_rounded, size: 18),
                    SizedBox(width: 6),
                    Flexible(child: Text('Accept', overflow: TextOverflow.fade)),
                  ],
                ),
              );

              if (shouldStack) {
                return Column(
                  children: [
                    declineButton,
                    const SizedBox(height: 10),
                    acceptButton,
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: declineButton),
                  const SizedBox(width: 10),
                  Expanded(child: acceptButton),
                ],
              );
            },
          ),
          SizedBox(height: 10),
          FluxButton(
            onPressed: onOpenTransfers,
            fullWidth: false,
            outlined: true,
            tone: FluxButtonTone.neutral,
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Text('Open Transfers for details'),
          ),
        ],
      ),
    );
  }
}

class _ThemeOptionCard extends StatelessWidget {
  final FluxThemeMode mode;
  final FluxThemeMode currentMode;
  final String title;
  final String subtitle;
  final LinearGradient previewGradient;
  final VoidCallback onTap;

  const _ThemeOptionCard({
    required this.mode,
    required this.currentMode,
    required this.title,
    required this.subtitle,
    required this.previewGradient,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = mode == currentMode;
    return InkWell(
      onTap: onTap,
      borderRadius: AppTheme.cardBorderRadius,
      child: FluxSurface(
        color: AppTheme.bgCardElevated,
        borderColor: isSelected ? AppTheme.accent : AppTheme.border,
        padding: EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                gradient: previewGradient,
                borderRadius: BorderRadius.circular(AppTheme.inputRadius),
                border: Border.all(
                  color: AppTheme.isNeoPop ? Colors.black : Colors.transparent,
                ),
              ),
            ),
            SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleLarge),
                  SizedBox(height: 4),
                  Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            SizedBox(width: 12),
            Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
              color: isSelected ? AppTheme.accent : AppTheme.textMuted,
            ),
          ],
        ),
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
      child: FluxSurface(
        padding: EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                gradient: gradient,
                borderRadius: BorderRadius.circular(AppTheme.inputRadius),
              ),
              child: Icon(icon, color: Colors.white, size: 22),
            ),
            SizedBox(height: 12),
            Text(label, style: Theme.of(context).textTheme.titleLarge),
            SizedBox(height: 4),
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
    return FluxSurface(
      padding: EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppTheme.accentGlow,
              borderRadius: BorderRadius.circular(AppTheme.inputRadius),
            ),
            child: Icon(icon, color: AppTheme.accent, size: 20),
          ),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleLarge),
                SizedBox(height: 4),
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
    final isNeo = AppTheme.isNeoPop;
    final iconColor = selected ? Colors.black : AppTheme.textPrimary;
    final labelColor = selected ? Colors.black : AppTheme.textMuted;

    if (isNeo) {
      return Expanded(
        child: SizedBox(
          height: 70,
          child: NeoPopButton(
            color: selected ? AppTheme.accent : AppTheme.bgCard,
            buttonPosition: Position.center,
            parentColor: AppTheme.bg,
            grandparentColor: AppTheme.bg,
            border: Border.all(
              color: selected ? AppTheme.accent : AppTheme.border,
              width: 1.2,
            ),
            onTapUp: onTap,
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon, color: iconColor, size: 21),
                      SizedBox(height: 3),
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: labelColor,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                  if (showBadge)
                    Positioned(
                      top: 2,
                      right: 16,
                      child: Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: AppTheme.success,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.black, width: 1),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: Duration(milliseconds: 180),
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: selected ? AppTheme.accentGlow : Colors.transparent,
                borderRadius: BorderRadius.circular(AppTheme.inputRadius),
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
                        decoration: BoxDecoration(
                          color: AppTheme.accent,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            SizedBox(height: 2),
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

// ─── Live connectivity chip for drawer ───────────────────────────────────────
class _ConnectivityChip extends StatelessWidget {
  final bool isOnline;
  final bool isNeo;

  const _ConnectivityChip({required this.isOnline, required this.isNeo});

  @override
  Widget build(BuildContext context) {
    final dotColor = isOnline ? AppTheme.success : AppTheme.error;
    final textColor = isOnline ? AppTheme.success : AppTheme.error;
    final bgColor =
        isOnline ? AppTheme.successGlow : AppTheme.errorGlow;
    final label = isOnline ? 'Online — Firebase Connected' : 'Offline — No internet';
    final borderColor = isOnline ? AppTheme.success : AppTheme.error;

    final inner = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
        ),
        SizedBox(width: 8),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: textColor,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );

    if (isNeo) {
      return NeoPopCard(
        color: AppTheme.bgCard,
        borderColor: borderColor,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: inner,
        ),
      );
    }

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: inner,
    );
  }
}
