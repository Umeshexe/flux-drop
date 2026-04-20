import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/theme.dart';
import '../widgets/flux_ui.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            color: AppTheme.textPrimary,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'About FluxDrop',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
      ),
      body: ListView(
        padding: EdgeInsets.all(24),
        children: [
          _buildHeading(context, 'Overview'),
          _buildText(
            context,
            'Built for the NeoSapien Developer Intern Assessment. FluxDrop is a real-time cross-device file sharing app using Flutter and Firebase. The focus for this build was to make the core mobile transfer flow real, stable, and reviewable without pretending unfinished parts were production-ready.',
          ),
          SizedBox(height: 32),

          _buildHeading(context, 'Architecture & Backend'),
          _buildCard(
            context,
            icon: Icons.account_tree_rounded,
            title: 'Transport Choice & Rationale',
            text:
                'I chose a Firebase-based relay path instead of making WebRTC the primary transport. That kept the project lower-risk for the assessment timeline and let me focus on mobile behavior, transfer state, and edge-case handling rather than building and hosting my own relay stack.',
          ),
          SizedBox(height: 12),
          _buildCard(
            context,
            icon: Icons.cloud_sync_rounded,
            title: 'Firestore State Machine',
            text:
                'Firestore snapshot listeners drive the transfer UI instead of a custom WebSocket backend. Transfer documents move through clear states like uploading, uploaded, downloading, completed, and failed so both devices stay in sync in near real time.',
          ),
          SizedBox(height: 12),
          _buildCard(
            context,
            icon: Icons.storage_rounded,
            title: 'Firebase Storage (Relay)',
            text:
                'Firebase Storage is the primary internet relay for file bytes. It gave me a practical way to support larger files and resume-friendly uploads without inventing my own byte-chunk transport layer during the assessment.',
          ),
          SizedBox(height: 12),
          _buildCard(
            context,
            icon: Icons.notifications_active_rounded,
            title: 'Cloud Functions & FCM',
            text:
                'For Android closed-app awareness, a small Node.js Cloud Function watches Firestore state changes and sends FCM notifications when a transfer becomes ready. This covers the receiver notification path without adding a separate custom backend.',
          ),
          SizedBox(height: 32),

          _buildHeading(context, 'Bonus Platform Integrations'),
          _buildCard(
            context,
            icon: Icons.wifi_tethering_rounded,
            title: 'Option #5: Nearby LAN Fast-Path',
            text:
                'The codebase also includes a nearby LAN fast-path. If both devices detect they are on the same `/24` Wi-Fi subnet, the sender can expose a local TCP path and the receiver can connect directly. This is implemented in the repo, but the Firebase relay path is still the primary demo-safe path I would rely on.',
          ),
          SizedBox(height: 12),
          _buildCard(
            context,
            icon: Icons.code_rounded,
            title: 'Option #2: Native MediaStore & Photos',
            text:
                'I implemented native platform-channel work instead of relying only on generic pub.dev wrappers. On Android, media saving uses `MediaStore` for scoped-storage compliance. On iOS, media saving uses `PHPhotoLibrary` to write to Photos.',
          ),
          SizedBox(height: 32),

          _buildHeading(context, 'Robustness & Edge Cases'),
          _buildBullet(
            context,
            'Streaming Large Files: Files are capped at 500 MB and written to disk instead of being held fully in memory.',
          ),
          _buildBullet(
            context,
            'SHA-256 Integrity: Hashes are computed on upload and verified on download before the app treats a file as valid.',
          ),
          _buildBullet(
            context,
            'Anonymous Collision Protection: Short-code creation retries until a unique code is found.',
          ),
          _buildBullet(
            context,
            'App Re-entry Cleanup: A startup recovery pass attempts to clean up or restore stale transfer documents left behind by interrupted sessions.',
          ),
          _buildBullet(
            context,
            'Pre-flight Checks: The app checks local free space through native paths and warns before large transfers on likely metered connections.',
          ),
          _buildBullet(
            context,
            'Cloud Function Push: A Firebase Cloud Function watches transfer state and sends FCM notifications for the Android closed-app path.',
          ),
          _buildBullet(
            context,
            'Transfer Control: Upload/download cancellation is supported, and first-time incoming transfers use an explicit Accept / Decline gate.',
          ),
          SizedBox(height: 32),

          _buildHeading(context, 'Scope Constraints & Honesty'),
          _buildCard(
            context,
            icon: Icons.warning_amber_rounded,
            title: 'What was skipped',
            text:
                '1. True Deep Backgrounding: Full background transfer survival with Android foreground services / iOS background sessions is not implemented.\n\n2. iOS Push Constraints: iOS closed-app push behavior depends on APNs-ready signing and entitlements, which were limited in my local setup.\n\n3. Identity Persistence: The anonymous identity persists while app data remains intact, but I did not build a manual recovery flow after app data clear.\n\n4. LAN Encryption: The local TCP fast-path is not wrapped in its own extra application-layer encryption.',
            isWarning: true,
          ),
          SizedBox(height: 32),

          _buildHeading(context, 'Developer Profile'),
          FluxSurface(
            color: AppTheme.bgCardElevated,
            borderColor: AppTheme.border,
            padding: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildProfileRow(
                  context,
                  Icons.person_rounded,
                  'Umesh Chandra Kadali',
                  null,
                ),
                Divider(color: AppTheme.border, height: 1),
                _buildProfileRow(
                  context,
                  Icons.email_rounded,
                  'kadaliumeshchandra@gmail.com',
                  'mailto:kadaliumeshchandra@gmail.com',
                ),
                Divider(color: AppTheme.border, height: 1),
                _buildProfileRow(
                  context,
                  Icons.phone_rounded,
                  '+91 7619526505',
                  'tel:+917619526505',
                ),
                Divider(color: AppTheme.border, height: 1),
                _buildProfileRow(
                  context,
                  Icons.work_outline_rounded,
                  'LinkedIn: umeshchandrakadali',
                  'https://www.linkedin.com/in/umeshchandrakadali/',
                ),
                Divider(color: AppTheme.border, height: 1),
                _buildProfileRow(
                  context,
                  Icons.code_rounded,
                  'GitLab: Umeshexe',
                  'https://gitlab.com/Umeshexe',
                ),
                Divider(color: AppTheme.border, height: 1),
                _buildProfileRow(
                  context,
                  Icons.code_rounded,
                  'GitHub: Umeshexe',
                  'https://github.com/Umeshexe',
                ),
              ],
            ),
          ),
          SizedBox(height: 48),
        ],
      ),
    );
  }

  Widget _buildProfileRow(
    BuildContext context,
    IconData icon,
    String text,
    String? url,
  ) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: url != null
            ? () async {
                final uri = Uri.parse(url);
                try {
                  final isWeb = uri.scheme == 'http' || uri.scheme == 'https';
                  await launchUrl(
                    uri,
                    mode: isWeb
                        ? LaunchMode.inAppWebView
                        : LaunchMode.externalApplication,
                  );
                } catch (e) {
                  debugPrint('Could not launch $url');
                }
              }
            : null,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            children: [
              Icon(icon, color: AppTheme.accent, size: 18),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  text,
                  style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                    color: url != null ? AppTheme.accent : AppTheme.textPrimary,
                    fontWeight: FontWeight.w500,
                    decoration: url != null ? TextDecoration.underline : null,
                    decorationColor: AppTheme.accent,
                  ),
                ),
              ),
              if (url != null)
                Icon(
                  Icons.open_in_new_rounded,
                  color: AppTheme.textMuted,
                  size: 14,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeading(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleLarge!.copyWith(
          fontWeight: FontWeight.w800,
          color: AppTheme.accent,
        ),
      ),
    );
  }

  Widget _buildText(BuildContext context, String text) {
    return Text(
      text,
      style: Theme.of(context).textTheme.bodyMedium!.copyWith(height: 1.5),
    );
  }

  Widget _buildBullet(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6, right: 12),
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: AppTheme.accent,
                shape: BoxShape.circle,
              ),
            ),
          ),
          Expanded(
            child: Text(
              text,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium!.copyWith(height: 1.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String text,
    bool isWarning = false,
  }) {
    return FluxSurface(
      color: isWarning
          ? AppTheme.warning.withAlpha(20)
          : AppTheme.bgCardElevated,
      borderColor: isWarning ? AppTheme.warning : AppTheme.border,
      padding: EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                color: isWarning ? AppTheme.warning : AppTheme.accent,
                size: 22,
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium!.copyWith(
                    fontWeight: FontWeight.bold,
                    color: isWarning ? AppTheme.warning : AppTheme.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          Text(
            text,
            style: Theme.of(context).textTheme.bodyMedium!.copyWith(
              height: 1.6,
              color: AppTheme.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}
