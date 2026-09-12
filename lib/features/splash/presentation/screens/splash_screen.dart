import 'package:flutter/material.dart';
import 'package:flutter_ai_agent/core/theme/hermes_theme.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/chat_screen.dart';

class SplashScreen extends StatefulWidget {
  final Duration duration;
  final Widget? nextScreen;
  final String splashAsset;
  final VoidCallback? onComplete;

  const SplashScreen({
    super.key,
    this.duration = const Duration(milliseconds: 2500),
    this.nextScreen,
    this.splashAsset = 'assets/images/flames_splash.gif',
    this.onComplete,
  });

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late CurvedAnimation _fadeAnimation;
  bool _hasNavigated = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );

    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: const Interval(0.0, 0.4, curve: Curves.easeIn),
    );

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _navigateToNext();
      }
    });

    if (widget.duration == Duration.zero) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _navigateToNext();
      });
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _fadeAnimation.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _navigateToNext() {
    if (_hasNavigated || !mounted) return;
    _hasNavigated = true;
    _controller.stop();

    if (widget.onComplete != null) {
      widget.onComplete!();
    }

    final targetScreen = widget.nextScreen ?? const ChatScreen();

    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 500),
        pageBuilder: (context, animation, secondaryAnimation) => targetScreen,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: animation,
            child: child,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HermesColors.stage,
      body: Semantics(
        button: true,
        label: 'Skip splash screen',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _navigateToNext,
          child: Center(
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    constraints:
                        const BoxConstraints(maxWidth: 320, maxHeight: 320),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Image.asset(
                      widget.splashAsset,
                      key: const Key('splash_gif_image'),
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) {
                        return Image.asset(
                          'assets/images/flames_logo.png',
                          key: const Key('splash_logo_fallback'),
                          cacheWidth: 320,
                          cacheHeight: 320,
                          fit: BoxFit.contain,
                          errorBuilder: (_, _, _) => const Icon(
                            Icons.bolt,
                            color: HermesColors.neonAccent,
                            size: 80,
                          ),
                        );
                      },
                    ),
                  ),
                const SizedBox(height: 24),
                const Text(
                  'FLAMES',
                  key: Key('splash_app_title'),
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 4.0,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Autonomous Device Workstation',
                  key: Key('splash_app_subtitle'),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    letterSpacing: 1.2,
                    color: HermesColors.inkMuted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  }
}
