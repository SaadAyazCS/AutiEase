import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'firebase_options.dart';
import 'navigation/app_route_observer.dart';
import 'navigation/session_navigation.dart';
import 'services/notification_service.dart';
import 'services/payment_deep_link_service.dart';
import 'screens/splash_screen.dart';
import 'utils/app_colors.dart';
import 'widgets/app_responsive_frame.dart';

void main() async {
  if (kReleaseMode) {
    debugPrint = (String? message, {int? wrapWidth}) {};
  }

  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Enable Firestore offline persistence so games and AAC boards work without network
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );

  // Initialize Notification Service
  try {
    await NotificationService.instance.initialize();
  } catch (e) {
    debugPrint('Failed to initialize notifications: $e');
  }

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ),
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'AutiEase',
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        final media = MediaQuery.of(context);
        final userTextScale = media.textScaler.scale(1);
        final clampedTextScale = userTextScale.clamp(0.9, 1.15).toDouble();
        return MediaQuery(
          data: media.copyWith(textScaler: TextScaler.linear(clampedTextScale)),
          child: AppResponsiveFrame(child: child ?? const SizedBox.shrink()),
        );
      },
      navigatorObservers: [appRouteObserver],
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primaryBlue,
          brightness: Brightness.light,
        ),
        textTheme: GoogleFonts.nunitoTextTheme(Theme.of(context).textTheme),
        useMaterial3: true,
        scaffoldBackgroundColor: AppColors.skyBlue,
      ),
      home: const SplashScreen(),
      onUnknownRoute: (settings) {
        final name = settings.name ?? '';
        PaymentDeepLinkService.instance.tryHandleRoute(name);
        // Return a transparent, zero-duration route so the navigator is satisfied,
        // and pop it immediately on the next frame so it doesn't affect the stack.
        return PageRouteBuilder<void>(
          settings: settings,
          pageBuilder: (context, _, __) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (Navigator.canPop(context)) {
                Navigator.pop(context);
              }
            });
            return const SizedBox.shrink();
          },
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          opaque: false,
          barrierDismissible: true,
        );
      },
    );
  }
}
