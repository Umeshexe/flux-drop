import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/theme.dart';
import '../widgets/flux_ui.dart';

class SettingsPanel extends StatefulWidget {
  const SettingsPanel({super.key});

  @override
  State<SettingsPanel> createState() => _SettingsPanelState();
}

class _SettingsPanelState extends State<SettingsPanel>
    with SingleTickerProviderStateMixin {
  String _version = '–';
  String _buildNumber = '–';
  String _cacheSize = 'Calculating…';
  String? _defaultSavePath;
  bool _autoClean = true;
  bool _isClearing = false;
  late AnimationController _fadeCtrl;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 500),
    )..forward();
    _fade = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _loadAll();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    await Future.wait([_loadVersion(), _loadPrefs(), _calcCacheSize()]);
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() {
        _version = info.version;
        _buildNumber = info.buildNumber;
      });
    }
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _autoClean = prefs.getBool('autoClean') ?? true;
        _defaultSavePath = prefs.getString('defaultSavePath');
      });
    }
  }

  Future<void> _calcCacheSize() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final fluxDir = Directory('${dir.path}/FluxDrop');
      if (!await fluxDir.exists()) {
        setState(() => _cacheSize = '0 B');
        return;
      }
      int total = 0;
      await for (final e in fluxDir.list(recursive: true)) {
        if (e is File) total += await e.length();
      }
      setState(() => _cacheSize = _fmt(total));
    } catch (_) {
      setState(() => _cacheSize = 'Unknown');
    }
  }

  Future<void> _clearCache() async {
    setState(() => _isClearing = true);
    try {
      final dir = await getApplicationDocumentsDirectory();
      final fluxDir = Directory('${dir.path}/FluxDrop');
      if (await fluxDir.exists()) await fluxDir.delete(recursive: true);
      await _calcCacheSize();
      if (mounted) _toast('Cache cleared!', AppTheme.success);
    } catch (e) {
      if (mounted) _toast('Failed: $e', AppTheme.error);
    } finally {
      if (mounted) setState(() => _isClearing = false);
    }
  }

  Future<void> _pickSavePath() async {
    final path = await FilePicker.getDirectoryPath(
      dialogTitle: 'Choose download folder',
    );
    if (path == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('defaultSavePath', path);
    setState(() => _defaultSavePath = path);
    _toast('Default folder saved!', AppTheme.success);
  }

  Future<void> _resetSavePath() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('defaultSavePath');
    setState(() => _defaultSavePath = null);
    _toast('Reset to Share Sheet mode', AppTheme.accent);
  }

  Future<void> _toggleAutoClean(bool val) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('autoClean', val);
    setState(() => _autoClean = val);
  }

  void _toast(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: TextStyle(color: Colors.white)),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: Duration(seconds: 2),
      ),
    );
  }

  String _fmt(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  String get _savePathLabel {
    if (_defaultSavePath == null) return 'Not set';
    final parts = _defaultSavePath!.split('/');
    return parts.length > 1 ? '.../${parts.last}' : _defaultSavePath!;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: FadeTransition(
        opacity: _fade,
        child: CustomScrollView(
          slivers: [
            // ─── Gradient header ──────────────────────────────────────────
            SliverToBoxAdapter(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF1A1A2E), Color(0xFF0A0A0F)],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(20, 12, 16, 28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            IconButton(
                              icon: Icon(
                                Icons.arrow_back_ios_new_rounded,
                                color: AppTheme.textMuted,
                                size: 18,
                              ),
                              onPressed: () => Navigator.pop(context),
                            ),
                            Spacer(),
                            Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.accentGlow,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'v$_version',
                                style: TextStyle(
                                  color: AppTheme.accent,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 12),
                        Row(
                          children: [
                            Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                gradient: AppTheme.accentGradient,
                                borderRadius: AppTheme.cardBorderRadius,
                                boxShadow: [
                                  BoxShadow(
                                    color: AppTheme.accent.withAlpha(80),
                                    blurRadius: 16,
                                    offset: Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Icon(
                                Icons.settings_rounded,
                                color: Colors.white,
                                size: 26,
                              ),
                            ),
                            SizedBox(width: 16),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Settings',
                                  style: TextStyle(
                                    fontSize: 26,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.textPrimary,
                                  ),
                                ),
                                Text(
                                  Platform.isIOS
                                      ? 'iOS • FluxDrop ${"v$_version"}'
                                      : 'Android • FluxDrop ${"v$_version"}',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: AppTheme.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // ─── Body sections ────────────────────────────────────────────
            SliverPadding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 40),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  // ── Download Location ──────────────────────────────────
                  _SectionLabel('Download Location'),
                  _Card(
                    children: [
                      if (Platform.isAndroid) ...[
                        _Tile(
                          icon: Icons.folder_rounded,
                          iconColor: AppTheme.accent,
                          title: 'Default Save Folder',
                          subtitle: _defaultSavePath != null
                              ? _savePathLabel
                              : 'Tap to choose a folder',
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_defaultSavePath != null)
                                Container(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppTheme.successGlow,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    'Set',
                                    style: TextStyle(
                                      color: AppTheme.success,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                )
                              else
                                Container(
                                  padding: EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: AppTheme.bgCardElevated,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    'None',
                                    style: TextStyle(
                                      color: AppTheme.textMuted,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              SizedBox(width: 8),
                              Icon(
                                Icons.chevron_right_rounded,
                                color: AppTheme.textMuted,
                                size: 20,
                              ),
                            ],
                          ),
                          onTap: _pickSavePath,
                        ),
                        if (_defaultSavePath != null) ...[
                          _Divider(),
                          _Tile(
                            icon: Icons.folder_off_rounded,
                            iconColor: AppTheme.error,
                            title: 'Reset Folder',
                            subtitle: 'Go back to Share Sheet each time',
                            trailing: Icon(
                              Icons.chevron_right_rounded,
                              color: AppTheme.textMuted,
                              size: 20,
                            ),
                            onTap: _resetSavePath,
                          ),
                        ],
                      ] else ...[
                        // iOS — friendly, not scary
                        _Tile(
                          icon: Icons.folder_rounded,
                          iconColor: AppTheme.accent,
                          title: 'Default Save Folder',
                          subtitle: 'Files App via Share Sheet',
                          trailing: Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: AppTheme.accentGlow,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'Auto',
                              style: TextStyle(
                                color: AppTheme.accent,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                        _Divider(),
                        _Tile(
                          icon: Icons.info_outline_rounded,
                          iconColor: AppTheme.textMuted,
                          title: 'How it works',
                          subtitle:
                              'After downloading, a share sheet appears.\nTap "Save to Files" to choose any folder.',
                        ),
                      ],
                    ],
                  ),

                  // ── Storage & Cache ────────────────────────────────────
                  _SectionLabel('Storage & Cache'),
                  _Card(
                    children: [
                      _Tile(
                        icon: Icons.storage_rounded,
                        iconColor: AppTheme.accent,
                        title: 'Temp Cache',
                        subtitle: 'Files awaiting the Share Sheet',
                        trailing: Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.bgCardElevated,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            _cacheSize,
                            style: TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      _Divider(),
                      _Tile(
                        icon: Icons.cleaning_services_rounded,
                        iconColor: AppTheme.warning,
                        title: 'Clear Cache',
                        subtitle: 'Delete all temporary download files',
                        trailing: _isClearing
                            ? SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppTheme.warning,
                                ),
                              )
                            : Icon(
                                Icons.chevron_right_rounded,
                                color: AppTheme.textMuted,
                                size: 20,
                              ),
                        onTap: _isClearing ? null : _clearCache,
                      ),
                      _Divider(),
                      _ToggleTile(
                        icon: Icons.auto_delete_rounded,
                        iconColor: AppTheme.success,
                        title: 'Auto-Clean',
                        subtitle: 'Delete temp files after sharing',
                        value: _autoClean,
                        onChanged: _toggleAutoClean,
                      ),
                    ],
                  ),

                  // ── Security ──────────────────────────────────────────
                  _SectionLabel('Security'),
                  _Card(
                    children: [
                      _Tile(
                        icon: Icons.lock_rounded,
                        iconColor: AppTheme.success,
                        title: 'Encryption',
                        subtitle: 'TLS in transit · SHA-256 integrity check',
                        trailing: _Badge(
                          'Always on',
                          AppTheme.success,
                          AppTheme.successGlow,
                        ),
                      ),
                      _Divider(),
                      _Tile(
                        icon: Icons.timer_rounded,
                        iconColor: AppTheme.warning,
                        title: 'Transfer Expiry',
                        subtitle: 'Files auto-expire after 24 hours',
                        trailing: _Badge(
                          '24h TTL',
                          AppTheme.warning,
                          AppTheme.warning.withAlpha(30),
                        ),
                      ),
                      _Divider(),
                      _Tile(
                        icon: Icons.cloud_upload_rounded,
                        iconColor: AppTheme.accent,
                        title: 'Max File Size',
                        subtitle: 'Per transfer limit',
                        trailing: _Badge(
                          '500 MB',
                          AppTheme.accent,
                          AppTheme.accentGlow,
                        ),
                      ),
                    ],
                  ),

                  // ── About ─────────────────────────────────────────────
                  _SectionLabel('About FluxDrop'),
                  _Card(
                    children: [
                      _Tile(
                        icon: Icons.bolt_rounded,
                        iconColor: AppTheme.accent,
                        title: 'FluxDrop',
                        subtitle: 'Real-time file sharing · Firebase powered',
                      ),
                      _Divider(),
                      _Tile(
                        icon: Icons.tag_rounded,
                        iconColor: AppTheme.textMuted,
                        title: 'Version',
                        subtitle: 'v$_version (build $_buildNumber)',
                      ),
                      _Divider(),
                      _Tile(
                        icon: Platform.isIOS
                            ? Icons.phone_iphone_rounded
                            : Icons.phone_android_rounded,
                        iconColor: AppTheme.textSecondary,
                        title: 'Platform',
                        subtitle: Platform.isIOS ? 'iOS' : 'Android',
                        trailing: _Badge(
                          Platform.isIOS ? 'iOS' : 'Android',
                          AppTheme.textSecondary,
                          AppTheme.bgCardElevated,
                        ),
                      ),
                    ],
                  ),

                  SizedBox(height: 16),

                  // Footer
                  Center(
                    child: Text(
                      'FluxDrop v$_version · Made with ♥',
                      style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                    ),
                  ),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Private helpers ──────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(4, 24, 0, 8),
    child: Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: AppTheme.textMuted,
        letterSpacing: 1.3,
      ),
    ),
  );
}

class _Card extends StatelessWidget {
  final List<Widget> children;
  const _Card({required this.children});

  @override
  Widget build(BuildContext context) =>
      FluxSurface(child: Column(children: children));
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      Divider(color: AppTheme.border, height: 1, indent: 56);
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _Tile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: AppTheme.cardBorderRadiusLarge,
    child: Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: iconColor.withAlpha(25),
              borderRadius: BorderRadius.circular(AppTheme.inputRadius),
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textMuted,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) ...[SizedBox(width: 10), trailing!],
        ],
      ),
    ),
  );
}

class _ToggleTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToggleTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: iconColor.withAlpha(25),
            borderRadius: BorderRadius.circular(AppTheme.inputRadius),
          ),
          child: Icon(icon, color: iconColor, size: 18),
        ),
        SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
              SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
              ),
            ],
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: AppTheme.accent,
          trackOutlineColor: WidgetStateProperty.all(AppTheme.border),
        ),
      ],
    ),
  );
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  final Color bg;
  const _Badge(this.label, this.color, this.bg);

  @override
  Widget build(BuildContext context) => Container(
    padding: EdgeInsets.symmetric(horizontal: 9, vertical: 4),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(AppTheme.inputRadius),
    ),
    child: Text(
      label,
      style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700),
    ),
  );
}
