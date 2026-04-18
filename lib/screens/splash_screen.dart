import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import 'home_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _logoController;
  late AnimationController _pulseController;
  late Animation<double> _logoScale;
  late Animation<double> _logoOpacity;
  late Animation<double> _pulseScale;

  String _statusText = 'Initializing...';
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _initializeApp();
  }

  void _setupAnimations() {
    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _logoScale = Tween<double>(begin: 0.7, end: 1.0).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.easeOutBack),
    );
    _logoOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.easeIn),
    );
    _pulseScale = Tween<double>(begin: 1.0, end: 1.12).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _logoController.forward();
  }

  Future<void> _initializeApp() async {
    debugPrint('🚀 [Splash] _initializeApp started');
    try {
      setState(() => _statusText = 'Creating your identity...');
      final authService = AuthService();
      UserModel user;

      if (authService.currentUser != null) {
        debugPrint('🚀 [Splash] Existing Firebase user found — restoring...');
        setState(() => _statusText = 'Restoring your identity...');
        user = (await authService.getCurrentUserModel()) ??
            await authService.signInAnonymously();
      } else {
        debugPrint('🚀 [Splash] No existing user — signing in anonymously...');
        user = await authService.signInAnonymously();
      }

      debugPrint('🚀 [Splash] User ready: ${user.shortCode} (uid: ${user.uid})');

      setState(() => _statusText = 'Setting up notifications...');
      debugPrint('🔔 [Splash] Initializing notifications...');
      await NotificationService().initialize();
      debugPrint('🔔 [Splash] Notifications ready');

      await Future.delayed(const Duration(milliseconds: 600));
      debugPrint('🚀 [Splash] Navigating to HomeScreen');

      if (mounted) {
        Navigator.of(context).pushReplacement(
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => HomeScreen(user: user),
            transitionsBuilder: (_, anim, __, child) => FadeTransition(
              opacity: anim,
              child: child,
            ),
            transitionDuration: const Duration(milliseconds: 400),
          ),
        );
      }
    } catch (e, stack) {
      debugPrint('❌ [Splash] Error: $e');
      debugPrint('❌ [Splash] Stack: $stack');
      setState(() {
        _hasError = true;
        _statusText = 'Failed to initialize: ${e.toString()}';
      });
    }
  }

  @override
  void dispose() {
    _logoController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Animated logo
            AnimatedBuilder(
              animation: Listenable.merge([_logoController, _pulseController]),
              builder: (_, __) => Transform.scale(
                scale: _logoScale.value,
                child: Opacity(
                  opacity: _logoOpacity.value,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Glow ring
                      Transform.scale(
                        scale: _pulseScale.value,
                        child: Container(
                          width: 120,
                          height: 120,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: AppTheme.accentGlow,
                          ),
                        ),
                      ),
                      // Logo container
                      Container(
                        width: 96,
                        height: 96,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: AppTheme.accentGradient,
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.accent.withAlpha(100),
                              blurRadius: 32,
                              spreadRadius: 4,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.bolt_rounded,
                          color: Colors.white,
                          size: 48,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 32),
            // App name
            ShaderMask(
              shaderCallback: (bounds) =>
                  AppTheme.accentGradient.createShader(bounds),
              child: Text(
                'FluxDrop',
                style: Theme.of(context)
                    .textTheme
                    .displayLarge!
                    .copyWith(color: Colors.white),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Real-time file sharing, anywhere',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 64),
            // Status
            if (!_hasError)
              Column(
                children: [
                  SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AppTheme.accent,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _statusText,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              )
            else
              Column(
                children: [
                  const Icon(Icons.error_outline, color: AppTheme.error, size: 32),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      _statusText,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall!
                          .copyWith(color: AppTheme.error),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _hasError = false;
                        _statusText = 'Retrying...';
                      });
                      _initializeApp();
                    },
                    child: const Text('Retry'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
