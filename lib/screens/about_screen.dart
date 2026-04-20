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
            'Built for the NeoSapien Developer Intern Assessment. A real-time cross-device file sharing app using Flutter and Firebase, featuring the NeoPOP design system. The goal was stability, robustness, and honestly defending architectural choices.',
          ),
          SizedBox(height: 32),

          _buildHeading(context, 'Architecture & Backend'),
          _buildCard(
            context,
            icon: Icons.account_tree_rounded,
            title: 'Transport Choice & Rationale',
            text:
                'I opted for a BaaS approach over WebRTC. True WebRTC across symmetric NATs requires deploying dedicated TURN servers, presenting high timeline risk. Firebase guarantees internet-grade NAT traversal out of the box, letting me focus entirely on complex mobile edge-cases.',
          ),
          SizedBox(height: 12),
          _buildCard(
            context,
            icon: Icons.cloud_sync_rounded,
            title: 'Firestore State Machine',
            text:
                'Instead of building custom WebSockets, Firestore snapshot listeners drive the UI. This creates a pure state machine (uploading, ready, completed) that perfectly satisfies the "arrives within a couple of seconds" rubric with minimal overhead.',
          ),
          SizedBox(height: 12),
          _buildCard(
            context,
            icon: Icons.storage_rounded,
            title: 'Firebase Storage (Relay)',
            text:
                'Chosen to handle the heavy lifting of large payloads. It provides chunked, robust upload streams out-of-the-box, ensuring 500MB+ large files safely transfer over flaky networks without manual byte-chunk management.',
          ),
          SizedBox(height: 12),
          _buildCard(
            context,
            icon: Icons.notifications_active_rounded,
            title: 'Cloud Functions & FCM',
            text:
                'To fulfill the "closed-app notification" requirement on Android, a custom Node.js Cloud Function acts as a side-path. It triggers on Firestore write events and securely dispatches FCM pushes to wake up the receiver.',
          ),
          SizedBox(height: 32),

          _buildHeading(context, 'Bonus Platform Integrations'),
          _buildCard(
            context,
            icon: Icons.wifi_tethering_rounded,
            title: 'Option #5: Nearby LAN Fast-Path',
            text:
                'If both devices detect they are on the same /24 Wi-Fi subnet, they bypass Firebase entirely. The sender binds a raw TCP socket, and the receiver connects instantly to stream files at local network speeds.',
          ),
          SizedBox(height: 12),
          _buildCard(
            context,
            icon: Icons.code_rounded,
            title: 'Option #2: Native MediaStore & Photos',
            text:
                'Implemented a custom MethodChannel instead of relying on generic pub.dev packages. On Android, it interfaces natively with MediaStore for Scoped Storage compliance. On iOS, it uses PHPhotoLibrary to write directly to the Camera Roll.',
          ),
          SizedBox(height: 32),

          _buildHeading(context, 'Robustness & Edge Cases'),
          _buildBullet(
            context,
            'Streaming Large Files: Files up to 500 MB stream directly to disk to prevent Out-Of-Memory (OOM) crashes.',
          ),
          _buildBullet(
            context,
            'SHA-256 Integrity: Hashes are computed dynamically on upload and strictly verified on download across all paths.',
          ),
          _buildBullet(
            context,
            'Anonymous Collision Protection: Handled securely via Firebase transaction logic during on-device provisioning.',
          ),
          _buildBullet(
            context,
            'App Re-entry Cleanup: Implemented a startup scanner (`recoverStaleTransfers`) to gracefully clean up and revert orphaned transfers left suspended by OS process death.',
          ),
          _buildBullet(
            context,
            'Pre-flight Checks: Validates local device free-space via native paths and alerts users before starting 50MB+ transfers on metered connections.',
          ),
          _buildBullet(
            context,
            'Cloud Function Push: A Firebase Cloud Function monitors the state-machine side-path to securely trigger offline push notifications via FCM.',
          ),
          _buildBullet(
            context,
            'Transfer Control: Implemented graceful mid-flight cancellation and an explicit Accept/Decline privacy gate for all incoming requests.',
          ),
          SizedBox(height: 32),

          _buildHeading(context, 'Scope Constraints & Honesty'),
          _buildCard(
            context,
            icon: Icons.warning_amber_rounded,
            title: 'What was skipped',
            text:
                '1. True Deep Backgrounding: OEM battery killers cause unpredictable behavior for Android Foreground Services. Focused on clean state recovery rather than flaky backgrounding.\n\n2. iOS Push Constraints: FCM was integrated perfectly, but true offline remote pushes on a physical iPhone require a paid Apple Developer certificate.\n\n3. Identity Persistence: Short-codes persist until App Data is cleared. On Android, reinstalling generates a new code. On iOS, Firebase stores the UID in the secure Native Keychain, meaning reinstalls natively restore the exact same code. No manual account recovery flow was built, strictly adhering to the prompt\'s "anonymous onboarding" requirement.\n\n4. LAN Encryption: The local TCP fast-path is unencrypted, assuming intrinsic safety on WPA2 subnets.',
            isWarning: true,
          ),
          SizedBox(height: 32),

          _buildHeading(context, 'Developer Profile'),
          FluxSurface(
            color: AppTheme.bgCardElevated,
            borderColor: AppTheme.border,
            padding:
                EdgeInsets.zero, // Padding shifted to InkWells for rippe bounds
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
                  debugPrint('Could not launch \$url');
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
