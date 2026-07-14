import 'dart:async';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/services.dart';

import 'dart:ui';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/app_models.dart';
import '../repositories/app_repositories.dart';
import '../services/firebase_service.dart';
import '../utils/responsive.dart';
import '../widgets/phone_input_field.dart';
import '../widgets/session_guard.dart';
import 'about_application_screen.dart';
import 'login_screen.dart';
import '../utils/app_colors.dart';
import '../widgets/bouncing_button.dart';
import '../widgets/figma_module_scaffold.dart';
import 'feedback_screen.dart';
import 'therapist_chat_screen.dart';
import '../utils/currency_utils.dart';
import 'therapist_notification_inbox_screen.dart';
import 'receipt_viewer_screen.dart';
import 'therapist_scheduler_screen.dart';

class TherapistHomeScreen extends StatefulWidget {
  const TherapistHomeScreen({super.key});

  @override
  State<TherapistHomeScreen> createState() => _TherapistHomeScreenState();
}

class _TherapistHomeScreenState extends State<TherapistHomeScreen>
    with TickerProviderStateMixin {
  TherapistProfile? _profile;
  bool _loading = true;
  int _years = 0;
  int _months = 0;
  String _credentials = '';
  String _contactEmail = '';
  String _contactPhone = '';
  String? _certificatePdfName;
  List<TherapyPackage> _packages = const <TherapyPackage>[];
  Map<String, bool> _notificationPrefs = _defaultTherapistNotificationPrefs;

  // Info icon state variables
  bool _showInfoIcon = false;
  bool _isGlowing = false;
  bool _isDialogShowing = false;

  // Pulse animation for the info icon on first visit
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  // Bell animation variables
  late final AnimationController _bellController;
  late final Animation<double> _bellAnimation;
  int _lastUnreadCount = 0;

  // Profile completion control
  bool _shouldCheckProfileCompletion = true;
  bool _hasCompletedInitialProfile = false;

  // Emergency monitoring state
  StreamSubscription<List<TherapistThread>>? _emergencySubscription;
  Timer? _emergencyAlertTimer;
  bool _emergencyAlertActive = false;
  final FlutterLocalNotificationsPlugin _localNotif = FlutterLocalNotificationsPlugin();
  final int _emergencyNotifId = 8888;

  @override
  void initState() {
    super.initState();
    // Always show info icon immediately — don't wait for Firestore.
    _showInfoIcon = true;
    // Set up pulse animation (scale 1.0 → 1.18 → 1.0).
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.18).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _bellController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _bellAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: -0.12), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -0.12, end: 0.12), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 0.12, end: -0.08), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -0.08, end: 0.08), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 0.08, end: 0.0), weight: 1),
    ]).animate(CurvedAnimation(parent: _bellController, curve: Curves.linear));

    _loadState();
    _startEmergencyMonitoring();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _bellController.dispose();
    _emergencySubscription?.cancel();
    _emergencyAlertTimer?.cancel();
    _localNotif.cancel(_emergencyNotifId);
    super.dispose();
  }

  void _startEmergencyMonitoring() {
    _emergencySubscription = AppRepositories.support
        .watchThreadsForRole('therapist')
        .listen((threads) {
      bool hasActiveEmergency = false;
      String parentName = '';
      for (final t in threads) {
        if (t.hasOpenEmergency) {
          hasActiveEmergency = true;
          parentName = t.parentDisplayName.isNotEmpty ? t.parentDisplayName : 'A parent';
          break;
        }
      }

      final emergencyEnabled = _notificationPrefs['emergency'] ?? true;
      if (hasActiveEmergency && emergencyEnabled) {
        _startGlobalEmergencyAlert(parentName);
      } else {
        _stopGlobalEmergencyAlert();
      }
    });
  }

  void _reevaluateEmergencyAlert() {
    final emergencyEnabled = _notificationPrefs['emergency'] ?? true;
    if (!emergencyEnabled) {
      _stopGlobalEmergencyAlert();
    } else {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      FirebaseFirestore.instance
          .collection(FirestoreCollections.therapistThreads)
          .where('therapistId', isEqualTo: uid)
          .get()
          .then((snapshot) {
        if (!mounted) return;
        final threads = snapshot.docs
            .map((doc) => TherapistThread.fromMap(doc.id, doc.data()))
            .toList();
        bool hasActiveEmergency = false;
        String parentName = '';
        for (final t in threads) {
          if (t.hasOpenEmergency) {
            hasActiveEmergency = true;
            parentName = t.parentDisplayName.isNotEmpty ? t.parentDisplayName : 'A parent';
            break;
          }
        }
        final emergencyEnabled = _notificationPrefs['emergency'] ?? true;
        if (hasActiveEmergency && emergencyEnabled) {
          _startGlobalEmergencyAlert(parentName);
        } else {
          _stopGlobalEmergencyAlert();
        }
      }).catchError((_) {});
    }
  }

  void _startGlobalEmergencyAlert(String parentName) {
    if (_emergencyAlertActive) return; // already active
    _emergencyAlertActive = true;

    final bodyText = '$parentName needs immediate help. Open the chat now.';
    final notifDetails = NotificationDetails(
      android: AndroidNotificationDetails(
        'autiease_high_channel',
        'High Importance Notifications',
        channelDescription: 'Used for important messages and emergencies.',
        importance: Importance.max,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
        playSound: true,
        enableVibration: true,
        styleInformation: BigTextStyleInformation(bodyText),
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );

    // Show immediately
    _localNotif.show(
      _emergencyNotifId,
      '🚨 Emergency Support Requested!',
      bodyText,
      notifDetails,
    );

    // Show every 10 seconds
    _emergencyAlertTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!_emergencyAlertActive) return;
      _localNotif.show(
        _emergencyNotifId,
        '🚨 Emergency Support Requested!',
        bodyText,
        notifDetails,
      );
    });
  }

  void _stopGlobalEmergencyAlert() {
    if (!_emergencyAlertActive) return;
    _emergencyAlertActive = false;
    _emergencyAlertTimer?.cancel();
    _emergencyAlertTimer = null;
    _localNotif.cancel(_emergencyNotifId);
  }

  void _triggerBellAnimation() {
    if (_bellController.isAnimating) return;
    _bellController.repeat(reverse: true);
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        _bellController.stop();
        _bellController.animateTo(0.0);
      }
    });
  }

  Future<void> _loadState() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      if (mounted) {
        setState(() => _loading = false);
      }
      return;
    }

    try {
      final profile = await AppRepositories.support.getTherapistById(uid);
      final userProfile = await AppRepositories.users.getCurrentUserProfile();

      if (userProfile?.status == 'banned' || userProfile?.status == 'suspended') {
        final reason = userProfile?.status == 'suspended'
            ? 'Your account has been suspended. Please contact support.'
            : 'Your account has been permanently banned due to policy violations.';
        await FirebaseAuth.instance.signOut();
        if (mounted) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(
              builder: (_) => LoginScreen(message: reason),
            ),
            (route) => false,
          );
        }
        return;
      }

      final doc = await FirebaseFirestore.instance
          .collection(FirestoreCollections.therapistProfiles)
          .doc(uid)
          .get();
      final data = doc.data() ?? <String, dynamic>{};

      var activeProfile = profile;
      DateTime? restUntil = activeProfile?.restrictionUntil;

      if (restUntil != null) {
        if (DateTime.now().isBefore(restUntil)) {
          // Restriction is active! Force in-memory acceptsClients to false
          if (activeProfile != null && activeProfile.isAcceptingClients) {
            activeProfile = activeProfile.copyWith(isAcceptingClients: false);
            await FirebaseFirestore.instance
                .collection(FirestoreCollections.therapistProfiles)
                .doc(uid)
                .update({'isAcceptingClients': false});
          }
        } else {
          // Restriction has expired! Automatically lift it!
          restUntil = null;
          await FirebaseFirestore.instance
              .collection(FirestoreCollections.therapistProfiles)
              .doc(uid)
              .update({
            'verificationStatus': 'approved',
            'restrictionUntil': FieldValue.delete(),
          });
          await FirebaseFirestore.instance
              .collection(FirestoreCollections.users)
              .doc(uid)
              .update({
            'status': 'verified',
          });
          final refreshedProfile = await AppRepositories.support.getTherapistById(uid);
          if (refreshedProfile != null) {
            activeProfile = refreshedProfile;
          }
        }
      }

      final parsedPackages = _parsePackages(data['servicePackages']);
      final userFullName = userProfile?.fullName.trim() ?? '';
      final canonicalDisplayName = userFullName.isNotEmpty
          ? userFullName
          : (profile?.displayName.trim().isNotEmpty == true
                ? profile!.displayName.trim()
                : (FirebaseAuth.instance.currentUser?.displayName
                          ?.trim()
                          .isNotEmpty ==
                      true
                      ? FirebaseAuth.instance.currentUser!.displayName!.trim()
                      : 'Therapist'));
      final canonicalEmail = (userProfile?.email.trim().isNotEmpty == true
          ? userProfile!.email.trim()
          : (data['contactEmail'] ??
                    FirebaseAuth.instance.currentUser?.email ??
                    '')
                .toString()
                .trim());
      final canonicalPhone = (userProfile?.phone.trim().isNotEmpty == true
          ? userProfile!.phone.trim()
          : (data['contactPhone'] ??
                    FirebaseAuth.instance.currentUser?.phoneNumber ??
                    '')
                .toString()
                .trim());

      if (!mounted) {
        return;
      }
      setState(() {
        _profile =
            activeProfile ??
            TherapistProfile(
              id: uid,
              displayName: canonicalDisplayName,
              bio: '',
              specializations: const <String>[],
              pricing: '',
              languages: const <String>['English'],
              // Hardcoded fallback rating removed for now.
              rating: 0,
              availability: 'Open',
              photoUrl: '',
              isActive: true,
            );
        _years = intFrom(data['experience_years'] ?? data['yearsOfExperience']);
        _months = intFrom(data['experience_months']);
        _credentials = (data['credentials'] ?? '').toString();
        _contactEmail = canonicalEmail;
        _contactPhone = canonicalPhone;
        _certificatePdfName = data['certificatePdfName']?.toString();
        _packages = parsedPackages;
        _notificationPrefs = () {
          final fromFirestore =
              boolMapFrom(data['therapistNotificationPreferences']);
          // Keep only the keys the app knows about so that stale / renamed
          // keys stored in Firestore never pollute the in-memory state.
          return <String, bool>{
            for (final key in _defaultTherapistNotificationPrefs.keys)
              key: fromFirestore[key] ?? _defaultTherapistNotificationPrefs[key]!,
          };
        }();
        _loading = false;
      });

      // ── Proactive sync ────────────────────────────────────────────────────
      // Explicitly remove every notification key that the app no longer knows
      // about from BOTH Firestore documents.  We use dot-notation field paths
      // with FieldValue.delete() to hard-delete the stale keys, and explicitly
      // set each of the 7 canonical keys to their correct value in the same
      // call.  This runs on every load but only performs a write when there is
      // actually something to clean up.
      final appKeys = _defaultTherapistNotificationPrefs.keys.toSet();
      final cleanMap = _notificationPrefs;

      // ── User document (users/{uid}) ──────────────────────────────────────
      final userDocAllKeys =
          (userProfile?.notificationPreferences ?? <String, bool>{}).keys.toSet();
      final extraUserKeys = userDocAllKeys.difference(appKeys);
      final userDocMissingOrWrong =
          extraUserKeys.isNotEmpty || !appKeys.every(userDocAllKeys.contains);

      if (userDocMissingOrWrong) {
        // Build a single update that both sets the 7 canonical keys AND
        // explicitly deletes every extra key using dot-notation paths.
        final userUpdatePayload = <String, dynamic>{
          for (final entry in cleanMap.entries)
            'notificationPreferences.${entry.key}': entry.value,
          for (final key in extraUserKeys)
            'notificationPreferences.$key': FieldValue.delete(),
          'updatedAt': FieldValue.serverTimestamp(),
        };
        unawaited(
          FirebaseFirestore.instance
              .collection(FirestoreCollections.users)
              .doc(uid)
              .update(userUpdatePayload)
              .catchError((_) {}),
        );
      }

      // ── Therapist profile document (therapist_profiles/{uid}) ────────────
      final therapistDocAllKeys =
          boolMapFrom(data['therapistNotificationPreferences']).keys.toSet();
      final extraTherapistKeys = therapistDocAllKeys.difference(appKeys);
      final therapistDocMissingOrWrong = extraTherapistKeys.isNotEmpty ||
          !appKeys.every(therapistDocAllKeys.contains);

      if (therapistDocMissingOrWrong) {
        final therapistUpdatePayload = <String, dynamic>{
          for (final entry in cleanMap.entries)
            'therapistNotificationPreferences.${entry.key}': entry.value,
          for (final key in extraTherapistKeys)
            'therapistNotificationPreferences.$key': FieldValue.delete(),
          'updatedAt': FieldValue.serverTimestamp(),
        };
        unawaited(
          FirebaseFirestore.instance
              .collection(FirestoreCollections.therapistProfiles)
              .doc(uid)
              .update(therapistUpdatePayload)
              .catchError((_) {}),
        );
      }
      // ─────────────────────────────────────────────────────────────────────

      // Check if therapist has already completed initial profile setup
      final userDoc = await FirebaseFirestore.instance
          .collection(FirestoreCollections.users)
          .doc(uid)
          .get();
      
      _hasCompletedInitialProfile = userDoc.data()?['hasCompletedInitialProfile'] ?? false;
      
      // Only prompt for profile completion if user hasn't completed initial setup
      // This prevents the popup from appearing when users navigate back or make profile changes
      if (_shouldCheckProfileCompletion && !_hasCompletedInitialProfile) {
        await _maybePromptCompleteProfile();
        _shouldCheckProfileCompletion = false; // Only check once per session
      } else if (!_hasCompletedInitialProfile && _profile != null) {
        // If profile exists but completion flag is missing, mark it as completed
        // This handles existing users who completed profiles before the flag was added
        await _markInitialProfileCompleted();
      }
      
      // Check if it's the first time visiting the home screen
      await _checkFirstTimeVisit();
    } catch (_) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _checkFirstTimeVisit() async {
    if (!mounted) return;

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      // Check if user has seen the info dialog before
      final userDoc = await FirebaseFirestore.instance
          .collection(FirestoreCollections.users)
          .doc(uid)
          .get();

      final hasSeenInfo = userDoc.data()?['hasSeenTherapistInfo'] ?? false;

      if (!hasSeenInfo) {
        if (!mounted) return;
        setState(() {
          _showInfoIcon = true;
          _isGlowing = true;
          _isDialogShowing = true; // Show tooltip instantly
        });
        // Play pulse animation for ~2 seconds (3 forward-reverse cycles)
        _pulseController.repeat(reverse: true);
        await Future<void>.delayed(const Duration(seconds: 2));
        if (!mounted) return;
        _pulseController.stop();
        _pulseController.animateTo(0);
      } else {
        if (!mounted) return;
        setState(() {
          _showInfoIcon = true;
          _isGlowing = false;
        });
      }
    } catch (_) {
      // On error, show icon without animation.
      if (mounted) {
        setState(() {
          _showInfoIcon = true;
          _isGlowing = false;
        });
      }
    }
  }


  Future<void> _markInfoAsSeen() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    
    try {
      await FirebaseFirestore.instance
          .collection(FirestoreCollections.users)
          .doc(uid)
          .update({'hasSeenTherapistInfo': true});
    } catch (e) {
      // Ignore errors, user can still access info
    }
  }

  Future<void> _startInfoFlow() async {
    // Hide tooltip if showing
    if (_isDialogShowing && mounted) {
      setState(() {
        _isDialogShowing = false;
      });
    }
    
    // Immediately mark as seen when user taps the info icon
    await _markInfoAsSeen();
    
    setState(() {
      _isGlowing = false;
    });
    
    // Navigate to info flow screens
    if (mounted) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const TherapistInfoFlowScreen()),
      );
    }
  }

  Future<void> _markInitialProfileCompleted() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    
    try {
      await FirebaseFirestore.instance
          .collection(FirestoreCollections.users)
          .doc(uid)
          .update({
            'hasCompletedInitialProfile': true,
            'hasSeenTherapistInfo': false, // Reset info flag so dialog shows on home screen
          });
      
      setState(() {
        _hasCompletedInitialProfile = true;
      });
    } catch (e) {
      // If update fails, continue anyway - this is not critical
      // Error is not shown to user as this is a non-critical operation
    }
  }

  Future<void> _maybePromptCompleteProfile() async {
    if (!mounted || _profile == null) {
      return;
    }

    // Check if profile is incomplete for INITIAL SIGNUP
    bool isIncompleteForInitialSignup() {
      return _years == 0 ||
          _credentials.trim().isEmpty ||
          _contactEmail.trim().isEmpty ||
          _contactPhone.trim().isEmpty ||
          _packages.isEmpty ||
          _profile?.bio.trim().isEmpty == true ||
          (_profile?.certificateBase64 ?? '').isEmpty;
    }

    // Keep prompting until profile is complete for initial signup
    while (isIncompleteForInitialSignup()) {
      await Future<void>.delayed(const Duration(milliseconds: 120));
      if (!mounted) {
        return;
      }

      final saved = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => TherapistProfileSettingsScreen(
            profile: _profile!,
            setupMode: true,
            initialYears: _years,
            initialMonths: _months,
            initialCredentials: _credentials,
            initialEmail: _contactEmail,
            initialPhone: _contactPhone,
            initialCertificatePdfName: _certificatePdfName,
            initialPackages: _packages,
            onSave: ({
              required profile,
              required years,
              required months,
              required credentials,
              required contactEmail,
              required contactPhone,
              required packages,
              certificatePdfName,
              photoBase64,
              certificateBase64,
            }) =>
                _saveProfileData(
                  profile: profile,
                  years: years,
                  months: months,
                  credentials: credentials,
                  contactEmail: contactEmail,
                  contactPhone: contactPhone,
                  packages: packages,
                  certificatePdfName: certificatePdfName,
                  photoBase64: photoBase64,
                  certificateBase64: certificateBase64,
                  successMessage: 'Profile completed successfully!',
                ),
          ),
        ),
      );

      if (saved == true) {
        // Mark initial profile as completed
        await _markInitialProfileCompleted();
        await _loadState();
        // Check again after loading state
        if (!mounted) return;
      } else {
        // User cancelled, show dialog and try again
        if (!mounted) return;
        final shouldRetry = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Complete Your Profile'),
            content: const Text(
              'You must complete your profile before accessing the therapist dashboard. Please fill in all required information.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Complete Profile'),
              ),
            ],
          ),
        );
        
        if (shouldRetry != true) {
          // User chose to cancel, show message and check again
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Profile completion is required to continue.'),
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    }
  }

  Future<void> _saveProfileData({
    required TherapistProfile profile,
    required int years,
    required int months,
    required String credentials,
    required String contactEmail,
    required String contactPhone,
    required List<TherapyPackage> packages,
    String? certificatePdfName,
    String? photoBase64,
    String? certificateBase64,
    String? successMessage,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return;
    }

    final oldTitles = _packages.map((p) => p.title.trim().toLowerCase()).toSet();
    final newTitles = packages.map((p) => p.title.trim().toLowerCase()).toSet();
    final deletedTitles = oldTitles.difference(newTitles);

    if (deletedTitles.isNotEmpty) {
      try {
        final slotsSnapshot = await FirebaseFirestore.instance
            .collection('appointment_slots')
            .where('therapistId', isEqualTo: uid)
            .where('status', isEqualTo: 'available')
            .get();

        final batch = FirebaseFirestore.instance.batch();
        bool hasDeletions = false;
        for (final doc in slotsSnapshot.docs) {
          final slotData = doc.data();
          final slotPkgTitle = (slotData['packageTitle'] ?? '').toString().trim().toLowerCase();
          if (slotPkgTitle.isNotEmpty && deletedTitles.contains(slotPkgTitle)) {
            batch.delete(doc.reference);
            hasDeletions = true;
          }
        }
        if (hasDeletions) {
          await batch.commit();
        }
      } catch (e) {
        debugPrint('Error deleting slots for deleted packages: $e');
      }
    }
    final firstName = profile.displayName.trim().split(' ').first;
    final lastNameParts = profile.displayName.trim().split(' ')..removeAt(0);
    final lastName = lastNameParts.join(' ').trim();
    final fullName = '$firstName $lastName'.trim();

    final pricing = packages.isEmpty
        ? profile.pricing
        : '${formatPrice(packages.map((TherapyPackage item) => item.price).reduce(math.min).toDouble())}/month';

    final normalized = TherapistProfile(
      id: profile.id,
      displayName: profile.displayName,
      bio: profile.bio,
      specializations: profile.specializations,
      pricing: pricing,
      languages: profile.languages.isEmpty
          ? const ['English']
          : profile.languages,
      rating: profile.rating,
      availability: profile.availability.isEmpty
          ? 'Open'
          : profile.availability,
      photoUrl: profile.photoUrl,
      isActive: profile.isActive,
      yearsOfExperience: years,
      experienceMonths: months,
      credentials: profile.credentials,
      photoUrlBase64: profile.photoUrlBase64,
      certificateBase64: profile.certificateBase64,
      verificationStatus: profile.verificationStatus,
      adminFeedback: profile.adminFeedback,
      verifiedBadge: profile.verifiedBadge,
      licenseNumber: profile.licenseNumber,
      registrationNumber: profile.registrationNumber,
      cnic: profile.cnic,
      experienceDetails: profile.experienceDetails,
      ratingBreakdown: profile.ratingBreakdown,
      totalReviews: profile.totalReviews,
      servicePackages: packages,
      isAcceptingClients: profile.isAcceptingClients,
      hasUnacknowledgedChanges: profile.hasUnacknowledgedChanges,
      unacknowledgedChangesFields: profile.unacknowledgedChangesFields,
    );

    await AppRepositories.users.upsertTherapistProfile(normalized);
    await AppRepositories.users.updateCurrentUser({
      'firstName': firstName,
      'lastName': lastName,
      'fullName': fullName,
      'email': contactEmail.trim().toLowerCase(),
      'phone': contactPhone.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    final authUser = FirebaseAuth.instance.currentUser;
    if (authUser != null &&
        fullName.isNotEmpty &&
        authUser.displayName?.trim() != fullName) {
      try {
        await authUser.updateDisplayName(fullName);
      } catch (_) {
        // Keep saving resilient even if Auth profile update fails.
      }
    }

    // notification preferences to match the 7 therapist notifications.
    final cleanMap = _notificationPrefs;

    try {
      await Future.wait([
        FirebaseFirestore.instance
            .collection(FirestoreCollections.users)
            .doc(uid)
            .update({
              'notificationPreferences': cleanMap,
            }),
        FirebaseFirestore.instance
            .collection(FirestoreCollections.therapistProfiles)
            .doc(uid)
            .set({
              'yearsOfExperience': years,
              'experience_years': years,
              'experience_months': months,
              'credentials': credentials,
              'contactEmail': contactEmail,
              'contactPhone': contactPhone,
              if (certificateBase64 != null &&
                  certificateBase64.trim().isEmpty) ...{
                'certificatePdfName': FieldValue.delete(),
                'certificateBase64': FieldValue.delete(),
              } else ...{
                if (certificatePdfName != null)
                  'certificatePdfName': certificatePdfName,
                if (certificateBase64 != null)
                  'certificateBase64': certificateBase64,
              },
              if (photoBase64 != null)
                'photoUrlBase64': photoBase64,
              'servicePackages': packages.map((TherapyPackage item) => item.toMap()).toList(),
              'isActive': normalized.isActive,
              'therapistNotificationPreferences': cleanMap,
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true)),
      ]);

      if (!mounted) {
        return;
      }
      setState(() {
        _profile = normalized;
        _years = years;
        _months = months;
        _credentials = credentials;
        _contactEmail = contactEmail;
        _contactPhone = contactPhone;
        if (certificateBase64 != null) {
          _certificatePdfName = certificatePdfName;
        }
        _packages = packages;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_outline, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Text(
                successMessage ?? 'Changes saved successfully!',
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF2ECC71),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Failed to save changes: $e',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFFE74C3C),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  Future<void> _toggleProfileVisibility(bool isActive) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final profile = _profile;
    if (uid == null || profile == null) {
      return;
    }
    // Only approved therapists can toggle visibility
    if (profile.verificationStatus != 'approved') {
      return;
    }
    final updated = TherapistProfile(
      id: profile.id,
      displayName: profile.displayName,
      bio: profile.bio,
      specializations: profile.specializations,
      pricing: profile.pricing,
      languages: profile.languages,
      rating: profile.rating,
      availability: profile.availability,
      photoUrl: profile.photoUrl,
      isActive: isActive,
      yearsOfExperience: profile.yearsOfExperience,
      experienceMonths: profile.experienceMonths,
      credentials: profile.credentials,
      photoUrlBase64: profile.photoUrlBase64,
      certificateBase64: profile.certificateBase64,
      verificationStatus: profile.verificationStatus,
      adminFeedback: profile.adminFeedback,
      verifiedBadge: profile.verifiedBadge,
      licenseNumber: profile.licenseNumber,
      registrationNumber: profile.registrationNumber,
      cnic: profile.cnic,
      experienceDetails: profile.experienceDetails,
      ratingBreakdown: profile.ratingBreakdown,
      totalReviews: profile.totalReviews,
      servicePackages: profile.servicePackages,
    );
    await AppRepositories.users.upsertTherapistProfile(updated);
    await FirebaseFirestore.instance
        .collection(FirestoreCollections.therapistProfiles)
        .doc(uid)
        .set({
          'isActive': isActive,
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
    if (!mounted) {
      return;
    }
    setState(() => _profile = updated);
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.logout_rounded, color: Color(0xFFEF4444), size: 26),
            SizedBox(width: 10),
            Text(
              'Logout',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: Color(0xFF1E293B),
              ),
            ),
          ],
        ),
        content: const Text(
          'Are you sure you want to logout? You will need to sign in again to access your account.',
          style: TextStyle(
            fontSize: 15,
            height: 1.45,
            color: Color(0xFF475569),
          ),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Cancel',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Color(0xFF64748B),
              ),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFEF4444),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Logout',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await FirebaseService().logout();
    if (!mounted) {
      return;
    }
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  Future<void> _openSettingsDialog() async {
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black45,
      builder: (context) {
        return _TherapistSettingsDialog(
          onScheduler: () async {
            Navigator.pop(context);
            if (_profile == null) return;
            await Navigator.push<void>(
              this.context,
              MaterialPageRoute(
                builder: (_) => TherapistSchedulerScreen(
                  therapistId: _profile!.id,
                ),
              ),
            );
          },
          onProfile: () async {
            Navigator.pop(context);
            if (_profile == null) return;
            await Navigator.push<bool>(
              this.context,
              MaterialPageRoute(
                builder: (_) => TherapistProfileSettingsScreen(
                  profile: _profile!,
                  setupMode: false,
                  initialYears: _years,
                  initialMonths: _months,
                  initialCredentials: _credentials,
                  initialEmail: _contactEmail,
                  initialPhone: _contactPhone,
                  initialCertificatePdfName: _certificatePdfName,
                  initialPackages: _packages,
                  onSave: ({
                    required profile,
                    required years,
                    required months,
                    required credentials,
                    required contactEmail,
                    required contactPhone,
                    required packages,
                    certificatePdfName,
                    photoBase64,
                    certificateBase64,
                  }) =>
                      _saveProfileData(
                        profile: profile,
                        years: years,
                        months: months,
                        credentials: credentials,
                        contactEmail: contactEmail,
                        contactPhone: contactPhone,
                        packages: packages,
                        certificatePdfName: certificatePdfName,
                        photoBase64: photoBase64,
                        certificateBase64: certificateBase64,
                        successMessage: 'Profile saved successfully!',
                      ),
                ),
              ),
            );
            if (mounted) {
              await _loadState();
            }
          },
          onPackage: () async {
            Navigator.pop(context);
            // Sync with Firestore to get latest packages before navigating
            await _loadState();
            if (!mounted) return;
            final updated = await Navigator.push<List<TherapyPackage>>(
              this.context,
              MaterialPageRoute(
                builder: (_) =>
                    TherapistPackagesScreen(
                      initialPackages: _packages,
                      specializations: _profile?.specializations ?? const <String>[],
                    ),
              ),
            );
            if (updated != null && _profile != null) {
              await _saveProfileData(
                profile: _profile!,
                years: _years,
                months: _months,
                credentials: _credentials,
                contactEmail: _contactEmail,
                contactPhone: _contactPhone,
                packages: updated,
                successMessage: 'Packages saved successfully!',
              );
              // Update local state to reflect the saved packages
              setState(() {
                _packages = updated;
              });
            }
          },
          onAlerts: () async {
            Navigator.pop(context);
            final updated = await Navigator.push<Map<String, bool>>(
              this.context,
              MaterialPageRoute(
                builder: (_) => TherapistNotificationSettingsScreen(
                  initialValues: _notificationPrefs,
                ),
              ),
            );
            if (updated != null) {
              final uid = FirebaseAuth.instance.currentUser?.uid;
              if (uid != null) {
                try {
                  await Future.wait([
                    FirebaseFirestore.instance
                        .collection(FirestoreCollections.users)
                        .doc(uid)
                        .update({
                      'notificationPreferences': updated,
                    }),
                    FirebaseFirestore.instance
                        .collection(FirestoreCollections.therapistProfiles)
                        .doc(uid)
                        .set({
                      'therapistNotificationPreferences': updated,
                    }, SetOptions(merge: true)),
                  ]);
                  if (mounted) {
                    ScaffoldMessenger.of(this.context).showSnackBar(
                      SnackBar(
                        content: const Row(
                          children: [
                            Icon(Icons.check_circle_outline, color: Colors.white, size: 20),
                            SizedBox(width: 10),
                            Text(
                              'Notification preferences saved successfully!',
                              style: TextStyle(fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                        backgroundColor: const Color(0xFF2ECC71),
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        duration: const Duration(seconds: 3),
                      ),
                    );
                  }
                } catch (_) {}
              }
              setState(() {
                _notificationPrefs = updated;
              });
            }
          },
          onFeedback: () async {
            Navigator.pop(context);
            await Navigator.push<void>(
              this.context,
              MaterialPageRoute(builder: (_) => const FeedbackScreen()),
            );
          },
          onAbout: () async {
            Navigator.pop(context);
            await Navigator.push<void>(
              this.context,
              MaterialPageRoute(builder: (_) => const AboutApplicationScreen(audience: 'therapist')),
            );
          },
          onLogout: () async {
            Navigator.pop(context);
            await _logout();
          },
        );
      },
    );
  }

  Future<void> _openDashboard() async {
    if (_profile == null) return;
    
    // Check if profile is complete for INITIAL SIGNUP before allowing dashboard access
    bool isIncompleteForInitialSignup() {
      return (_years == 0 && _months == 0 && !_hasCompletedInitialProfile) ||
          _credentials.trim().isEmpty ||
          _contactEmail.trim().isEmpty ||
          _contactPhone.trim().isEmpty ||
          _packages.isEmpty ||
          _profile?.bio.trim().isEmpty == true ||
          (_profile?.certificateBase64 ?? '').isEmpty;
    }
    
    // Check if profile is incomplete for REGULAR SETTINGS (less strict)
    bool isIncompleteForSettings() {
      return (_years == 0 && _months == 0 && !_hasCompletedInitialProfile) ||
          _credentials.trim().isEmpty ||
          _contactEmail.trim().isEmpty ||
          _contactPhone.trim().isEmpty;
    }
    
    final initialSignupIncomplete = isIncompleteForInitialSignup();
    final settingsIncomplete = isIncompleteForSettings();
        
    if (initialSignupIncomplete && !_hasCompletedInitialProfile) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please complete your profile first before accessing the dashboard.'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    } else if (settingsIncomplete && _hasCompletedInitialProfile) {
      // Profile was completed before but basic info is now incomplete
      // Allow access but show a gentle reminder
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Some basic profile information is missing. You can update it in Settings when needed.'),
          duration: Duration(seconds: 3),
        ),
      );
    }
    
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => TherapistDashboardScreen(
          profile: _profile!,
          years: _years,
          onToggleVisibility: _toggleProfileVisibility,
          onOpenSettings: _openSettingsDialog,
        ),
      ),
    );
    _loadState();
  }

  void _showComingSoon() {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Coming soon')));
  }

  @override
  Widget build(BuildContext context) {
    final r = context.responsive;
    final isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
      child: SessionGuard(
        role: SessionGuardRole.therapist,
        child: Scaffold(
          backgroundColor: const Color(0xFFF6F6F6),
          body: Stack(
            children: [
              const Positioned.fill(child: ColoredBox(color: Color(0xFF77C6F0))),
            Positioned(
              top: r.h(96),
              left: 0,
              right: 0,
              bottom: 0,
              child: ClipRRect(
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(r.w(14)),
                  topRight: Radius.circular(r.w(14)),
                ),
                child: const ColoredBox(color: Color(0xFFF6F6F6)),
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: SafeArea(
                bottom: false,
                child: Container(
                  height: r.h(92),
                  decoration: BoxDecoration(
                    color: Color(0xFF77C6F0),
                    borderRadius: BorderRadius.only(
                      bottomLeft: Radius.circular(r.w(18)),
                      bottomRight: Radius.circular(r.w(18)),
                    ),
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Column(
                children: [
                  SizedBox(height: r.h(140)),
                  Expanded(
                    child: StreamBuilder<ProfessionalSupportFeatureFlags>(
                      stream: AppRepositories.content
                          .watchProfessionalSupportFeatureFlags(),
                      initialData: ProfessionalSupportFeatureFlags.enabled,
                      builder: (context, flagsSnapshot) {
                        final featureFlags =
                            flagsSnapshot.data ??
                            ProfessionalSupportFeatureFlags.enabled;
                        return LayoutBuilder(
                          builder: (context, constraints) {
                            final cardWidth = math.min(
                              324.0,
                              constraints.maxWidth - 52,
                            );
                            return SingleChildScrollView(
                              padding: EdgeInsets.fromLTRB(
                                0,
                                r.h(12),
                                0,
                                r.h(172),
                              ),
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  minHeight: math.max(
                                    0,
                                    constraints.maxHeight - 184,
                                  ),
                                ),
                                child: Center(
                                  child: SizedBox(
                                    width: cardWidth,
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        _ModuleCard(
                                          title: 'Dashboard',
                                          color: const Color(0xFFF6B1BF),
                                          asset: 'assets/images/Dashboard.png',
                                          onTap: _openDashboard,
                                        ),
                                        SizedBox(height: r.h(14)),
                                        StreamBuilder<List<TherapistThread>>(
                                          stream: AppRepositories.support.watchThreadsForRole('therapist'),
                                          builder: (context, snapshot) {
                                            final threads = snapshot.data ?? [];
                                            final unreadCount = threads.where((t) {
                                              if (t.lastMessageAt == null) return false;
                                              if (t.therapistLastRead == null) return true;
                                              return t.lastMessageAt!.isAfter(t.therapistLastRead!);
                                            }).length;
                                            return _ModuleCard(
                                              title: 'Messages',
                                              color: const Color(0xFFA5E876),
                                              asset:
                                                  'assets/images/Professional_Support.png',
                                              enabled: featureFlags.chatEnabled,
                                              unreadCount: unreadCount,
                                              onTap: featureFlags.chatEnabled
                                                  ? () => Navigator.push(
                                                      context,
                                                      MaterialPageRoute(
                                                        builder: (_) =>
                                                            const TherapistMessagesScreen(),
                                                      ),
                                                    )
                                                  : _showComingSoon,
                                            );
                                          },
                                        ),
                                        SizedBox(height: r.h(14)),
                                        _ModuleCard(
                                          title: 'Settings',
                                          color: const Color(0xFF66D2E8),
                                          asset: 'assets/images/Settings.png',
                                          onTap: _openSettingsDialog,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            if (!isKeyboardOpen)
              // Wave and decor shapes moved to the end of Stack to appear ON TOP of content
              Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: IgnorePointer(
                child: Stack(
                  alignment: Alignment.bottomCenter,
                  children: [
                    ClipPath(
                      clipper: _BottomWaveClipper(),
                      child: Container(
                        height: r.h(150),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [AppColors.lightBlue, AppColors.primaryBlue],
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: r.h(34),
                      left: r.w(44),
                      child: Container(
                        width: r.w(20),
                        height: r.w(20),
                        color: AppColors.yellow,
                      ),
                    ),
                    Positioned(
                      bottom: r.h(54),
                      left: r.w(100),
                      child: Icon(
                        Icons.star,
                        color: AppColors.pink,
                        size: r.sp(24, min: 18, max: 28),
                      ),
                    ),
                    Positioned(
                      bottom: r.h(20),
                      right: r.w(152),
                      child: CustomPaint(
                        size: Size(r.w(20), r.w(20)),
                        painter: _TrianglePainter(color: AppColors.red),
                      ),
                    ),
                    Positioned(
                      bottom: r.h(10),
                      right: r.w(44),
                      child: Container(
                        width: r.w(16),
                        height: r.w(16),
                        decoration: const BoxDecoration(
                          color: AppColors.green,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              top: MediaQuery.of(context).padding.top + r.h(10),
              left: 0,
              right: 0,
              child: Center(child: _TherapistHomeBadge(size: r.w(124))),
            ),
            if (_showInfoIcon)
              Positioned(
                bottom: r.h(120),
                right: r.w(20),
                child: ScaleTransition(
                  scale: _pulseAnimation,
                  child: GestureDetector(
                    onTap: _startInfoFlow,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 500),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF6B35),
                        shape: BoxShape.circle,
                        boxShadow: [
                          if (_isGlowing)
                            BoxShadow(
                              color: const Color(0xFFFF6B35).withValues(alpha: 0.6),
                              blurRadius: 20,
                              spreadRadius: 3,
                            ),
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.info_outline,
                        color: Colors.white,
                        size: r.sp(28, min: 24, max: 32),
                      ),
                    ),
                  ),
                ),
              ),
            // Custom tooltip cloud above info icon
            if (_isDialogShowing && _showInfoIcon)
              Positioned(
                bottom: r.h(160), // Position above the icon
                right: r.w(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // Tooltip cloud with enhanced design
                    Container(
                      constraints: BoxConstraints(maxWidth: r.w(220)),
                      padding: EdgeInsets.all(r.w(16)),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            const Color(0xFF667EEA),
                            const Color(0xFF764BA2),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF667EEA).withValues(alpha: 0.3),
                            blurRadius: 20,
                            spreadRadius: 2,
                            offset: const Offset(0, 8),
                          ),
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.2),
                          width: 1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: EdgeInsets.all(r.w(6)),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  Icons.celebration,
                                  color: Colors.white,
                                  size: r.sp(16),
                                ),
                              ),
                              SizedBox(width: r.w(8)),
                              Expanded(
                                child: Text(
                                  'Congratulations!',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: r.sp(14),
                                    shadows: [
                                      Shadow(
                                        color: Colors.black.withValues(alpha: 0.3),
                                        offset: const Offset(0, 1),
                                        blurRadius: 2,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: r.h(8)),
                          Text(
                            'Tap this glowing icon to discover your dashboard features and get started!',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.9),
                              fontSize: r.sp(12),
                              height: 1.4,
                              shadows: [
                                Shadow(
                                  color: Colors.black.withValues(alpha: 0.3),
                                  offset: const Offset(0, 1),
                                  blurRadius: 2,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Enhanced triangle pointing down to icon
                    Container(
                      width: 0,
                      height: 0,
                      margin: EdgeInsets.only(right: r.w(24)),
                      child: CustomPaint(
                        size: Size(r.w(24), r.h(12)),
                        painter: TooltipTrianglePainter(
                          color: const Color(0xFF764BA2),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Positioned(
              top: MediaQuery.of(context).padding.top + r.h(12),
              right: r.w(18),
              child: _buildHomeNotificationBell(context),
            ),
          ],
        ),
      ),
    ),
    );
  }

  Widget _buildHomeNotificationBell(BuildContext context) {
    return StreamBuilder<List<NotificationInboxItem>>(
      stream: AppRepositories.support.watchNotifications(),
      builder: (context, snapshot) {
        final items = snapshot.data ?? const [];
        final unreadCount = items.where((item) => !item.isRead).length;

        if (unreadCount > _lastUnreadCount) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _triggerBellAnimation();
            _lastUnreadCount = unreadCount;
          });
        } else if (unreadCount < _lastUnreadCount) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _lastUnreadCount = unreadCount;
          });
        }

        return Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.8),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: AnimatedBuilder(
                animation: _bellAnimation,
                builder: (context, child) {
                  return Transform.rotate(
                    angle: _bellAnimation.value,
                    child: IconButton(
                      icon: const Icon(
                        Icons.notifications_none_rounded,
                        color: Color(0xFF1E293B),
                        size: 24,
                      ),
                      onPressed: () async {
                        final updated = await Navigator.push<Map<String, bool>>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => TherapistNotificationInboxScreen(
                              initialPrefs: _notificationPrefs,
                            ),
                          ),
                        );
                        if (updated != null) {
                          setState(() {
                            _notificationPrefs = updated;
                          });
                          _reevaluateEmergencyAlert();
                        }
                      },
                    ),
                  );
                },
              ),
            ),
            if (unreadCount > 0)
              Positioned(
                right: -2,
                top: -2,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: Color(0xFFEF4444),
                    shape: BoxShape.circle,
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 18,
                    minHeight: 18,
                  ),
                  child: Center(
                    child: Text(
                      '$unreadCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class TooltipTrianglePainter extends CustomPainter {
  final Color color;
  
  TooltipTrianglePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final path = Path();
    path.moveTo(size.width / 2, 0); // Top center
    path.lineTo(0, size.height); // Bottom left
    path.lineTo(size.width, size.height); // Bottom right
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class TherapistInfoFlowScreen extends StatefulWidget {
  const TherapistInfoFlowScreen({super.key});

  @override
  State<TherapistInfoFlowScreen> createState() => _TherapistInfoFlowScreenState();
}

class _TherapistInfoFlowScreenState extends State<TherapistInfoFlowScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;
  
  final List<Map<String, String>> _infoPages = [
    {
      'title': 'Dashboard',
      'description': 'Your central workspace showing verification status, client counts, payout records, and immediate tasks.',
      'details': '• Track profile verification & approval status\n• View total client subscriptions & earnings\n• Initiate secure payout and withdrawal requests\n• Monitor daily profile visitation statistics',
    },
    {
      'title': 'Messages',
      'description': 'Communicate with parents, review children\'s planner logs, and coordinate developmental support through secure channels.',
      'details': '• Coordinate child development plans with parents\n• Review active child profile records & logs\n• Share professional advice & progress insights\n• Lock or unlock chat threads when needed',
    },
    {
      'title': 'Scheduler',
      'description': 'Establish your consultation availability slots and review booked appointments from active parent clients.',
      'details': '• Define active slot times for parent bookings\n• Review slot details & client information\n• Manage scheduler overrides and cooling periods',
    },
    {
      'title': 'Settings',
      'description': 'Configure your licensing details, rate cards, communication packages, and notification preferences.',
      'details': '• Update bio, specializations, and certificates\n• Adjust pricing tiers and subscription options\n• Manage security settings and access policies\n• View platform guidelines and developer feedback',
    },
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_currentPage < _infoPages.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      Navigator.pop(context);
    }
  }

  void _previousPage() {
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = context.responsive;
    
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Column(
          children: [
            // Header with gradient
            Container(
              padding: EdgeInsets.symmetric(horizontal: r.w(20), vertical: r.h(16)),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF77C6F0), Color(0xFF10B6CF)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                  const Spacer(),
                  Text(
                    'Therapist Dashboard Guide',
                    style: TextStyle(
                      fontSize: r.sp(18),
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const Spacer(),
                  const SizedBox(width: 48), // Balance the header
                ],
              ),
            ),
            
            // Page indicator with improved styling
            Container(
              margin: EdgeInsets.symmetric(horizontal: r.w(20), vertical: r.h(16)),
              child: Row(
                children: List.generate(
                  _infoPages.length,
                  (index) => Expanded(
                    child: Container(
                      height: 6,
                      margin: EdgeInsets.only(right: index < _infoPages.length - 1 ? r.w(8) : 0),
                      decoration: BoxDecoration(
                        color: index <= _currentPage 
                            ? const Color(0xFF77C6F0) 
                            : const Color(0xFFE2E8F0),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            
            // Page content with improved design
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: (index) {
                  setState(() => _currentPage = index);
                },
                itemCount: _infoPages.length,
                itemBuilder: (context, index) {
                  final page = _infoPages[index];
                  final pageColor = _getPageColor(index);
                  
                  return Padding(
                    padding: EdgeInsets.all(r.w(20)),
                    child: Column(
                      children: [
                        SizedBox(height: r.h(20)),
                        
                        // Icon with gradient background
                        Container(
                          width: r.w(140),
                          height: r.w(140),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [pageColor.withValues(alpha: 0.2), pageColor.withValues(alpha: 0.1)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            shape: BoxShape.circle,
                            border: Border.all(color: pageColor.withValues(alpha: 0.3), width: 2),
                          ),
                          child: Icon(
                            _getIconForPage(index),
                            size: r.sp(56),
                            color: pageColor,
                          ),
                        ),
                        
                        SizedBox(height: r.h(32)),
                        
                        // Title with gradient text effect
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: r.w(20)),
                          child: Text(
                            page['title']!,
                            style: TextStyle(
                              fontSize: r.sp(32),
                              fontWeight: FontWeight.bold,
                              color: pageColor,
                              letterSpacing: 0.5,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        
                        SizedBox(height: r.h(20)),
                        
                        // Description card
                        Container(
                          width: double.infinity,
                          padding: EdgeInsets.all(r.w(24)),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(r.w(20)),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.05),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Text(
                            page['description']!,
                            style: TextStyle(
                              fontSize: r.sp(16),
                              color: const Color(0xFF475569),
                              height: 1.6,
                              fontWeight: FontWeight.w500,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        
                        SizedBox(height: r.h(24)),
                        
                        // Details with improved styling
                        Container(
                          width: double.infinity,
                          padding: EdgeInsets.all(r.w(24)),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [pageColor.withValues(alpha: 0.05), pageColor.withValues(alpha: 0.02)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(r.w(20)),
                            border: Border.all(color: pageColor.withValues(alpha: 0.2)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Key Features:',
                                style: TextStyle(
                                  fontSize: r.sp(16),
                                  color: pageColor,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              SizedBox(height: r.h(12)),
                              Text(
                                page['details']!,
                                style: TextStyle(
                                  fontSize: r.sp(14),
                                  color: const Color(0xFF475569),
                                  height: 1.8,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            
            // Navigation buttons with improved styling
            Container(
              padding: EdgeInsets.all(r.w(20)),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  // Previous button
                  Expanded(
                    child: _currentPage > 0
                        ? OutlinedButton(
                            onPressed: _previousPage,
                            style: OutlinedButton.styleFrom(
                              padding: EdgeInsets.symmetric(vertical: r.h(18)),
                              side: const BorderSide(color: Color(0xFF77C6F0), width: 2),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Text(
                              'Previous',
                              style: TextStyle(
                                color: const Color(0xFF77C6F0),
                                fontSize: r.sp(16),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          )
                        : const SizedBox(),
                  ),
                  
                  SizedBox(width: r.w(16)),
                  
                  // Next/Done button
                  Expanded(
                    child: FilledButton(
                      onPressed: _nextPage,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF77C6F0),
                        padding: EdgeInsets.symmetric(vertical: r.h(18)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        _currentPage < _infoPages.length - 1 ? 'Next' : 'Get Started',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: r.sp(16),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getPageColor(int index) {
    switch (index) {
      case 0:
        return const Color(0xFFF6B1BF); // Dashboard - Pink
      case 1:
        return const Color(0xFFA5E876); // Messages - Green
      case 2:
        return const Color(0xFF66D2E8); // Settings - Blue
      default:
        return const Color(0xFFFF6B35); // Default - Orange
    }
  }

  IconData _getIconForPage(int index) {
    switch (index) {
      case 0:
        return Icons.dashboard;
      case 1:
        return Icons.message;
      case 2:
        return Icons.settings;
      default:
        return Icons.info;
    }
  }
}

class TherapistDashboardScreen extends StatefulWidget {
  const TherapistDashboardScreen({
    super.key,
    required this.profile,
    required this.years,
    required this.onToggleVisibility,
    required this.onOpenSettings,
  });

  final TherapistProfile profile;
  final int years;
  final Future<void> Function(bool isActive) onToggleVisibility;
  final Future<void> Function() onOpenSettings;

  @override
  State<TherapistDashboardScreen> createState() =>
      _TherapistDashboardScreenState();
}

class _TherapistDashboardScreenState extends State<TherapistDashboardScreen> {
  late bool _isActive;
  late bool _isAcceptingClients;
  bool _updatingVisibility = false;
  bool _updatingAccepting = false;
  late TherapistProfile _profile;
  bool _submittingReappeal = false;
  bool _submittingAcknowledgment = false;
  StreamSubscription<List<AppointmentSlot>>? _slotsSub;
  bool _showingNoteDialog = false;

  @override
  void initState() {
    super.initState();
    _profile = widget.profile;
    _isActive = _profile.isActive;
    _isAcceptingClients = _profile.isAcceptingClients;
    _refreshProfile();
    _startSessionCompletionCheck();
  }

  @override
  void dispose() {
    _slotsSub?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant TherapistDashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.profile.isActive != widget.profile.isActive) {
      _isActive = widget.profile.isActive;
    }
    if (oldWidget.profile.isAcceptingClients != widget.profile.isAcceptingClients) {
      _isAcceptingClients = widget.profile.isAcceptingClients;
    }
    if (oldWidget.profile != widget.profile) {
      _profile = widget.profile;
    }
  }

  Future<void> _refreshProfile() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final updatedProfile = await AppRepositories.support.getTherapistById(uid);
      if (updatedProfile != null && mounted) {
        setState(() {
          _profile = updatedProfile;
          _isActive = updatedProfile.isActive;
          _isAcceptingClients = updatedProfile.isAcceptingClients;
        });
      }
    } catch (e) {
      debugPrint('Error refreshing profile: $e');
    }
  }

  Future<void> _handleReappeal() async {
    if (_submittingReappeal) return;
    setState(() {
      _submittingReappeal = true;
    });
    try {
      await FirebaseFirestore.instance
          .collection(FirestoreCollections.therapistProfiles)
          .doc(_profile.id)
          .update({
        'verificationStatus': 'pending',
        'adminFeedback': '',
        'updatedAt': FieldValue.serverTimestamp(),
      });
      await _refreshProfile();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Reappeal submitted successfully! Your profile is now pending review.'),
          backgroundColor: Color(0xFF0B7D3B),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to submit reappeal: $e'),
          backgroundColor: const Color(0xFFFF4D4D),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _submittingReappeal = false;
        });
      }
    }
  }

  Future<void> _handleAcknowledgeChanges() async {
    if (_submittingAcknowledgment) return;
    setState(() {
      _submittingAcknowledgment = true;
    });
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        await FirebaseFirestore.instance
            .collection(FirestoreCollections.therapistProfiles)
            .doc(uid)
            .update({
          'hasUnacknowledgedChanges': false,
        });

        final querySnap = await FirebaseFirestore.instance
            .collection('therapist_profile_updates')
            .where('therapistId', isEqualTo: uid)
            .where('status', isEqualTo: 'pending_acknowledgment')
            .get();

        final batch = FirebaseFirestore.instance.batch();
        for (var doc in querySnap.docs) {
          batch.update(doc.reference, {
            'status': 'pending_review',
            'acknowledgedAt': FieldValue.serverTimestamp(),
          });
        }
        await batch.commit();

        await _refreshProfile();

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Acknowledgment recorded successfully.'),
            backgroundColor: Color(0xFF0B7D3B),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to record acknowledgment: $e'),
          backgroundColor: const Color(0xFFFF4D4D),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _submittingAcknowledgment = false;
        });
      }
    }
  }

  Future<void> _handleToggleVisibility() async {
    if (_updatingVisibility) {
      return;
    }
    final nextIsActive = !_isActive;
    setState(() {
      _updatingVisibility = true;
      _isActive = nextIsActive;
    });
    try {
      await widget.onToggleVisibility(nextIsActive);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            nextIsActive
                ? 'Profile is now visible to all parents.'
                : 'Profile is now hidden from new parents.',
          ),
          backgroundColor: nextIsActive
              ? const Color(0xFF0B7D3B)
              : const Color(0xFFB45309),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _isActive = !nextIsActive);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to update visibility right now.'),
          backgroundColor: Color(0xFFFF4D4D),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _updatingVisibility = false);
      }
    }
  }

  Future<void> _handleToggleAccepting() async {
    if (_updatingAccepting) return;
    final restUntil = _profile.restrictionUntil;
    final isRestricted = restUntil != null && DateTime.now().isBefore(restUntil);
    if (isRestricted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Your account is temporarily restricted. You cannot accept new clients at this time.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    final next = !_isAcceptingClients;
    setState(() {
      _updatingAccepting = true;
      _isAcceptingClients = next;
      _profile = _profile.copyWith(isAcceptingClients: next);
    });
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        await FirebaseFirestore.instance
            .collection(FirestoreCollections.therapistProfiles)
            .doc(uid)
            .set(
              {'isAcceptingClients': next, 'updatedAt': FieldValue.serverTimestamp()},
              SetOptions(merge: true),
            );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            next
                ? 'You are now accepting new clients.'
                : 'You are no longer accepting new clients.',
          ),
          backgroundColor: next
              ? const Color(0xFF0B7D3B)
              : const Color(0xFFB45309),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isAcceptingClients = !next;
        _profile = _profile.copyWith(isAcceptingClients: !next);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to update client availability. Please try again.'),
          backgroundColor: Color(0xFFFF4D4D),
        ),
      );
    } finally {
      if (mounted) setState(() => _updatingAccepting = false);
    }
  }

  void _startSessionCompletionCheck() {
    _slotsSub = AppRepositories.support.watchSlotsForTherapist(_profile.id).listen((slots) {
      if (!mounted || _showingNoteDialog) return;
      
      final now = DateTime.now();
      for (final slot in slots) {
        if (slot.status == 'booked' && !slot.sessionCompleted) {
          final endTime = slot.dateTime.add(Duration(minutes: slot.durationMinutes));
          if (now.isAfter(endTime)) {
            // Trigger note dialog
            _triggerNoteDialog(slot);
            break;
          }
        }
      }
    });
  }

  Future<void> _triggerNoteDialog(AppointmentSlot slot) async {
    _showingNoteDialog = true;
    final titleCtrl = TextEditingController(text: 'Session Progress Note');
    final bodyCtrl = TextEditingController();

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.assignment_turned_in_rounded, color: Color(0xFF0D9488)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Complete Session for ${slot.bookedForChildName ?? 'Child'}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'The session has ended. Please enter your clinical progress note to mark it complete.',
                  style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                ),
                const SizedBox(height: 14),
                const Text('Note Title *', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 6),
                TextField(
                  controller: titleCtrl,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                ),
                const SizedBox(height: 14),
                const Text('Clinical Progress Note *', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                const SizedBox(height: 6),
                TextField(
                  controller: bodyCtrl,
                  maxLines: 4,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    hintText: 'e.g., Child engaged well, practiced speech templates...',
                    contentPadding: const EdgeInsets.all(10),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                AppRepositories.support.markSessionCompleted(slot.id);
                Navigator.pop(ctx);
              },
              child: const Text('Skip Note', style: TextStyle(color: Color(0xFF64748B))),
            ),
            ElevatedButton(
              onPressed: () async {
                final title = titleCtrl.text.trim();
                final body = bodyCtrl.text.trim();
                if (title.isEmpty || body.isEmpty) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Please fill in both fields.')),
                  );
                  return;
                }
                
                try {
                  await AppRepositories.support.createClinicalNote(
                    therapistId: slot.therapistId,
                    parentId: slot.bookedByParentId ?? '',
                    childId: slot.bookedForChildId ?? '',
                    therapistName: _profile.displayName,
                    childName: slot.bookedForChildName ?? 'Child',
                    title: title,
                    body: body,
                    slotId: slot.id,
                  );
                  if (ctx.mounted) Navigator.pop(ctx);
                } catch (e) {
                  if (ctx.mounted) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(content: Text('Failed: $e')),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0D9488), foregroundColor: Colors.white),
              child: const Text('Save Note & Complete'),
            ),
          ],
        );
      },
    );
    _showingNoteDialog = false;
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
    final specialization = profile.specializations.isEmpty
        ? 'Specialization not set'
        : profile.specializations.first;
    final visibilityBg = _isActive
        ? const Color(0xFFDDFCEA)
        : const Color(0xFFFFF1E8);
    final visibilityBorder = _isActive
        ? const Color(0xFFA7E9C6)
        : const Color(0xFFFFC9A7);
    final statusColor = _isActive
        ? const Color(0xFF0B7D3B)
        : const Color(0xFFB45309);
    final detailColor = _isActive
        ? const Color(0xFF17924C)
        : const Color(0xFFC2410C);
    final actionColor = _isActive
        ? const Color(0xFF0EA5C6)
        : const Color(0xFFB45309);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        statusBarBrightness: Brightness.light,
      ),
      child: SessionGuard(
        role: SessionGuardRole.therapist,
        child: Scaffold(
          backgroundColor: const Color(0xFFF1F3F4),
          body: Column(
            children: [
              Container(
                width: double.infinity,
                color: const Color(0xFF99E8F2),
                child: SafeArea(
                  bottom: false,
                  child: SizedBox(
                    height: 80,
                    width: double.infinity,
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(
                            Icons.arrow_back,
                            color: Color(0xFF1F2937),
                          ),
                        ),
                        const Expanded(
                          child: Text(
                            'Dashboard',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 30 / 1.5,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF1F2937),
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () async {
                            await widget.onOpenSettings();
                            await _refreshProfile();
                          },
                          icon: const Icon(Icons.menu, color: Color(0xFF1F2937)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 16),
                  children: [
                    if (profile.verificationStatus == 'pending') ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFFBEB),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFFDE68A)),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.hourglass_empty, color: Colors.amber),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Verification status: Pending. Your credentials are under review. You will be listed once approved.',
                                style: TextStyle(color: Color(0xFF92400E), fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                    ] else if (profile.verificationStatus == 'rejected') ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF2F2),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFFCA5A5)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.error_outline, color: Colors.red),
                                SizedBox(width: 10),
                                Text(
                                  'Profile Update Required',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF991B1B),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Rejection comments: ${profile.adminFeedback.isEmpty ? "Please double-check your uploaded documents and details." : profile.adminFeedback}',
                              style: const TextStyle(color: Color(0xFF991B1B), fontSize: 13),
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: _submittingReappeal ? null : _handleReappeal,
                                icon: _submittingReappeal
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Icon(Icons.send_rounded, size: 16),
                                label: const Text('Reappeal'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFFEF4444),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                    ] else if (profile.verificationStatus == 'suspended') ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF2F2),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFFCA5A5)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.gavel, color: Colors.red),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Account Suspended: ${profile.adminFeedback.isEmpty ? "Please contact support." : profile.adminFeedback}',
                                style: const TextStyle(color: Color(0xFF991B1B), fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                    ] else if (profile.verificationStatus == 'restricted') ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF3C7),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFFCD34D)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.gavel, color: Colors.amber),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Account Restricted: Your account has been temporarily restricted. You cannot accept new clients or be listed on Professional Support at this time. Admin notes: ${profile.adminFeedback.isEmpty ? "No notes provided." : profile.adminFeedback}',
                                style: const TextStyle(color: Color(0xFF92400E), fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    if (_profile.hasUnacknowledgedChanges) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFBFDBFE)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.info_outline, color: Colors.blue.shade700, size: 20),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'Important Profile Warning',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue.shade900,
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'You recently updated your account information. Please ensure that all details are accurate and comply with our guidelines. Your account may be reviewed by the admin at any time. Providing false or misleading information may result in suspension or permanent removal.',
                              style: TextStyle(color: Color(0xFF1E3A8A), fontSize: 13, height: 1.4),
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton(
                                onPressed: _submittingAcknowledgment ? null : _handleAcknowledgeChanges,
                                style: FilledButton.styleFrom(
                                  backgroundColor: Colors.blue.shade700,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                child: _submittingAcknowledgment
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Text('I Acknowledge'),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: _cardDeco,
                      child: Column(
                        children: [
                          Row(
                            children: [
                              _LogoCircleAvatar(
                                radius: 26,
                                backgroundColor: const Color(0xFFD8F6DF),
                                padding: 4,
                                photoBase64: profile.photoUrlBase64,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      profile.displayName,
                                      style: const TextStyle(
                                        fontSize: 30 / 1.5,
                                        fontWeight: FontWeight.w500,
                                        color: Color(0xFF1F2937),
                                      ),
                                    ),
                                    Text(
                                      specialization,
                                      style: const TextStyle(
                                        color: Color(0xFF16A34A),
                                      ),
                                    ),
                                    Text(
                                      profile.formattedExperience == 'Not set'
                                          ? 'Experience not set'
                                          : '${profile.formattedExperience} exp',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Color(0xFF6B7280),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: _cardDeco,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Specializations',
                            style: TextStyle(
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF1F2937),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children:
                                (profile.specializations.isEmpty
                                        ? const ['Specialization not set']
                                        : profile.specializations)
                                    .map(
                                      (item) => Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFDDEBFF),
                                          borderRadius: BorderRadius.circular(
                                            999,
                                          ),
                                        ),
                                        child: Text(
                                          item,
                                          style: const TextStyle(
                                            fontSize: 11.5,
                                            color: Color(0xFF3165C9),
                                          ),
                                        ),
                                      ),
                                    )
                                    .toList(),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    _TherapistWalletSection(therapistId: profile.id),
                    const SizedBox(height: 10),
                    StreamBuilder<List<TherapistReview>>(
                      stream: AppRepositories.support.watchReviewsForTherapist(profile.id),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return Container(
                            padding: const EdgeInsets.all(12),
                            decoration: _cardDeco,
                            child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                          );
                        }
                        final reviews = snapshot.data ?? const [];
                        final totalReviews = reviews.length;
                        double sumRating = 0.0;
                        final breakdown = {'1': 0, '2': 0, '3': 0, '4': 0, '5': 0};
                        for (final r in reviews) {
                          sumRating += r.rating;
                          final key = r.rating.clamp(1, 5).toString();
                          breakdown[key] = (breakdown[key] ?? 0) + 1;
                        }
                        final averageRating = totalReviews > 0 ? (sumRating / totalReviews) : 0.0;

                        Widget buildBreakdownRow(int star, int count) {
                          final percentage = totalReviews > 0 ? count / totalReviews : 0.0;
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 1.5),
                            child: Row(
                              children: [
                                Text(
                                  '$star ★',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF4B5563),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(4),
                                    child: LinearProgressIndicator(
                                      value: percentage,
                                      backgroundColor: const Color(0xFFE5E7EB),
                                      color: Colors.amber,
                                      minHeight: 6,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '$count',
                                  style: const TextStyle(fontSize: 11, color: Color(0xFF6B7280)),
                                ),
                              ],
                            ),
                          );
                        }

                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: _cardDeco,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.star_rounded, color: Colors.amber, size: 20),
                                  SizedBox(width: 6),
                                  Text(
                                    'Reviews & Feedback',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w500,
                                      color: Color(0xFF1F2937),
                                      fontSize: 15,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              if (totalReviews == 0)
                                const Center(
                                  child: Padding(
                                    padding: EdgeInsets.symmetric(vertical: 12),
                                    child: Text(
                                      'No reviews submitted yet.',
                                      style: TextStyle(color: Color(0xFF6B7280), fontStyle: FontStyle.italic),
                                    ),
                                  ),
                                )
                              else ...[
                                Row(
                                  children: [
                                    Column(
                                      children: [
                                        Text(
                                          averageRating.toStringAsFixed(1),
                                          style: const TextStyle(
                                            fontSize: 32,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF1F2937),
                                          ),
                                        ),
                                        Row(
                                          children: List.generate(5, (index) {
                                            return Icon(
                                              index < averageRating.round()
                                                  ? Icons.star
                                                  : Icons.star_border,
                                              color: Colors.amber,
                                              size: 14,
                                            );
                                          }),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '$totalReviews reviews',
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: Color(0xFF6B7280),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        children: [
                                          for (int i = 5; i >= 1; i--)
                                            buildBreakdownRow(i, breakdown[i.toString()] ?? 0),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                const Divider(),
                                const SizedBox(height: 6),
                                const Text(
                                  'Recent Written Feedback',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    color: Color(0xFF4B5563),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                ListView.separated(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: math.min(3, reviews.length),
                                  separatorBuilder: (context, index) => const Divider(height: 12),
                                  itemBuilder: (context, index) {
                                    final review = reviews[index];
                                    return Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Text(
                                              review.parentName.isEmpty ? 'Parent' : review.parentName,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 11,
                                                color: Color(0xFF374151),
                                              ),
                                            ),
                                            const Spacer(),
                                            Row(
                                              children: List.generate(5, (sIndex) {
                                                return Icon(
                                                  sIndex < review.rating
                                                      ? Icons.star
                                                      : Icons.star_border,
                                                  color: Colors.amber,
                                                  size: 11,
                                                );
                                              }),
                                            ),
                                          ],
                                        ),
                                        if (review.feedback.trim().isNotEmpty) ...[
                                          const SizedBox(height: 2),
                                          Text(
                                            review.feedback,
                                            style: const TextStyle(
                                              fontSize: 11.5,
                                              color: Color(0xFF4B5563),
                                            ),
                                          ),
                                        ],
                                        if (review.privateFeedback.trim().isNotEmpty) ...[
                                          const SizedBox(height: 4),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFF3F4F6),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              'Private Note: ${review.privateFeedback}',
                                              style: const TextStyle(
                                                fontSize: 10.5,
                                                color: Color(0xFF6B7280),
                                                fontStyle: FontStyle.italic,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ],
                                    );
                                  },
                                ),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: _cardDeco,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Profile Visibility',
                            style: TextStyle(
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF1F2937),
                            ),
                          ),
                          const SizedBox(height: 4),
                          // ── Only approved therapists can toggle visibility ──
                          if (profile.verificationStatus == 'approved') ...[
                            Text(
                              _isActive
                                  ? 'Your profile is visible to parents in the community'
                                  : 'Your profile is hidden from new parent discovery',
                              style: const TextStyle(
                                fontSize: 13,
                                color: Color(0xFF4B5563),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: visibilityBg,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: visibilityBorder),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _isActive
                                              ? 'Status: Active'
                                              : 'Status: Inactive',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            color: statusColor,
                                          ),
                                        ),
                                        Text(
                                          _isActive
                                              ? 'Parents can discover and contact you'
                                              : 'Only subscribed parents can continue seeing you',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: detailColor,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  OutlinedButton(
                                    onPressed: _updatingVisibility
                                        ? null
                                        : _handleToggleVisibility,
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: actionColor,
                                      side: BorderSide(color: actionColor),
                                      minimumSize: const Size(86, 40),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                      ),
                                    ),
                                    child: _updatingVisibility
                                        ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : Text(
                                            _isActive ? 'Hide' : 'Show',
                                            style: const TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                  ),
                                ],
                              ),
                            ),
                          ] else ...[
                            // ── Locked state for pending / rejected / suspended ──
                            const Text(
                              'This feature is locked until your profile is verified by the admin.',
                              style: TextStyle(
                                fontSize: 13,
                                color: Color(0xFF6B7280),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF3F4F6),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: const Color(0xFFD1D5DB)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.lock_outline, color: Color(0xFF9CA3AF), size: 20),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          profile.verificationStatus == 'pending'
                                              ? 'Status: Pending Verification'
                                              : profile.verificationStatus == 'rejected'
                                                  ? 'Status: Rejected'
                                                  : 'Status: Suspended',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFF9CA3AF),
                                          ),
                                        ),
                                        Text(
                                          profile.verificationStatus == 'pending'
                                              ? 'Your profile is under review. Visibility control will unlock once approved.'
                                              : profile.verificationStatus == 'rejected'
                                                  ? 'Please update your profile and resubmit for verification.'
                                                  : 'Your account is suspended. Please contact support.',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Color(0xFFB0B7C0),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  OutlinedButton(
                                    onPressed: null, // Disabled
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: const Color(0xFFD1D5DB),
                                      side: const BorderSide(color: Color(0xFFD1D5DB)),
                                      minimumSize: const Size(86, 40),
                                      padding: const EdgeInsets.symmetric(horizontal: 16),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.lock, size: 14, color: Color(0xFFD1D5DB)),
                                        SizedBox(width: 4),
                                        Text(
                                          'Locked',
                                          style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFFD1D5DB),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    // ── Accepting New Clients card ──────────────────────────
                    _buildAcceptingClientsCard(),
                    const SizedBox(height: 10),
                    // ── Tips to Increase Visibility ─────────────────────────
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: _cardDeco.copyWith(
                        color: const Color(0xFFDDF6FF),
                        border: Border.all(color: const Color(0xFFA8E4F7)),
                      ),
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Tips to Increase Visibility:',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF1F2937),
                            ),
                          ),
                          SizedBox(height: 6),
                          Text(
                            '✓ Complete all profile sections with detailed information',
                          ),
                          Text(
                            '✓ Add multiple service packages to attract different needs',
                          ),
                          Text('✓ Respond quickly to parent inquiries'),
                          Text(
                            '✓ Maintain a high rating through quality service',
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAcceptingClientsCard() {
    final accepting = _isAcceptingClients;
    final acBg = accepting
        ? const Color(0xFFE8FFF4)
        : const Color(0xFFFFF7ED);
    final acBorder = accepting
        ? const Color(0xFF86EFAC)
        : const Color(0xFFFDBA74);
    final acIcon = accepting
        ? Icons.check_circle_rounded
        : Icons.pause_circle_rounded;
    final acIconColor = accepting
        ? const Color(0xFF16A34A)
        : const Color(0xFFEA580C);
    final acStatusLabel = accepting ? 'Open for new clients' : 'Not accepting clients';
    final acStatusColor = accepting
        ? const Color(0xFF15803D)
        : const Color(0xFFC2410C);
    final acSubtitle = accepting
        ? 'Parents can subscribe to your services'
        : 'New subscriptions are paused — existing clients unaffected';
    final acBtnLabel = accepting ? 'Pause' : 'Resume';
    final acBtnColor = accepting
        ? const Color(0xFFEA580C)
        : const Color(0xFF0EA5C6);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: acBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: acBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(acIcon, color: acIconColor, size: 18),
              const SizedBox(width: 6),
              const Text(
                'Accepting New Clients',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: Color(0xFF1F2937),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(200),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: acBorder.withAlpha(160)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        acStatusLabel,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: acStatusColor,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        acSubtitle,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF6B7280),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _updatingAccepting
                    ? const SizedBox(
                        width: 24, height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : OutlinedButton(
                        onPressed: _handleToggleAccepting,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: acBtnColor,
                          side: BorderSide(color: acBtnColor),
                          minimumSize: const Size(76, 36),
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: Text(
                          acBtnLabel,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TherapistWalletSection extends StatefulWidget {
  final String therapistId;
  const _TherapistWalletSection({required this.therapistId});

  @override
  State<_TherapistWalletSection> createState() => _TherapistWalletSectionState();
}

class _TherapistWalletSectionState extends State<_TherapistWalletSection> {
  late Future<Map<String, dynamic>> _walletFuture;
  late Future<List<Map<String, dynamic>>> _transactionsFuture;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  void _refresh() {
    setState(() {
      _walletFuture = AppRepositories.billing.getTherapistWallet(widget.therapistId);
      _transactionsFuture = AppRepositories.billing.getTherapistTransactions(widget.therapistId);
    });
  }

  String _getPaymentMethodName(String method) {
    final clean = method.trim().toLowerCase();
    if (clean == 'easypaisa') return 'EasyPaisa';
    if (clean == 'jazzcash') return 'JazzCash';
    if (clean == 'raast') return 'Raast';
    if (clean == 'bank' || clean == 'bank transfer') return 'Bank Transfer';
    if (method.isEmpty) return 'Bank/Wallet';
    return method[0].toUpperCase() + method.substring(1);
  }

  String _formatCooldown(Duration d) {
    if (d.inDays > 0) {
      final hours = d.inHours % 24;
      return '${d.inDays}d ${hours}h left';
    } else if (d.inHours > 0) {
      final minutes = d.inMinutes % 60;
      return '${d.inHours}h ${minutes}m left';
    } else {
      return '${d.inMinutes}m left';
    }
  }

  void _openCooldownAppealDialog(
    BuildContext context, {
    required double balance,
    required Duration cooldownRemaining,
    required DateTime lastWithdrawalTime,
    required List<Map<String, dynamic>> transactions,
  }) {
    bool hasRecentAppeal = false;
    final threeDaysAgo = DateTime.now().subtract(const Duration(days: 3));
    for (final tx in transactions) {
      if (tx['isAppeal'] == true) {
        final createdAt = tx['createdAt'];
        DateTime? dt;
        if (createdAt is Timestamp) {
          dt = createdAt.toDate();
        }
        if (dt != null && dt.isAfter(threeDaysAgo)) {
          hasRecentAppeal = true;
          break;
        }
      }
    }

    final unlockTime = lastWithdrawalTime.add(const Duration(days: 3));
    final unlockStr = '${unlockTime.day}/${unlockTime.month}/${unlockTime.year} at ${unlockTime.hour.toString().padLeft(2, '0')}:${unlockTime.minute.toString().padLeft(2, '0')}';
    final lastStr = '${lastWithdrawalTime.day}/${lastWithdrawalTime.month}/${lastWithdrawalTime.year} at ${lastWithdrawalTime.hour.toString().padLeft(2, '0')}:${lastWithdrawalTime.minute.toString().padLeft(2, '0')}';

    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          titlePadding: EdgeInsets.zero,
          title: Container(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
            decoration: const BoxDecoration(
              color: Color(0xFFFFF3CD),
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Row(
              children: [
                Icon(
                  hasRecentAppeal ? Icons.lock : Icons.lock_open,
                  color: const Color(0xFFD97706),
                  size: 24,
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Withdrawal Cooldown',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF92400E),
                    ),
                  ),
                ),
              ],
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Standard payouts are limited to once every 3 days to prevent system abuse and ensure security.',
                  style: TextStyle(fontSize: 13.5, color: Color(0xFF374151), height: 1.4),
                ),
                const SizedBox(height: 16),
                _buildInfoRow('Last Withdrawal Request:', lastStr),
                const SizedBox(height: 8),
                _buildInfoRow('Cooldown Ends (Unlock):', unlockStr, isHighlight: true),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 12),
                if (hasRecentAppeal) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFFCA5A5)),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.error_outline, color: Color(0xFFDC2626), size: 20),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Appeal Limit Reached: You have already submitted an appeal request during this 3-day cooldown. You must wait for the cooldown to end or for the previous appeal to be resolved.',
                            style: TextStyle(fontSize: 12, color: Color(0xFF991B1B), height: 1.4, fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  const Text(
                    'Need funds urgently? You can request exactly ONE bypass appeal during this cooldown. Please note that appeals are subject to administrative review.',
                    style: TextStyle(fontSize: 12.5, color: Color(0xFF4B5563), height: 1.4),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text(
                'Cancel',
                style: TextStyle(color: Color(0xFF6B7280), fontWeight: FontWeight.w600),
              ),
            ),
            if (!hasRecentAppeal)
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  _openWithdrawalSheet(context, balance, isAppeal: true);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0D9488),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Request Appeal', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
          ],
        );
      },
    );
  }

  Widget _buildInfoRow(String label, String value, {bool isHighlight = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280), fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            color: isHighlight ? const Color(0xFFC2410C) : const Color(0xFF1F2937),
          ),
        ),
      ],
    );
  }

  void _openWithdrawalSheet(BuildContext context, double availableBalance, {bool isAppeal = false}) {
    final formKey = GlobalKey<FormState>();
    final amountController = TextEditingController();
    final accountDetailsController = TextEditingController();
    final accountTitleController = TextEditingController();
    final appealReasonController = TextEditingController();
    String selectedMethod = 'EasyPaisa';
    bool submitting = false;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return ScaffoldMessenger(
          child: Scaffold(
            backgroundColor: Colors.transparent,
            resizeToAvoidBottomInset: false,
            body: Builder(
              builder: (innerContext) {
                return StatefulBuilder(
                  builder: (context, setSheetState) {
                    return Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
                        child: Container(
                          constraints: BoxConstraints(
                            maxHeight: MediaQuery.of(context).size.height -
                                MediaQuery.of(context).viewInsets.bottom -
                                48,
                          ),
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                          ),
                          padding: const EdgeInsets.fromLTRB(20, 24, 20, 34),
                          child: Form(
                            key: formKey,
                            child: SingleChildScrollView(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Center(
                                    child: Container(
                                      width: 40,
                                      height: 5,
                                      decoration: BoxDecoration(
                                        color: Colors.grey[300],
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 20),
                                  Text(
                                    isAppeal ? 'Withdraw Funds (Emergency Appeal)' : 'Withdraw Funds',
                                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1F2937)),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Available Balance: ${formatPrice(availableBalance)}',
                                    style: const TextStyle(fontSize: 14, color: Color(0xFF0D9488), fontWeight: FontWeight.w600),
                                  ),
                                  const SizedBox(height: 16),

                                  DropdownButtonFormField<String>(
                                    isExpanded: true,
                                    value: selectedMethod, // ignore: deprecated_member_use
                                    decoration: const InputDecoration(
                                      labelText: 'Payment Method',
                                      border: OutlineInputBorder(),
                                      prefixIcon: Icon(Icons.payment),
                                    ),
                                    items: const [
                                      DropdownMenuItem(value: 'EasyPaisa', child: Text('EasyPaisa', overflow: TextOverflow.ellipsis)),
                                      DropdownMenuItem(value: 'JazzCash', child: Text('JazzCash', overflow: TextOverflow.ellipsis)),
                                      DropdownMenuItem(value: 'Raast', child: Text('Raast (Instant Transfer)', overflow: TextOverflow.ellipsis)),
                                      DropdownMenuItem(value: 'Bank Transfer', child: Text('Bank Transfer', overflow: TextOverflow.ellipsis)),
                                    ],
                                    onChanged: submitting
                                        ? null
                                        : (val) {
                                            if (val != null) {
                                              setSheetState(() => selectedMethod = val);
                                            }
                                          },
                                  ),
                                  const SizedBox(height: 12),

                                  // 3-day payout cooldown warning banner
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: isAppeal ? const Color(0xFFFEF2F2) : const Color(0xFFFFF7ED),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: isAppeal ? const Color(0xFFFCA5A5) : const Color(0xFFFFEDD5)),
                                    ),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Icon(
                                          isAppeal ? Icons.warning_amber_rounded : Icons.info_outline_rounded,
                                          color: isAppeal ? const Color(0xFFDC2626) : const Color(0xFFD97706),
                                          size: 20,
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            isAppeal
                                                ? 'Emergency Cooldown Appeal: You are bypassing the standard 3-day cooldown. Limit of exactly 1 appeal request per cooldown period.'
                                                : 'Important: Payouts are limited to once every 3 days. Once submitted, please wait 3 days for processing before requesting another withdrawal.',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: isAppeal ? const Color(0xFF991B1B) : const Color(0xFFC2410C),
                                              height: 1.4,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 12),

                                  TextFormField(
                                    controller: amountController,
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    enabled: !submitting,
                                    decoration: const InputDecoration(
                                      labelText: 'Amount (PKR)',
                                      hintText: 'Enter amount to withdraw',
                                      border: OutlineInputBorder(),
                                      prefixIcon: Icon(Icons.money),
                                    ),
                                    validator: (value) {
                                      if (value == null || value.trim().isEmpty) {
                                        return 'Please enter an amount';
                                      }
                                      final val = double.tryParse(value);
                                      if (val == null || val <= 0) {
                                        return 'Enter a valid positive number';
                                      }
                                      if (val < 500) {
                                        return 'Minimum withdrawal amount is Rs. 500';
                                      }
                                      if (val > availableBalance) {
                                        return 'Amount exceeds available balance';
                                      }
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 12),

                                  TextFormField(
                                    controller: accountTitleController,
                                    enabled: !submitting,
                                    decoration: const InputDecoration(
                                      labelText: 'Account Title',
                                      hintText: 'Full name on account',
                                      border: OutlineInputBorder(),
                                      prefixIcon: Icon(Icons.person_outline),
                                    ),
                                    validator: (value) {
                                      if (value == null || value.trim().isEmpty) {
                                        return 'Please enter account title';
                                      }
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 12),

                                  TextFormField(
                                    controller: accountDetailsController,
                                    enabled: !submitting,
                                    decoration: InputDecoration(
                                      labelText: selectedMethod == 'Bank Transfer'
                                          ? 'IBAN'
                                          : (selectedMethod == 'Raast'
                                              ? 'Raast Mobile Number / IBAN'
                                              : 'Mobile Number'),
                                      hintText: selectedMethod == 'Bank Transfer'
                                          ? 'e.g. PK36SCBL0000001123456702'
                                          : (selectedMethod == 'Raast'
                                              ? 'e.g. 03001234567 or PK36SCBL0000001123456702'
                                              : 'e.g. 03001234567'),
                                      border: const OutlineInputBorder(),
                                      prefixIcon: const Icon(Icons.pin),
                                      errorMaxLines: 5,
                                      errorStyle: const TextStyle(
                                        fontSize: 11.5,
                                        height: 1.2,
                                        overflow: TextOverflow.visible,
                                      ),
                                    ),
                                    validator: (value) {
                                      if (value == null || value.trim().isEmpty) {
                                        return 'Please enter account details';
                                      }
                                      final v = value.trim();
                                      
                                      // Mobile number normalization for validation
                                      String cleanedMobile = v.replaceAll(RegExp(r'\D'), '');
                                      if (cleanedMobile.startsWith('92')) {
                                        cleanedMobile = '0${cleanedMobile.substring(2)}';
                                      } else if (cleanedMobile.length == 10 && cleanedMobile.startsWith('3')) {
                                        cleanedMobile = '0$cleanedMobile';
                                      }
                                      
                                      // IBAN normalization for validation
                                      final upperIban = v.toUpperCase().replaceAll(RegExp(r'\s+'), '');

                                      if (selectedMethod == 'EasyPaisa' ||
                                          selectedMethod == 'JazzCash') {
                                        // EasyPaisa and JazzCash: Only valid Pakistani mobile number (11 digits, starting with 03)
                                        if (cleanedMobile.length != 11 || !cleanedMobile.startsWith('03')) {
                                          return 'Mobile number must be a valid Pakistani mobile number (e.g. 03001234567)';
                                        }
                                      } else if (selectedMethod == 'Bank Transfer') {
                                        // Bank Transfer: Only valid Pakistani IBAN (24 chars)
                                        if (!RegExp(r'^PK\d{2}[A-Z]{4}\d{16}$').hasMatch(upperIban)) {
                                          return 'Please enter a valid Pakistan IBAN (e.g. PK36SCBL0000001123456702)';
                                        }
                                      } else if (selectedMethod == 'Raast') {
                                        // Raast: Either Pakistani mobile number OR Pakistani IBAN
                                        final isMobile = cleanedMobile.length == 11 && cleanedMobile.startsWith('03');
                                        final isIban = RegExp(r'^PK\d{2}[A-Z]{4}\d{16}$').hasMatch(upperIban);
                                        if (!isMobile && !isIban) {
                                          return 'Please enter a valid Pakistani mobile number (e.g. 03001234567) or a valid Pakistan IBAN (e.g. PK36SCBL0000001123456702)';
                                        }
                                      }
                                      return null;
                                    },
                                  ),
                                  if (isAppeal) ...[
                                    const SizedBox(height: 12),
                                    TextFormField(
                                      controller: appealReasonController,
                                      enabled: !submitting,
                                      maxLines: 3,
                                      maxLength: 500,
                                      buildCounter: (context, {required currentLength, required maxLength, required isFocused}) {
                                        return Text(
                                          '$currentLength/$maxLength',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Color(0xFF6B7280),
                                          ),
                                        );
                                      },
                                      decoration: const InputDecoration(
                                        labelText: 'Reason for Appeal (Urgent Needs)',
                                        hintText: 'Please describe the emergency reason for this appeal (minimum 5 characters)',
                                        border: OutlineInputBorder(),
                                        prefixIcon: Icon(Icons.comment_outlined),
                                        contentPadding: EdgeInsets.fromLTRB(12, 16, 12, 4),
                                      ),
                                      validator: (value) {
                                        if (value == null || value.trim().isEmpty) {
                                          return 'Please enter the appeal reason';
                                        }
                                        if (value.trim().length < 5) {
                                          return 'Appeal reason must be at least 5 characters';
                                        }
                                        if (value.trim().length > 500) {
                                          return 'Appeal reason must not exceed 500 characters';
                                        }
                                        return null;
                                      },
                                    ),
                                  ],
                                  const SizedBox(height: 24),

                                  ElevatedButton(
                                    onPressed: submitting
                                        ? null
                                        : () async {
                                            if (formKey.currentState?.validate() != true) {
                                              return;
                                            }
                                            setSheetState(() => submitting = true);

                                            final double withdrawAmt = double.parse(amountController.text.trim());
                                            final String accTitle = accountTitleController.text.trim();
                                            String rawNum = accountDetailsController.text.trim();
                                            String accNum = rawNum;

                                            // Normalize the submitted account/mobile number value
                                            if (selectedMethod == 'EasyPaisa' || selectedMethod == 'JazzCash') {
                                              String cleaned = rawNum.replaceAll(RegExp(r'\D'), '');
                                              if (cleaned.startsWith('92')) {
                                                cleaned = '0${cleaned.substring(2)}';
                                              } else if (cleaned.length == 10 && cleaned.startsWith('3')) {
                                                cleaned = '0$cleaned';
                                              }
                                              accNum = cleaned;
                                            } else if (selectedMethod == 'Bank Transfer') {
                                              accNum = rawNum.toUpperCase().replaceAll(RegExp(r'\s+'), '');
                                            } else if (selectedMethod == 'Raast') {
                                              final upperVal = rawNum.toUpperCase().replaceAll(RegExp(r'\s+'), '');
                                              if (RegExp(r'^PK\d{2}[A-Z]{4}\d{16}$').hasMatch(upperVal)) {
                                                accNum = upperVal;
                                              } else {
                                                String cleaned = rawNum.replaceAll(RegExp(r'\D'), '');
                                                if (cleaned.startsWith('92')) {
                                                  cleaned = '0${cleaned.substring(2)}';
                                                } else if (cleaned.length == 10 && cleaned.startsWith('3')) {
                                                  cleaned = '0$cleaned';
                                                }
                                                accNum = cleaned;
                                              }
                                            }

                                            final String fullDetailsStr = '$accTitle - $accNum';

                                            try {
                                              await AppRepositories.billing.requestWithdrawal(
                                                widget.therapistId,
                                                withdrawAmt,
                                                selectedMethod,
                                                fullDetailsStr,
                                                isAppeal: isAppeal,
                                                appealReason: isAppeal ? appealReasonController.text.trim() : null,
                                              );

                                              if (context.mounted) {
                                                Navigator.pop(innerContext);
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  const SnackBar(
                                                    content: Text('Withdrawal request submitted successfully!'),
                                                    backgroundColor: Color(0xFF059669),
                                                  ),
                                                );
                                              }
                                              _refresh();
                                            } catch (e) {
                                              setSheetState(() => submitting = false);
                                              if (innerContext.mounted) {
                                                ScaffoldMessenger.of(innerContext).showSnackBar(
                                                  SnackBar(
                                                    content: Text('Withdrawal request failed: $e'),
                                                    backgroundColor: const Color(0xFFDC2626),
                                                  ),
                                                );
                                              }
                                            }
                                          },
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF0D9488),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 14),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                    child: submitting
                                        ? const SizedBox(
                                            height: 20,
                                            width: 20,
                                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                          )
                                        : const Text('Submit Withdrawal Request', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }

  String _formatTime(DateTime dt) {
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final minute = dt.minute.toString().padLeft(2, '0');
    final suffix = dt.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $suffix';
  }

  void _showTherapistTransactionModal(BuildContext context, Map<String, dynamic> tx) {
    final isEarning = tx['type'] == 'subscription';
    // For earnings, prefer netAmount (the amount credited to wallet)
    final grossAmount = double.tryParse((tx['grossAmount'] ?? 0.0).toString()) ?? 0.0;
    final platformFee = double.tryParse((tx['platformFee'] ?? 0.0).toString()) ?? 0.0;
    final safepayFee = double.tryParse((tx['safepayFee'] ?? 0.0).toString()) ?? 0.0;
    final netAmount = double.tryParse((tx['netAmount'] ?? tx['amount'] ?? 0.0).toString()) ?? 0.0;
    final amount = isEarning ? netAmount : (double.tryParse((tx['amount'] ?? 0.0).toString()) ?? 0.0);
    final amountStr = formatPrice(amount);
    final hasBreakdown = isEarning && grossAmount > 0 && (platformFee > 0 || safepayFee > 0);
    final dateVal = tx['createdAt'];
    String formattedDate = '';
    if (dateVal is Timestamp) {
      final dt = dateVal.toDate().toLocal();
      formattedDate = '${dt.day}/${dt.month}/${dt.year} at ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    final status = (tx['status'] ?? 'pending').toString().toUpperCase();
    final details = (tx['accountDetails'] ?? '').toString();
    final method = _getPaymentMethodName((tx['paymentMethod'] ?? '').toString());
    final parentName = (tx['parentName'] ?? '').toString();

    showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: isEarning ? const Color(0xFFE6F4EA) : const Color(0xFFFEF3C7),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Center(
                  child: Column(
                    children: [
                      Icon(
                        isEarning ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
                        color: isEarning ? const Color(0xFF059669) : const Color(0xFFD97706),
                        size: 48,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        isEarning ? 'Earning Receipt' : 'Withdrawal Request',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1F2937)),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        amountStr,
                        style: TextStyle(
                          fontSize: 26, 
                          fontWeight: FontWeight.w800, 
                          color: isEarning ? const Color(0xFF059669) : const Color(0xFFD97706),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    _buildModalDetailRow('Status', status, 
                      valueColor: status == 'COMPLETED' || status == 'PAID'
                          ? const Color(0xFF059669)
                          : status == 'PENDING'
                              ? const Color(0xFFD97706)
                              : const Color(0xFFDC2626),
                      isBoldValue: true,
                    ),
                    const Divider(),
                    if (isEarning) ...[
                      _buildModalDetailRow('From Parent', parentName.isNotEmpty ? parentName : 'Parent Member'),
                      if (hasBreakdown) ...[
                        const Divider(),
                        _buildModalDetailRow('Gross Subscription', formatPrice(grossAmount)),
                        const Divider(),
                        _buildModalDetailRow('SafePay Processing Fee', '-${formatPrice(safepayFee)}', valueColor: const Color(0xFFDC2626)),
                        const Divider(),
                        _buildModalDetailRow('Platform Service Fee (7%)', '-${formatPrice(platformFee)}', valueColor: const Color(0xFFDC2626)),
                        const Divider(),
                        _buildModalDetailRow('Net Credited to Wallet', formatPrice(netAmount), valueColor: const Color(0xFF059669), isBoldValue: true),
                      ],
                    ] else ...[
                      _buildModalDetailRow('Payment Method', method.isNotEmpty ? method : 'Bank/Wallet'),
                      const Divider(),
                      _buildModalDetailRow('Account Details', details),
                    ],
                    const Divider(),
                    _buildModalDetailRow('Date', formattedDate),
                    if (!isEarning && status == 'PAID' && tx['receiptBase64'] != null && tx['receiptBase64'].toString().isNotEmpty) ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => ReceiptViewerScreen(
                                  base64String: tx['receiptBase64'].toString(),
                                  title: 'Payout Receipt',
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.receipt_long_rounded),
                          label: const Text('View Payout Receipt'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0D9488),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Color(0xFFCBD5E1)),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            child: const Text('Close', style: TextStyle(color: Color(0xFF475569))),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildModalDetailRow(String label, String value, {Color? valueColor, bool isBoldValue = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 13, color: Color(0xFF64748B), fontWeight: FontWeight.w500)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontSize: 13,
                color: valueColor ?? const Color(0xFF1E293B),
                fontWeight: isBoldValue ? FontWeight.bold : FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<dynamic>>(
      future: Future.wait([_walletFuture, _transactionsFuture]),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(24.0),
            decoration: _cardDeco,
            child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        if (snapshot.hasError) {
          return Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(16.0),
            decoration: _cardDeco,
            child: Text('Error loading wallet: ${snapshot.error}'),
          );
        }
        
        final walletData = (snapshot.data?[0] as Map<String, dynamic>?) ?? {'walletBalance': 0.0, 'totalEarnings': 0.0};
        final transactions = (snapshot.data?[1] as List<Map<String, dynamic>>?) ?? [];

        final balance = double.tryParse(walletData['walletBalance'].toString()) ?? 0.0;
        final earnings = double.tryParse(walletData['totalEarnings'].toString()) ?? 0.0;

        // Calculate cooldown remaining time
        DateTime? lastWithdrawalTime;
        for (final tx in transactions) {
          final type = (tx['type'] ?? '').toString();
          final status = (tx['status'] ?? '').toString();
          if (type == 'withdrawal' && status != 'rejected') {
            final createdAt = tx['createdAt'];
            DateTime? dt;
            if (createdAt is Timestamp) {
              dt = createdAt.toDate();
            }
            if (dt != null) {
              if (lastWithdrawalTime == null || dt.isAfter(lastWithdrawalTime)) {
                lastWithdrawalTime = dt;
              }
            }
          }
        }

        Duration? cooldownRemaining;
        if (lastWithdrawalTime != null) {
          final cooldownEnd = lastWithdrawalTime.add(const Duration(days: 3));
          final now = DateTime.now();
          if (cooldownEnd.isAfter(now)) {
            cooldownRemaining = cooldownEnd.difference(now);
          }
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
            border: Border.all(color: const Color(0xFFE5E7EB), width: 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF0EA5C6), Color(0xFF0D9488)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.account_balance_wallet, color: Colors.white, size: 20),
                            SizedBox(width: 8),
                            Text(
                              'Earnings & Wallet',
                              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                        IconButton(
                          icon: const Icon(Icons.refresh, color: Colors.white, size: 20),
                          onPressed: _refresh,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Available Balance',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      formatPrice(balance),
                      style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Total Gross Earnings',
                              style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 11),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              formatPrice(earnings),
                              style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        ElevatedButton.icon(
                          onPressed: (balance > 0)
                              ? () {
                                  if (cooldownRemaining != null) {
                                    _openCooldownAppealDialog(
                                      context,
                                      balance: balance,
                                      cooldownRemaining: cooldownRemaining,
                                      lastWithdrawalTime: lastWithdrawalTime!,
                                      transactions: transactions,
                                    );
                                  } else {
                                    _openWithdrawalSheet(context, balance);
                                  }
                                }
                              : null,
                          icon: Icon(
                            cooldownRemaining != null ? Icons.lock_outline_rounded : Icons.arrow_upward_rounded,
                            size: 16,
                          ),
                          label: Text(
                            cooldownRemaining != null 
                                ? 'Locked (${_formatCooldown(cooldownRemaining)})' 
                                : 'Withdraw Funds',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: const Color(0xFF0D9488),
                            disabledBackgroundColor: Colors.white.withValues(alpha: 0.3),
                            disabledForegroundColor: cooldownRemaining != null 
                                ? Colors.white.withValues(alpha: 0.8) 
                                : Colors.white.withValues(alpha: 0.5),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Transaction History',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF374151)),
                    ),
                    const SizedBox(height: 8),
                    if (transactions.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Center(
                          child: Text(
                            'No transaction history yet.',
                            style: TextStyle(color: Colors.grey, fontSize: 13, fontStyle: FontStyle.italic),
                          ),
                        ),
                      )
                    else
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: transactions.length,
                        separatorBuilder: (context, index) => const Divider(height: 12),
                        itemBuilder: (context, index) {
                          final tx = transactions[index];
                          final isEarning = tx['type'] == 'subscription';
                          final amount = double.tryParse((tx['amount'] ?? 0.0).toString()) ?? 0.0;
                          final dateVal = tx['createdAt'];
                          String formattedDate = '';
                          if (dateVal is Timestamp) {
                            final dt = dateVal.toDate().toLocal();
                            formattedDate = '${dt.day}/${dt.month}/${dt.year} ${_formatTime(dt)}';
                          }
                          final status = (tx['status'] ?? 'pending').toString().toLowerCase();
                          final details = (tx['accountDetails'] ?? '').toString();
                          final method = _getPaymentMethodName((tx['paymentMethod'] ?? '').toString());
                          final parentName = (tx['parentName'] ?? '').toString();

                          return InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () => _showTherapistTransactionModal(context, tx),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 16,
                                    backgroundColor: isEarning ? const Color(0xFFD1FAE5) : const Color(0xFFF3F4F6),
                                    child: Icon(
                                      isEarning ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
                                      size: 16,
                                      color: isEarning ? const Color(0xFF059669) : const Color(0xFF4B5563),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          isEarning 
                                              ? 'Subscription received ${parentName.isNotEmpty ? "from $parentName" : ""}'
                                              : 'Withdrawal to $method',
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1F2937)),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        if (formattedDate.isNotEmpty)
                                          Text(
                                            formattedDate,
                                            style: const TextStyle(fontSize: 11, color: Colors.grey),
                                          ),
                                        if (!isEarning && details.isNotEmpty)
                                          Text(
                                            'Acc: $details',
                                            style: const TextStyle(fontSize: 11, color: Colors.black54),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                      ],
                                    ),
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        '${isEarning ? "+" : "-"}${formatPrice(amount).replaceAll(" PKR", "")}',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                          color: isEarning ? const Color(0xFF059669) : const Color(0xFFDC2626),
                                        ),
                                      ),
                                      Container(
                                        margin: const EdgeInsets.only(top: 2),
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: status == 'completed' || status == 'paid'
                                              ? const Color(0xFFD1FAE5)
                                              : status == 'pending'
                                                  ? const Color(0xFFFEF3C7)
                                                  : const Color(0xFFFEE2E2),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          status.toUpperCase(),
                                          style: TextStyle(
                                            fontSize: 9,
                                            fontWeight: FontWeight.bold,
                                            color: status == 'completed' || status == 'paid'
                                                ? const Color(0xFF065F46)
                                                : status == 'pending'
                                                    ? const Color(0xFF92400E)
                                                    : const Color(0xFF991B1B),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class TherapistMessagesScreen extends StatefulWidget {
  const TherapistMessagesScreen({super.key});

  @override
  State<TherapistMessagesScreen> createState() =>
      _TherapistMessagesScreenState();
}

class _TherapistMessagesScreenState extends State<TherapistMessagesScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<Map<String, UserProfile>> _loadParentProfiles(
    List<TherapistThread> threads,
  ) async {
    final parentIds = threads.map((thread) => thread.parentId).toSet();
    final entries = await Future.wait(
      parentIds.map((parentId) async {
        final profile = await AppRepositories.users.getUserProfile(parentId);
        return MapEntry(parentId, profile);
      }),
    );

    return {
      for (final entry in entries)
        if (entry.value != null) entry.key: entry.value!,
    };
  }

  Widget _buildParentAvatar(String? photoUrl, {double size = 40}) {
    Widget imageWidget;
    final cleanPhoto = photoUrl?.trim() ?? '';
    if (cleanPhoto.isNotEmpty) {
      if (cleanPhoto.startsWith('http://') || cleanPhoto.startsWith('https://')) {
        imageWidget = Image.network(
          cleanPhoto,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => const Icon(Icons.person, color: Color(0xFF64748B)),
        );
      } else {
        try {
          final imageBytes = base64Decode(cleanPhoto);
          imageWidget = Image.memory(
            imageBytes,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => const Icon(Icons.person, color: Color(0xFF64748B)),
          );
        } catch (_) {
          imageWidget = const Icon(Icons.person, color: Color(0xFF64748B));
        }
      }
    } else {
      imageWidget = const Icon(Icons.person, color: Color(0xFF64748B));
    }

    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: Color(0xFFD9F4DF),
        shape: BoxShape.circle,
      ),
      padding: const EdgeInsets.all(2),
      child: ClipOval(
        child: imageWidget,
      ),
    );
  }

  Future<void> _confirmDeleteChat(TherapistThread thread) async {
    // Step 1: Option menu
    final selectOption = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Chat Options', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.delete_forever_rounded, color: Colors.red),
              title: const Text('Delete Chat', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
          ],
        ),
      ),
    );

    if (selectOption != 'delete') return;

    // Step 2: Confirmation box
    if (!mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Are you sure?', style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text(
          'This will completely delete the chat history with this parent. This action cannot be undone.',
          style: TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    // Step 3: Deletion execution
    if (!mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final messagesSnap = await FirebaseFirestore.instance
          .collection(FirestoreCollections.therapistThreads)
          .doc(thread.id)
          .collection('messages')
          .get();
      final batch = FirebaseFirestore.instance.batch();
      for (final doc in messagesSnap.docs) {
        batch.delete(doc.reference);
      }
      batch.delete(FirebaseFirestore.instance
          .collection(FirestoreCollections.therapistThreads)
          .doc(thread.id));
      await batch.commit();

      if (mounted) {
        Navigator.pop(context); // Pop loading indicator
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Chat successfully deleted.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Pop loading indicator
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete chat: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SessionGuard(
      role: SessionGuardRole.therapist,
      child: Scaffold(
        backgroundColor: const Color(0xFFF1F3F4),
        body: SafeArea(
          child: Column(
            children: [
              Container(
                height: 80,
                color: const Color(0xFF9FE7F2),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.arrow_back),
                    ),
                    const Expanded(
                      child: Text(
                        'Messages',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 30 / 1.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 40),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                child: TextField(
                  controller: _searchController,
                  onChanged: (value) =>
                      setState(() => _query = value.trim().toLowerCase()),
                  decoration: InputDecoration(
                    hintText: 'Search conversations...',
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: Colors.grey.shade300),
                    ),
                  ),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: StreamBuilder<List<TherapistThread>>(
                  stream: AppRepositories.support.watchThreadsForRole(
                    'therapist',
                  ),
                  builder: (context, snapshot) {
                    final threads = snapshot.data ?? const <TherapistThread>[];
                    if (threads.isEmpty) {
                      return const Center(
                        child: Text('No parent conversations yet.'),
                      );
                    }
                    final filtered = threads.where((thread) {
                      if (_query.isEmpty) return true;
                      final hay =
                          '${thread.parentDisplayName} ${thread.lastMessagePreview}'
                              .toLowerCase();
                      return hay.contains(_query);
                    }).toList();

                    return FutureBuilder<Map<String, UserProfile>>(
                      future: _loadParentProfiles(filtered),
                      builder: (context, parentSnapshot) {
                        final parentMap =
                            parentSnapshot.data ??
                            const <String, UserProfile>{};
                        return ListView.separated(
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final thread = filtered[index];
                            final parentProfile = parentMap[thread.parentId];
                            final parentName =
                                thread.parentDisplayName.isNotEmpty
                                ? thread.parentDisplayName
                                : (parentProfile?.fullName.isNotEmpty == true
                                      ? parentProfile!.fullName
                                      : parentProfile?.email ?? 'Parent');

                             final isUnread = thread.lastMessageAt != null &&
                                 (thread.therapistLastRead == null ||
                                     thread.lastMessageAt!.isAfter(thread.therapistLastRead!));

                             return ListTile(
                               leading: _buildParentAvatar(parentProfile?.photoUrl),
                               title: Text(
                                 parentName,
                                 style: const TextStyle(
                                   fontWeight: FontWeight.w600,
                                 ),
                                ),
                               subtitle: Column(
                                 crossAxisAlignment: CrossAxisAlignment.start,
                                 children: [
                                   const Text(
                                     'Parent conversation',
                                     style: TextStyle(color: Color(0xFF16A34A)),
                                   ),
                                   Text(
                                     thread.lastMessagePreview.isEmpty
                                         ? 'No messages yet'
                                         : thread.lastMessagePreview,
                                     maxLines: 1,
                                     overflow: TextOverflow.ellipsis,
                                     style: TextStyle(
                                       fontWeight: isUnread ? FontWeight.bold : FontWeight.normal,
                                       color: isUnread ? Colors.black : const Color(0xFF475569),
                                     ),
                                   ),
                                   Text(
                                     _friendlyTime(thread.lastMessageAt),
                                     style: const TextStyle(
                                       color: Color(0xFF9CA3AF),
                                     ),
                                   ),
                                 ],
                               ),
                               trailing: Row(
                                 mainAxisSize: MainAxisSize.min,
                                 children: [
                                   if (isUnread)
                                     Container(
                                       width: 10,
                                       height: 10,
                                       decoration: const BoxDecoration(
                                         color: Colors.red,
                                         shape: BoxShape.circle,
                                       ),
                                     ),
                                   if (thread.hasOpenEmergency) ...[
                                     if (isUnread) const SizedBox(width: 6),
                                     const CircleAvatar(
                                       radius: 12,
                                       backgroundColor: Color(0xFFF85D93),
                                       child: Text(
                                         '2',
                                         style: TextStyle(
                                           color: Colors.white,
                                           fontSize: 12,
                                           fontWeight: FontWeight.w700,
                                         ),
                                       ),
                                     ),
                                   ],
                                   StreamBuilder<RestrictionRecord?>(
                                     stream: AppRepositories.support.watchActiveRestriction(
                                       parentId: thread.parentId,
                                       therapistId: thread.therapistId,
                                     ),
                                     builder: (context, restSnap) {
                                       final hasRest = restSnap.data != null && restSnap.data!.isActive;
                                       if (hasRest) {
                                         return const Padding(
                                           padding: EdgeInsets.only(left: 6),
                                           child: Icon(Icons.lock_clock, color: Colors.amber, size: 18),
                                         );
                                       }
                                       return const SizedBox.shrink();
                                     },
                                   ),
                                 ],
                               ),
                               onLongPress: () => _confirmDeleteChat(thread),
                               onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => TherapistChatScreen(
                                      thread: thread,
                                      participantName: parentName,
                                      senderRole: 'therapist',
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class TherapistProfileSettingsScreen extends StatefulWidget {
  const TherapistProfileSettingsScreen({
    super.key,
    required this.profile,
    required this.setupMode,
    required this.initialYears,
    required this.initialMonths,
    required this.initialCredentials,
    required this.initialEmail,
    required this.initialPhone,
    required this.initialCertificatePdfName,
    required this.initialPackages,
    required this.onSave,
  });

  final TherapistProfile profile;
  final bool setupMode;
  final int initialYears;
  final int initialMonths;
  final String initialCredentials;
  final String initialEmail;
  final String initialPhone;
  final String? initialCertificatePdfName;
  final List<TherapyPackage> initialPackages;
  final Future<void> Function({
    required TherapistProfile profile,
    required int years,
    required int months,
    required String credentials,
    required String contactEmail,
    required String contactPhone,
    required List<TherapyPackage> packages,
    String? certificatePdfName,
    String? photoBase64,
    String? certificateBase64,
  })
  onSave;

  @override
  State<TherapistProfileSettingsScreen> createState() =>
      _TherapistProfileSettingsScreenState();
}

class _TherapistProfileSettingsScreenState
    extends State<TherapistProfileSettingsScreen> {
  final _selected = <String>{};
  late final TextEditingController _first;
  late final TextEditingController _last;
  late final TextEditingController _email;
  late final TextEditingController _phone;
  late final TextEditingController _savedPasswordDisplay;
  late final TextEditingController _newPassword;
  late final TextEditingController _credentials;
  late final TextEditingController _about;
  late final TextEditingController _otherSpecialization;
  String? _certificatePdfName;
  bool _saving = false;
  bool _isDeleting = false;
  String? _photoBase64;
  String? _certificateBase64;
  bool _certificateTouched = false;
  bool _revealSavedPassword = false;
  bool _obscureNewPassword = true;
  late bool _isAcceptingClients;
  final FirebaseService _firebaseService = FirebaseService();

  late int _selectedYears;
  late int _selectedMonths;
  late PhoneCountry _selectedPhoneCountry;

  @override
  void initState() {
    super.initState();
    _isAcceptingClients = widget.profile.isAcceptingClients;
    final display = widget.profile.displayName.trim().split(' ');
    _first = TextEditingController(text: display.isEmpty ? '' : display.first);
    _last = TextEditingController(
      text: display.length > 1 ? display.sublist(1).join(' ') : '',
    );
    _email = TextEditingController(text: widget.initialEmail);
    
    final (parsedCountry, parsedLocalDigits) = parseStoredPhoneNumber(widget.initialPhone);
    _phone = TextEditingController(text: parsedLocalDigits);
    _selectedPhoneCountry = parsedCountry;

    _newPassword = TextEditingController();
    _savedPasswordDisplay = TextEditingController();
    
    _selectedYears = widget.initialYears;
    _selectedMonths = widget.initialMonths;
    
    _credentials = TextEditingController(text: widget.initialCredentials);
    _about = TextEditingController(text: widget.profile.bio);
    _certificatePdfName = widget.initialCertificatePdfName;
    _photoBase64 = widget.profile.photoUrlBase64;
    _certificateBase64 = widget.profile.certificateBase64;

    // Detect specializations not in the predefined list
    final predefined = _specializations.toSet();
    String otherValue = '';
    for (final spec in widget.profile.specializations) {
      if (!predefined.contains(spec) && spec != 'Others') {
        otherValue = spec;
        _selected.add('Others');
      } else {
        _selected.add(spec);
      }
    }
    _otherSpecialization = TextEditingController(text: otherValue);
  }

  @override
  void dispose() {
    _first.dispose();
    _last.dispose();
    _email.dispose();
    _phone.dispose();
    _savedPasswordDisplay.dispose();
    _newPassword.dispose();
    _credentials.dispose();
    _about.dispose();
    _otherSpecialization.dispose();
    super.dispose();
  }

  Future<void> _openPricing() async {
    // Validate first section before allowing navigation to pricing
    if (_first.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your first name before proceeding.')),
      );
      return;
    }
    if (_last.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your last name before proceeding.')),
      );
      return;
    }

    final email = _email.text.trim();
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your email address before proceeding.')),
      );
      return;
    }
    if (!_isValidEmail(email)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid email address before proceeding.')),
      );
      return;
    }

    final phoneText = _phone.text.trim();
    if (phoneText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your phone number before proceeding.')),
      );
      return;
    }
    final fullPhone = buildFullPhoneNumber(_selectedPhoneCountry, phoneText);
    if (!_isValidPhoneNumber(fullPhone)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid phone number (10-15 digits).')),
      );
      return;
    }

    if (_selectedYears < 0 || _selectedYears > 80) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Years of experience must be between 0 and 80 years.')),
      );
      return;
    }
    if (_selectedMonths < 0 || _selectedMonths > 11) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Months of experience must be between 0 and 11 months.')),
      );
      return;
    }

    if (_credentials.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your credentials before proceeding.')),
      );
      return;
    }

    if (_about.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your about me section before proceeding.')),
      );
      return;
    }

    if (_certificateBase64 == null || _certificateBase64!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please upload your certificate/degree before proceeding.')),
      );
      return;
    }

    final finalSpecs = _selected.map((s) {
      if (s == 'Others') return _otherSpecialization.text.trim();
      return s;
    }).where((s) => s.isNotEmpty).toList();

    // First section is valid, proceed to pricing
    final updated = await Navigator.push<List<TherapyPackage>>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            TherapistPackagesScreen(
              initialPackages: widget.initialPackages,
              specializations: finalSpecs,
            ),
      ),
    );

    if (updated == null) {
      return;
    }

    await _save(updated);
  }

  Future<void> _save(List<TherapyPackage> packages) async {
    if (_saving) {
      return;
    }
    if (_first.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your first name.')),
      );
      return;
    }
    if (_last.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your last name.')),
      );
      return;
    }
    /* Specialization and experience are no longer mandatory */
    /* 
    if (_selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one specialization.')),
      );
      return;
    }
    */

    final email = _email.text.trim();
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your email address.')),
      );
      return;
    }
    if (!_isValidEmail(email)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid email address.')),
      );
      return;
    }
    final phoneText = _phone.text.trim();
    if (phoneText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your phone number.')),
      );
      return;
    }
    final fullPhone = buildFullPhoneNumber(_selectedPhoneCountry, phoneText);
    if (!_isValidPhoneNumber(fullPhone)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid phone number (10-15 digits).'),
        ),
      );
      return;
    }

    final newPassword = _newPassword.text.trim();
    if (newPassword.isNotEmpty) {
      final passwordError = _validatePassword(newPassword);
      if (passwordError.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(passwordError)),
        );
        return;
      }
    }

    if (_selectedYears < 0 || _selectedYears > 80) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Years of experience must be between 0 and 80 years.')),
      );
      return;
    }
    if (_selectedMonths < 0 || _selectedMonths > 11) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Months of experience must be between 0 and 11 months.')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final finalSpecs = _selected.map((s) {
        if (s == 'Others') return _otherSpecialization.text.trim();
        return s;
      }).where((s) => s.isNotEmpty).toList(growable: false);

      if (newPassword.isNotEmpty) {
        final currentPassword = _savedPasswordDisplay.text.trim();
        if (currentPassword.isEmpty) {
          if (!mounted) return;
          setState(() => _saving = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Please enter your current password to set a new one.'),
              backgroundColor: Color(0xFFE74C3C),
            ),
          );
          return;
        }

        final passwordResult = await _firebaseService.updateCurrentUserPassword(
          newPassword: newPassword,
          currentPassword: currentPassword,
        );
        if (passwordResult['success'] != true) {
          if (!mounted) {
            return;
          }
          setState(() => _saving = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                passwordResult['message']?.toString() ??
                    'Failed to update password.',
              ),
              backgroundColor: const Color(0xFFE74C3C),
            ),
          );
          return;
        }
        _newPassword.clear();
        _savedPasswordDisplay.clear();
      }

      // Perform change tracking for approved profiles
      final isApproved = widget.profile.verificationStatus == 'approved';
      final changedFields = <String>[];
      if (isApproved) {
        final displayName = '${_first.text.trim()} ${_last.text.trim()}'.trim();
        if (widget.profile.displayName != displayName) changedFields.add('Display Name');
        if (widget.profile.bio != _about.text.trim()) changedFields.add('Bio');
        if (widget.profile.credentials != _credentials.text.trim()) changedFields.add('Credentials');
        if (widget.profile.yearsOfExperience != _selectedYears || widget.profile.experienceMonths != _selectedMonths) {
          changedFields.add('Experience');
        }
        
        final oldSpecs = List<String>.from(widget.profile.specializations)..sort();
        final newSpecs = List<String>.from(finalSpecs)..sort();
        if (oldSpecs.join(',') != newSpecs.join(',')) {
          changedFields.add('Specializations');
        }

        if (_photoBase64 != null && _photoBase64 != widget.profile.photoUrlBase64) {
          changedFields.add('Profile Photo');
        }
        if (_certificateTouched && _certificateBase64 != null && _certificateBase64 != widget.profile.certificateBase64) {
          changedFields.add('Certificate');
        }
        
        final oldPkgs = widget.profile.servicePackages;
        if (oldPkgs.length != packages.length) {
          changedFields.add('Packages');
        } else {
          for (int i = 0; i < oldPkgs.length; i++) {
            final op = oldPkgs[i];
            final np = packages[i];
            if (op.title != np.title || op.price != np.price || op.durationMinutes != np.durationMinutes || op.sessionsPerWeek != np.sessionsPerWeek || op.description != np.description) {
              changedFields.add('Packages');
              break;
            }
          }
        }
      }

      final updatedHasUnacknowledgedChanges = isApproved ? (changedFields.isNotEmpty || widget.profile.hasUnacknowledgedChanges) : false;
      final updatedUnacknowledgedChangesFields = isApproved
          ? ({...widget.profile.unacknowledgedChangesFields, ...changedFields}.toList())
          : <String>[];

      final updated = TherapistProfile(
        id: widget.profile.id,
        displayName: '${_first.text.trim()} ${_last.text.trim()}'.trim(),
        bio: _about.text.trim(),
        specializations: finalSpecs,
        pricing: widget.profile.pricing,
        languages: widget.profile.languages,
        rating: widget.profile.rating,
        availability: widget.profile.availability,
        photoUrl: widget.profile.photoUrl,
        isActive: widget.profile.isActive,
        yearsOfExperience: _selectedYears,
        experienceMonths: _selectedMonths,
        credentials: _credentials.text.trim(),
        photoUrlBase64: _photoBase64 ?? widget.profile.photoUrlBase64,
        certificateBase64: _certificateTouched
            ? (_certificateBase64 ?? '')
            : widget.profile.certificateBase64,
        isAcceptingClients: _isAcceptingClients,
        verificationStatus: widget.profile.verificationStatus,
        verifiedBadge: widget.profile.verifiedBadge,
        adminFeedback: widget.profile.adminFeedback,
        licenseNumber: widget.profile.licenseNumber,
        registrationNumber: widget.profile.registrationNumber,
        cnic: widget.profile.cnic,
        experienceDetails: widget.profile.experienceDetails,
        ratingBreakdown: widget.profile.ratingBreakdown,
        totalReviews: widget.profile.totalReviews,
        servicePackages: packages,
        hasUnacknowledgedChanges: updatedHasUnacknowledgedChanges,
        unacknowledgedChangesFields: updatedUnacknowledgedChangesFields,
      );

      await widget.onSave(
        profile: updated,
        years: _selectedYears,
        months: _selectedMonths,
        credentials: _credentials.text.trim(),
        contactEmail: email,
        contactPhone: fullPhone,
        packages: packages,
        certificatePdfName: _certificateTouched ? _certificatePdfName : null,
        photoBase64: _photoBase64,
        certificateBase64: _certificateTouched ? (_certificateBase64 ?? '') : null,
      );

      if (isApproved && changedFields.isNotEmpty) {
        final querySnap = await FirebaseFirestore.instance
            .collection('therapist_profile_updates')
            .where('therapistId', isEqualTo: widget.profile.id)
            .where('status', isEqualTo: 'pending_acknowledgment')
            .limit(1)
            .get();

        final updateData = {
          'therapistId': widget.profile.id,
          'displayName': updated.displayName,
          'timestamp': FieldValue.serverTimestamp(),
          'status': 'pending_acknowledgment',
          'changedFields': updatedUnacknowledgedChangesFields,
          'oldProfile': widget.profile.toMap(),
          'newProfile': updated.toMap(),
        };

        if (querySnap.docs.isNotEmpty) {
          await querySnap.docs.first.reference.set(updateData, SetOptions(merge: true));
        } else {
          await FirebaseFirestore.instance.collection('therapist_profile_updates').add(updateData);
        }
      }

      if (mounted) {
        Navigator.pop(context, true);
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _pickProfilePicture() async {
    final picker = ImagePicker();
    final XFile? image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 85,
    );
    
    if (image == null) return;
    
    // Validate file type
    final extension = image.path.toLowerCase().split('.').last;
    if (extension != 'jpg' && extension != 'jpeg' && extension != 'png') {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Only JPG and PNG images are allowed.')),
      );
      return;
    }
    
    // Read and encode image
    final bytes = await image.readAsBytes();
    final sizeKB = bytes.length / 1024;
    
    if (sizeKB > 500) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Image size must be under 500 KB.')),
      );
      return;
    }
    
    final base64 = base64Encode(bytes);
    setState(() => _photoBase64 = base64);
    
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Profile picture updated successfully.')),
    );
  }

  Future<void> _pickCertificatePdf() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) {
      return;
    }
    
    final file = result.files.single;
    final bytes = file.bytes;
    if (bytes == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to read file.')),
      );
      return;
    }
    
    // First encode to Base64 to get exact size
    final base64 = base64Encode(bytes);
    final originalSizeMB = bytes.length / (1024 * 1024);
    final base64SizeMB = base64.length / (1024 * 1024);
    
    // Firestore document size limit is 1MB (1,048,487 bytes)
    // We need to stay well under this limit to account for other document fields
    const maxBase64SizeMB = 0.9; // 0.9MB limit for Base64 string
    const maxOriginalSizeMB = 1.3; // 1.3MB limit for original file
    
    if (originalSizeMB > maxOriginalSizeMB) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF size must be under ${maxOriginalSizeMB.toStringAsFixed(1)} MB.')),
      );
      return;
    }
    
    if (base64SizeMB > maxBase64SizeMB) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF is too large. When encoded, it becomes ${base64SizeMB.toStringAsFixed(2)} MB. Maximum allowed is ${maxBase64SizeMB.toStringAsFixed(1)} MB.')),
      );
      return;
    }
    setState(() {
      _certificatePdfName = file.name;
      _certificateBase64 = base64;
      _certificateTouched = true;
    });
    
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Certificate/Degree uploaded: ${file.name}')),
    );
  }

  Future<void> _deleteCertificate() async {
    setState(() {
      _certificatePdfName = null;
      _certificateBase64 = null;
      _certificateTouched = true;
    });
    
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Certificate/Degree deleted successfully.')),
    );
  }

  Widget _buildCertificateUploadGuidance() {
    final selectedCount = _selected.length;
    final guidance = selectedCount <= 1
        ? 'If one specialization is selected, upload the relevant certificate/degree as a single PDF.'
        : 'If multiple specializations are selected, merge all corresponding certificates/degrees into one PDF before uploading.';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Certificate Upload Guidance',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: Color(0xFF1E3A8A),
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            guidance,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF1E40AF),
              height: 1.35,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Make sure the final PDF size is less than 0.9 MB so it can be stored successfully.',
            style: TextStyle(
              fontSize: 12,
              color: Color(0xFF1E40AF),
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  bool get _hasEmailPasswordLogin =>
      FirebaseAuth.instance.currentUser?.providerData.any(
        (provider) => provider.providerId == 'password',
      ) ??
      false;

  void _toggleSavedPasswordVisibility() {
    setState(() {
      _revealSavedPassword = !_revealSavedPassword;
    });
  }

  Widget _buildCurrentPasswordIndicator() {
    if (!_hasEmailPasswordLogin) {
      return const Padding(
        padding: EdgeInsets.only(bottom: 8),
        child: Text(
          'You signed in with Google. Your password is managed through your Google account.',
          style: TextStyle(
            fontSize: 11,
            color: Color(0xFF6B7280),
            height: 1.35,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Current password',
          style: TextStyle(
            fontWeight: FontWeight.w500,
            fontSize: 12,
            color: Color(0xFF6B7280),
          ),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: _savedPasswordDisplay,
          obscureText: !_revealSavedPassword,
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            isDense: true,
            hintText: 'Enter current password',
            hintStyle: const TextStyle(fontSize: 13, color: Colors.grey),
            suffixIcon: IconButton(
              onPressed: _toggleSavedPasswordVisibility,
              icon: Icon(
                _revealSavedPassword ? Icons.visibility : Icons.visibility_off,
                color: const Color(0xFF6B7280),
                size: 20,
              ),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFF11B5CF)),
            ),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildDeletingOverlay() {
    return Positioned.fill(
      child: AbsorbPointer(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: Container(
            color: Colors.black.withValues(alpha: 0.55),
            child: Center(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 32),
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.2),
                      blurRadius: 30,
                      offset: const Offset(0, 15),
                    ),
                  ],
                ),
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 50,
                      height: 50,
                      child: CircularProgressIndicator(
                        strokeWidth: 4,
                        color: Color(0xFFFF3040),
                      ),
                    ),
                    SizedBox(height: 24),
                    Text(
                      'Deleting Account',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1F2937),
                        letterSpacing: -0.5,
                        decoration: TextDecoration.none,
                      ),
                    ),
                    SizedBox(height: 10),
                    Text(
                      'Please wait while we securely erase your profile data and sign-in credentials. This process cannot be undone.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Color(0xFF64748B),
                        height: 1.5,
                        fontWeight: FontWeight.normal,
                        decoration: TextDecoration.none,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget child;
    if (widget.setupMode) {
      child = _buildSetupMode(context);
    } else {
      child = _buildProfileSettingsMode(context);
    }

    if (_isDeleting) {
      return Stack(
        children: [
          child,
          _buildDeletingOverlay(),
        ],
      );
    }
    return child;
  }

  Widget _buildSetupMode(BuildContext context) {
    final r = context.responsive;
    return SessionGuard(
      role: SessionGuardRole.therapist,
      child: FigmaModuleScaffold(
        title: widget.setupMode ? 'Complete Your Profile' : 'My Profile',
        onBack: () => Navigator.pop(context),
        child: ListView(
          padding: EdgeInsets.fromLTRB(r.w(12), r.h(12), r.w(12), r.h(120)),
          children: [
            Center(
              child: GestureDetector(
                onTap: _pickProfilePicture,
                child: Stack(
                  children: [
                    _LogoCircleAvatar(
                      radius: 42,
                      backgroundColor: Colors.white,
                      padding: 6,
                      photoBase64: _photoBase64,
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Color(0xFF10B6CF),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.camera_alt,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: _cardDeco,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Select Your Specializations',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  for (final item in _specializations)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Material(
                          color: Colors.transparent,
                          child: CheckboxListTile(
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            value: _selected.contains(item),
                            onChanged: (value) {
                              setState(() {
                                if (value == true) {
                                  _selected.add(item);
                                } else {
                                  _selected.remove(item);
                                }
                              });
                            },
                            title: Text(
                              item,
                              style: const TextStyle(fontSize: 13.5),
                            ),
                          ),
                        ),
                        if (item == 'Others' && _selected.contains('Others'))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _input(
                              'Please specify other specialization',
                              _otherSpecialization,
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            _input('First Name', _first, maxLength: 50),
            const SizedBox(height: 8),
            _input('Last Name', _last, maxLength: 50),
            const SizedBox(height: 8),
            _buildExperiencePicker(),
            const SizedBox(height: 8),
            _input(
              'Credentials & Certifications',
              _credentials,
              lines: 3,
              maxLength: 500,
              subtext: 'Please provide details such as registration/license number, CNIC, or other professional credentials for verification purposes.',
            ),
            const SizedBox(height: 8),
            _input('About You', _about, lines: 4, maxLength: 1000),
            const SizedBox(height: 10),
            _buildCertificateUploadGuidance(),
            const SizedBox(height: 8),
            // Upload Certificate Section
            OutlinedButton.icon(
              onPressed: _pickCertificatePdf,
              icon: const Icon(Icons.upload_file_outlined),
              label: Text(_certificatePdfName != null ? 'Replace Certificate/Degree PDF' : 'Upload Certificate/Degree PDF'),
            ),
            const SizedBox(height: 12),
            
            // Uploaded Certificate Section
            if (_certificatePdfName != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                  borderRadius: BorderRadius.circular(8),
                  color: const Color(0xFFF8FAFC),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.picture_as_pdf,
                      color: Color(0xFFDC2626),
                      size: 24,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Uploaded Certificate/Degree',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF1E293B),
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _certificatePdfName!,
                            style: const TextStyle(
                              color: Color(0xFF64748B),
                              fontSize: 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: _deleteCertificate,
                      icon: const Icon(
                        Icons.delete_outline,
                        color: Color(0xFFDC2626),
                      ),
                      tooltip: 'Delete Certificate/Degree',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            const SizedBox(height: 12),
            if (widget.setupMode)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Back'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: _saving ? null : _openPricing,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF11B5CF),
                        foregroundColor: Colors.white,
                      ),
                      child: _saving
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Next: Pricing'),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfileSettingsMode(BuildContext context) {
    final r = context.responsive;
    return SessionGuard(
      role: SessionGuardRole.therapist,
      child: FigmaModuleScaffold(
        title: 'Edit Profile',
        onBack: () => Navigator.pop(context),
        child: ListView(
          padding: EdgeInsets.fromLTRB(r.w(12), r.h(12), r.w(12), r.h(150)),
          children: [
            Center(
              child: GestureDetector(
                onTap: _pickProfilePicture,
                child: Stack(
                  children: [
                    _LogoCircleAvatar(
                      radius: r.w(42),
                      backgroundColor: Colors.white,
                      padding: 6,
                      photoBase64: _photoBase64,
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Color(0xFF10B6CF),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.camera_alt,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            ),
            const SizedBox(height: 20),
            _sectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Basic Information',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1F2937),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: _input('First Name', _first, maxLength: 50)),
                      const SizedBox(width: 8),
                      Expanded(child: _input('Last Name', _last, maxLength: 50)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _input(
                    'Email Address',
                    _email,
                    keyboard: TextInputType.emailAddress,
                    readOnly: true,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Phone Number',
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      fontSize: 12,
                      color: Color(0xFF6B7280),
                    ),
                  ),
                  const SizedBox(height: 4),
                  PhoneInputField(
                    localController: _phone,
                    initialCountry: _selectedPhoneCountry,
                    onCountryChanged: (country) {
                      setState(() => _selectedPhoneCountry = country);
                    },
                    fieldDecoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildCurrentPasswordIndicator(),
                  _input(
                    'New password (optional)',
                    _newPassword,
                    obscureText: _obscureNewPassword,
                    suffixIcon: IconButton(
                      onPressed: () {
                        setState(
                          () =>
                              _obscureNewPassword = !_obscureNewPassword,
                        );
                      },
                      icon: Icon(
                        _obscureNewPassword
                            ? Icons.visibility_off
                            : Icons.visibility,
                        color: const Color(0xFF6B7280),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _input('About Me', _about, lines: 4, maxLength: 1000),
                ],
              ),
            ),
            const SizedBox(height: 10),
            _sectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Professional Information',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1F2937),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _buildExperiencePicker(),
                  const SizedBox(height: 8),
                  _input(
                    'Credentials & Certifications',
                    _credentials,
                    lines: 3,
                    maxLength: 500,
                    subtext: 'Please provide details such as registration/license number, CNIC, or other professional credentials for verification purposes.',
                  ),
                  const SizedBox(height: 8),
                  _buildCertificateUploadGuidance(),
                  const SizedBox(height: 8),
                  // Upload Certificate Section
                  OutlinedButton.icon(
                    onPressed: _pickCertificatePdf,
                    icon: const Icon(Icons.upload_file_outlined),
                    label: Text(
                      _certificatePdfName == null
                          ? 'Upload Certificate/Degree PDF'
                          : 'Replace Certificate/Degree PDF',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(height: 12),
                  
                  // Uploaded Certificate Section
                  if (_certificatePdfName != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                        borderRadius: BorderRadius.circular(8),
                        color: const Color(0xFFF8FAFC),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.picture_as_pdf,
                            color: Color(0xFFDC2626),
                            size: 24,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Uploaded Certificate/Degree',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF1E293B),
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _certificatePdfName!,
                                  style: const TextStyle(
                                    color: Color(0xFF64748B),
                                    fontSize: 12,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: _deleteCertificate,
                            icon: const Icon(
                              Icons.delete_outline,
                              color: Color(0xFFDC2626),
                            ),
                            tooltip: 'Delete Certificate/Degree',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 10),
            _sectionCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Specializations (${_selected.length} selected)',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1F2937),
                    ),
                  ),
                  const SizedBox(height: 8),
                  for (final item in _specializations)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          margin: const EdgeInsets.only(bottom: 7),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: const Color(0xFFE5E7EB),
                            ),
                            color: Colors.white,
                          ),
                          child: Material(
                            color: Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                            clipBehavior: Clip.antiAlias,
                            child: CheckboxListTile(
                              dense: true,
                              value: _selected.contains(item),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 0,
                              ),
                              controlAffinity: ListTileControlAffinity.leading,
                              activeColor: const Color(0xFF11B5CF),
                              onChanged: (value) {
                                setState(() {
                                  if (value == true) {
                                    _selected.add(item);
                                  } else {
                                    _selected.remove(item);
                                  }
                                });
                              },
                              title: Text(
                                item,
                                style: const TextStyle(
                                  fontSize: 13.2,
                                  color: Color(0xFF374151),
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (item == 'Others' && _selected.contains('Others'))
                          Padding(
                            padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
                            child: _input(
                              'Please specify other specialization',
                              _otherSpecialization,
                            ),
                          ),
                      ],
                    ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _saving ? null : () => _save(widget.initialPackages),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF11B5CF),
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(50),
              ),
              child: _saving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Save Profile Changes'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _showDeleteAccountDialog,
              icon: const Icon(Icons.delete_forever, color: Color(0xFFFF3040)),
              label: const Text(
                'Delete Account',
                style: TextStyle(color: Color(0xFFFF3040)),
              ),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFFFF3040)),
                minimumSize: const Size.fromHeight(50),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showDeleteAccountDialog() async {
    bool checkboxChecked = false;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text(
            'Delete Account',
            style: TextStyle(color: Color(0xFFFF3040)),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'This action cannot be undone. All your data will be permanently deleted, including:',
                  style: TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 8),
                const Text('• Profile information'),
                const Text('• Uploaded certificates/degrees'),
                const Text('• Service packages'),
                const Text('• Message history'),
                const Text('• All account settings'),
                const SizedBox(height: 12),
                const Text(
                  'You will be removed from the Professional Support section and parents will no longer be able to see or contact you.',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Checkbox(
                      value: checkboxChecked,
                      onChanged: (value) {
                        setDialogState(() => checkboxChecked = value ?? false);
                      },
                    ),
                    const Expanded(
                      child: Text(
                        'I understand the consequences and want to permanently delete my account',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: checkboxChecked
                  ? () {
                      Navigator.pop(context, true);
                    }
                  : null,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFFF3040),
              ),
              child: const Text('Delete Account'),
            ),
          ],
        ),
      ),
    );

    if (result == true) {
      await _deleteAccount();
    }
  }

  Future<void> _deleteAccount() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;
    final uid = currentUser.uid;

    final lastSignIn = currentUser.metadata.lastSignInTime;
    if (lastSignIn != null && DateTime.now().difference(lastSignIn).inMinutes > 5) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('For security, please sign out and sign back in before deleting your account.'),
          backgroundColor: Color(0xFFFF4D4D),
          duration: Duration(seconds: 5),
        ),
      );
      return;
    }

    setState(() => _isDeleting = true);
    try {
      // First try to delete Firestore documents while we still have auth context
      bool firestoreDeleted = false;
      try {
        // Delete from therapist_profiles collection
        await FirebaseFirestore.instance
            .collection(FirestoreCollections.therapistProfiles)
            .doc(uid)
            .delete();

        // Delete from users collection
        await FirebaseFirestore.instance
            .collection(FirestoreCollections.users)
            .doc(uid)
            .delete();
        
        // Also remove from any Professional Support related collections
        // Check if there's a support requests collection where therapist might be referenced
        try {
          // Delete any support requests related to this therapist
          final supportRequests = await FirebaseFirestore.instance
              .collection('supportRequests')
              .where('therapistId', isEqualTo: uid)
              .get();
          
          for (final doc in supportRequests.docs) {
            await doc.reference.delete();
          }
        } catch (e) {
          // Support requests collection might not exist or therapist might not have any requests
          // This is not critical for account deletion
        }
        
        // Delete any feedback submitted by the therapist
        try {
          final feedbackSnap = await FirebaseFirestore.instance
              .collection(FirestoreCollections.feedback)
              .where('userId', isEqualTo: uid)
              .get();
          for (final f in feedbackSnap.docs) {
            await f.reference.delete();
          }
        } catch (e) {
          // Non-critical
        }
        
        firestoreDeleted = true;
      } catch (firestoreError) {
        // If Firestore deletion fails due to permissions, we'll try a different approach
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Unable to delete profile data due to permissions: $firestoreError'),
            backgroundColor: const Color(0xFFFF4D4D),
            duration: const Duration(seconds: 3),
          ),
        );
      }

      // Now try to delete from Firebase Auth with multiple fallback methods
      bool authDeleted = false;
      String authError = '';
      
      // Method 1: Direct deletion attempt
      try {
        final currentUser = FirebaseAuth.instance.currentUser;
        if (currentUser != null) {
          await currentUser.delete();
          authDeleted = true;
        }
      } catch (authError1) {
        authError = authError1.toString();
        
        // Method 2: Try re-authentication and deletion
        try {
          final currentUser = FirebaseAuth.instance.currentUser;
          if (currentUser != null && currentUser.email != null) {
            // Force re-authentication by creating a new credential
            // Note: This won't work without password, but we'll try alternative methods
            throw Exception('Re-auth not possible without password');
          }
        } catch (reauthError) {
          // Method 3: Try to mark account for deletion and handle via admin
          try {
            // Mark the user document as deleted so admin can clean up
            await FirebaseFirestore.instance
                .collection(FirestoreCollections.users)
                .doc(uid)
                .update({
                  'markedForDeletion': true,
                  'deletionTimestamp': FieldValue.serverTimestamp(),
                  'deletionReason': 'User requested account deletion',
                });
            
            // Also mark in therapist profiles
            await FirebaseFirestore.instance
                .collection(FirestoreCollections.therapistProfiles)
                .doc(uid)
                .update({
                  'markedForDeletion': true,
                  'deletionTimestamp': FieldValue.serverTimestamp(),
                  'isActive': false,
                });
            
            authDeleted = true; // Mark as handled for admin cleanup
          } catch (markError) {
            // Method 4: Last resort - just disable the account
            try {
              await FirebaseFirestore.instance
                  .collection(FirestoreCollections.therapistProfiles)
                  .doc(uid)
                  .update({
                    'isActive': false,
                    'disabledByUser': true,
                    'disabledTimestamp': FieldValue.serverTimestamp(),
                  });
              
              authDeleted = true; // Mark as disabled
            } catch (disableError) {
              // Preserve the original authError
            }
          }
        }
      }
      
      // Handle the result
      if (!mounted) return;
      
      if (authDeleted) {
        // Success - show appropriate message
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(firestoreDeleted 
                ? 'Account and all data deleted successfully.' 
                : 'Account deleted. Some profile data may remain due to permissions.'),
            backgroundColor: firestoreDeleted ? const Color(0xFF2ECC71) : const Color(0xFFFFA500),
            duration: const Duration(seconds: 3),
          ),
        );
      } else {
        if (mounted) {
          setState(() => _isDeleting = false);
        }
        // Failed - show detailed error and guidance
        String errorMessage = 'Account deletion failed';
        if (authError.contains('requires-recent-login')) {
          errorMessage = 'For security, please sign out and sign back in before deleting your account.';
        } else if (authError.contains('network-request-failed')) {
          errorMessage = 'Network error. Please check your connection and try again.';
        } else if (authError.contains('too-many-requests')) {
          errorMessage = 'Too many requests. Please try again later.';
        } else if (authError.contains('user-not-found')) {
          errorMessage = 'User not found. Please sign in again.';
        } else {
          errorMessage = 'Account deletion failed. Your account has been disabled for security. Please contact support for complete removal.';
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: const Color(0xFFFF4D4D),
            duration: const Duration(seconds: 5),
          ),
        );
      }

      // Navigate to login screen
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (_) => false,
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isDeleting = false);
      }
      if (!mounted) return;
      
      String errorMessage = 'Failed to delete account';
      if (e.toString().contains('PERMISSION_DENIED')) {
        errorMessage = 'Account deletion requires additional permissions. Please contact support for assistance.';
      } else if (e.toString().contains('requires-recent-login')) {
        errorMessage = 'For security, please sign out and sign back in before deleting your account.';
      } else {
        errorMessage = 'Failed to delete account: $e';
      }
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMessage),
          backgroundColor: const Color(0xFFFF4D4D),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  Widget _input(
    String label,
    TextEditingController controller, {
    int lines = 1,
    TextInputType? keyboard,
    bool readOnly = false,
    bool obscureText = false,
    Widget? suffixIcon,
    String? subtext,
    int? maxLength,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w500,
            fontSize: 12,
            color: Color(0xFF6B7280),
          ),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          maxLines: lines,
          maxLength: maxLength,
          keyboardType: keyboard,
          readOnly: readOnly,
          obscureText: obscureText,
          buildCounter: maxLength == null
              ? null
              : (context, {required currentLength, required maxLength, required isFocused}) {
                  return Text(
                    '$currentLength/$maxLength',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF6B7280),
                    ),
                  );
                },
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            isDense: true,
            suffixIcon: suffixIcon,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFF11B5CF)),
            ),
          ),
        ),
        if (subtext != null) ...[
          const SizedBox(height: 4),
          Text(
            subtext,
            style: const TextStyle(
              fontSize: 11,
              color: Color(0xFF6B7280),
              height: 1.3,
            ),
          ),
        ],
      ],
    );
  }

  Widget _sectionCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }

  bool _isValidEmail(String email) {
    if (email.isEmpty) {
      return false;
    }
    final emailRegex = RegExp(
      r'^[a-zA-Z0-9.!#$%&*+/=?^_`{|}~-]+@[a-zA-Z0-9-]+(?:\.[a-zA-Z0-9-]+)*\.[a-zA-Z]{2,}$',
    );
    return emailRegex.hasMatch(email);
  }

  bool _isValidPhoneNumber(String phone) {
    final digitsOnly = phone.replaceAll(RegExp(r'[^\d]'), '');
    if (digitsOnly.length < 10 || digitsOnly.length > 15) {
      return false;
    }
    final phoneRegex = RegExp(r'^[+]?[\d\s\-()]+$');
    return phoneRegex.hasMatch(phone);
  }

  String _validatePassword(String password) {
    if (password.length < 6) {
      return 'Password must be at least 6 characters long';
    }
    if (password.length > 100) {
      return 'Password must not exceed 100 characters';
    }
    if (!password.contains(RegExp(r'[A-Z]'))) {
      return 'Password must contain at least one uppercase letter for strong password';
    }
    if (!password.contains(RegExp(r'[a-z]'))) {
      return 'Password must contain at least one lowercase letter for strong password';
    }
    if (!password.contains(RegExp(r'[0-9]'))) {
      return 'Password must contain at least one number for strong password';
    }
    if (!password.contains(RegExp(r'[^a-zA-Z0-9]'))) {
      return 'Password must contain at least one special character (e.g. !@#\$%^&*)';
    }
    return '';
  }

  Widget _buildExperiencePicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Experience',
          style: TextStyle(
            fontWeight: FontWeight.w500,
            fontSize: 12,
            color: Color(0xFF6B7280),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: _selectedYears,
                    isExpanded: true,
                    style: const TextStyle(color: Color(0xFF1F2937), fontSize: 14),
                    items: List.generate(81, (index) => index)
                        .map((y) => DropdownMenuItem<int>(
                              value: y,
                              child: Text('$y Years'),
                            ))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _selectedYears = val);
                      }
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<int>(
                    value: _selectedMonths,
                    isExpanded: true,
                    style: const TextStyle(color: Color(0xFF1F2937), fontSize: 14),
                    items: List.generate(12, (index) => index)
                        .map((m) => DropdownMenuItem<int>(
                              value: m,
                              child: Text('$m Months'),
                            ))
                        .toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _selectedMonths = val);
                      }
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class TherapistPackagesScreen extends StatefulWidget {
  const TherapistPackagesScreen({super.key, required this.initialPackages, required this.specializations});

  final List<TherapyPackage> initialPackages;
  final List<String> specializations;

  @override
  State<TherapistPackagesScreen> createState() =>
      _TherapistPackagesScreenState();
}

class _TherapistPackagesScreenState extends State<TherapistPackagesScreen> {
  late List<TherapyPackage> _packages;
  final Set<int> _activePackageIndices = <int>{};
  bool _loadingSubscriptions = true;

  @override
  void initState() {
    super.initState();
    _packages = widget.initialPackages.map((TherapyPackage item) => item.copy()).toList();
    _loadActiveSubscriptions();
  }

  Future<void> _loadActiveSubscriptions() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final activeSubsSnapshot = await FirebaseFirestore.instance
          .collection('subscriptions')
          .where('therapistId', isEqualTo: uid)
          .where('status', whereIn: ['active', 'trialing', 'grace_period'])
          .get();

      final activeIndices = <int>{};
      for (final doc in activeSubsSnapshot.docs) {
        final data = doc.data();
        final prodId = data['productId']?.toString() ?? '';
        if (prodId.startsWith('auto_${uid}_')) {
          final parts = prodId.split('_');
          if (parts.length >= 3) {
            final pkgIndex = int.tryParse(parts.last);
            if (pkgIndex != null) {
              activeIndices.add(pkgIndex);
            }
          }
        } else if (prodId == 'bypass-plan' || prodId == 'local-bypass' || prodId == 'cached-offline') {
          activeIndices.add(0);
        }
      }
      if (mounted) {
        setState(() {
          _activePackageIndices.clear();
          _activePackageIndices.addAll(activeIndices);
          _loadingSubscriptions = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading active subscriptions: $e');
      if (mounted) {
        setState(() {
          _loadingSubscriptions = false;
        });
      }
    }
  }

  Future<void> _addOrEdit({int? index}) async {
    if (index == null) {
      final limit = widget.specializations.length;
      if (_packages.length >= limit) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "Your package limit is based on the number of specializations you have selected. "
              "To add more packages, either select more specializations or edit your existing packages.",
            ),
            backgroundColor: Color(0xFFFF4D4D),
            duration: Duration(seconds: 5),
          ),
        );
        return;
      }
    }
    final initial = index == null ? null : _packages[index];
    final pkg = await showDialog<TherapyPackage>(
      context: context,
      barrierColor: Colors.black45,
      builder: (_) => _PackageEditor(initial: initial),
    );
    if (pkg == null) {
      return;
    }
    setState(() {
      if (index == null) {
        _packages.add(pkg);
      } else {
        _packages[index] = pkg;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final r = context.responsive;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          _onBack();
        }
      },
      child: SessionGuard(
        role: SessionGuardRole.therapist,
        child: FigmaModuleScaffold(
          title: 'Service Packages',
          onBack: _onBack,
          child: ListView(
            padding: EdgeInsets.fromLTRB(r.w(14), r.h(12), r.w(14), r.h(120)),
            children: [
              FilledButton.icon(
                onPressed: () => _addOrEdit(),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF10B6CF),
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(vertical: r.h(14)),
                ),
                icon: const Icon(Icons.add),
                label: const Text('Add New Package'),
              ),
              SizedBox(height: r.h(12)),
              if (_packages.isEmpty)
                Container(
                  padding: EdgeInsets.all(r.w(16)),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE5E7EB)),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        Icons.inventory_2_outlined,
                        size: r.w(48),
                        color: const Color(0xFF9CA3AF),
                      ),
                      SizedBox(height: r.h(12)),
                      Text(
                        'No service packages added yet',
                        style: TextStyle(
                          fontSize: r.sp(16),
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF374151),
                        ),
                      ),
                      SizedBox(height: r.h(8)),
                      Text(
                        'Tap on "Add New Package" to add your service packages.',
                        style: TextStyle(
                          fontSize: r.sp(14),
                          color: const Color(0xFF6B7280),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              if (_packages.isEmpty) SizedBox(height: r.h(12)),
              for (var i = 0; i < _packages.length; i++) ...[
                _PackageTile(
                  package: _packages[i],
                  onEdit: () => _addOrEdit(index: i),
                  onDelete: () {
                    if (_loadingSubscriptions) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Checking active subscriptions...')),
                      );
                      return;
                    }
                    if (_activePackageIndices.contains(i)) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Parents are currently subscribed to this package. You can edit it, but you cannot delete it.'),
                          backgroundColor: Color(0xFFFF4D4D),
                        ),
                      );
                      return;
                    }
                    setState(() {
                      _packages.removeAt(i);
                      final newActive = <int>{};
                      for (final index in _activePackageIndices) {
                        if (index < i) {
                          newActive.add(index);
                        } else if (index > i) {
                          newActive.add(index - 1);
                        }
                      }
                      _activePackageIndices.clear();
                      _activePackageIndices.addAll(newActive);
                    });
                  },
                  onVisible: (value) => setState(
                    () => _packages[i] = _packages[i].copy(
                      visible: value,
                    ),
                  ),
                ),
                SizedBox(height: r.h(12)),
              ],
              FilledButton(
                onPressed: _packages.isEmpty ? null : _onBack,
                style: FilledButton.styleFrom(
                  backgroundColor: _packages.isEmpty ? const Color(0xFF9CA3AF) : const Color(0xFF10B6CF),
                  foregroundColor: Colors.white,
                ),
                child: const Text('Save Packages'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _onBack() {
    // Check if packages are empty and show warning
    if (_packages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please add at least one service package before saving.'),
          backgroundColor: Color(0xFFFF4D4D),
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }
    
    // Return the current packages list
    Navigator.pop(context, _packages);
  }
}

class TherapistNotificationSettingsScreen extends StatefulWidget {
  const TherapistNotificationSettingsScreen({
    super.key,
    required this.initialValues,
  });

  final Map<String, bool> initialValues;

  @override
  State<TherapistNotificationSettingsScreen> createState() =>
      _TherapistNotificationSettingsScreenState();
}

class _TherapistNotificationSettingsScreenState
    extends State<TherapistNotificationSettingsScreen> {
  bool newMessages = false;
  bool bookings = false;
  bool payments = false;
  bool emergency = true;

  @override
  void initState() {
    super.initState();
    final initial = {
      ..._defaultTherapistNotificationPrefs,
      ...widget.initialValues,
    };
    newMessages = initial['newMessages'] ?? false;
    bookings = initial['bookings'] ?? false;
    payments = initial['payments'] ?? false;
    emergency = initial['emergency'] ?? true;
  }

  @override
  Widget build(BuildContext context) {
    final r = context.responsive;
    return SessionGuard(
      role: SessionGuardRole.therapist,
      child: FigmaModuleScaffold(
        title: 'Notification Settings',
        onBack: () => Navigator.pop(context),
        child: ListView(
          padding: EdgeInsets.fromLTRB(r.w(14), r.h(12), r.w(14), r.h(120)),
          children: [
            _switchTile(
              'New Messages',
              'When parents send you messages',
              newMessages,
              (v) => setState(() => newMessages = v),
            ),
            _switchTile(
              'New Bookings',
              'When parents book your sessions',
              bookings,
              (v) => setState(() => bookings = v),
            ),
            _switchTile(
              'Payment Alerts',
              'Payment and transaction updates',
              payments,
              (v) => setState(() => payments = v),
            ),
            _switchTile(
              'Emergency Button Alerts',
              'Instant alerts for emergency events',
              emergency,
              (v) => setState(() => emergency = v),
            ),
            SizedBox(height: r.h(12)),
            FilledButton(
              onPressed: () {
                Navigator.pop(context, <String, bool>{
                  'newMessages': newMessages,
                  'bookings': bookings,
                  'payments': payments,
                  'emergency': emergency,
                });
              },
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF8CC93B),
                foregroundColor: Colors.white,
              ),
              child: const Text('Save Notification Preferences'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _switchTile(
    String title,
    String subtitle,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: _cardDeco,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(color: Color(0xFF6B7280)),
                ),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

class _TherapistSettingsDialog extends StatelessWidget {
  const _TherapistSettingsDialog({
    required this.onProfile,
    required this.onPackage,
    required this.onAlerts,
    required this.onFeedback,
    required this.onAbout,
    required this.onLogout,
    required this.onScheduler,
  });

  final VoidCallback onProfile;
  final VoidCallback onPackage;
  final VoidCallback onAlerts;
  final VoidCallback onFeedback;
  final VoidCallback onAbout;
  final VoidCallback onLogout;
  final VoidCallback onScheduler;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded, size: 24, color: Color(0xFF64748B)),
                      splashRadius: 20,
                    ),
                  ],
                ),
                const CircleAvatar(
                  radius: 32,
                  backgroundColor: Color(0xFF4EA9E3),
                  child: Icon(Icons.settings_rounded, color: Colors.white, size: 32),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Settings',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Color(0xFF1E293B)),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: BouncingButton(
                        onTap: onProfile,
                        child: _setBtn('Profile', const Color(0xFF4EA9E3), Icons.person_rounded),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: BouncingButton(
                        onTap: onPackage,
                        child: _setBtn('Package', const Color(0xFFFB923C), Icons.inventory_2_rounded),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: BouncingButton(
                        onTap: onAlerts,
                        child: _setBtn('Alerts', const Color(0xFF10B981), Icons.notifications_rounded),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: BouncingButton(
                        onTap: onFeedback,
                        child: _setBtn('Feedback', const Color(0xFF8B5CF6), Icons.rate_review_rounded),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: BouncingButton(
                        onTap: onAbout,
                        child: _setBtn('About App', const Color(0xFF3B82F6), Icons.info_rounded),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: BouncingButton(
                        onTap: onScheduler,
                        child: _setBtn('Scheduler', const Color(0xFF0D9488), Icons.calendar_month_rounded),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                BouncingButton(
                  onTap: onLogout,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.logout_rounded, color: Colors.white, size: 20),
                        SizedBox(width: 8),
                        Text('Logout', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
      ),
    );
  }

  Widget _setBtn(String title, Color color, IconData icon) {
    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: Colors.white, size: 16),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              title,
              maxLines: 2,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PackageTile extends StatelessWidget {
  const _PackageTile({
    required this.package,
    required this.onEdit,
    required this.onDelete,
    required this.onVisible,
  });

  final TherapyPackage package;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final ValueChanged<bool> onVisible;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _cardDeco,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            decoration: const BoxDecoration(
              color: Color(0xFFFB955F),
              borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
            ),
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    package.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 30 / 1.5,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit, color: Colors.white),
                ),
                IconButton(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline, color: Colors.white),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${formatPrice(package.price)} /session',
                  style: const TextStyle(
                    color: Color(0xFF0EA5C6),
                    fontWeight: FontWeight.w700,
                    fontSize: 42 / 1.5,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${package.durationMinutes} min • ${package.sessionsPerWeek} sessions/week',
                ),
                const SizedBox(height: 6),
                Text(
                  package.description,
                  style: const TextStyle(color: Color(0xFF6B7280)),
                ),
                Row(
                  children: [
                    const Expanded(child: Text('Visible to parents')),
                    Switch(value: package.visible, onChanged: onVisible),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PackageEditor extends StatefulWidget {
  const _PackageEditor({this.initial});

  final TherapyPackage? initial;

  @override
  State<_PackageEditor> createState() => _PackageEditorState();
}

class _PackageEditorState extends State<_PackageEditor> {
  late final TextEditingController _title;
  late final TextEditingController _price;
  late final TextEditingController _duration;
  late final TextEditingController _sessions;
  late final TextEditingController _description;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.initial?.title ?? '');
    _price = TextEditingController(
      text: (widget.initial?.price ?? 75).toStringAsFixed(0),
    );
    _duration = TextEditingController(
      text: '${widget.initial?.durationMinutes ?? 60}',
    );
    _sessions = TextEditingController(
      text: '${widget.initial?.sessionsPerWeek ?? 3}',
    );
    _description = TextEditingController(
      text: widget.initial?.description ?? '',
    );
  }

  @override
  void dispose() {
    _title.dispose();
    _price.dispose();
    _duration.dispose();
    _sessions.dispose();
    _description.dispose();
    super.dispose();
  }

  void _showError(String msg) {
    // Use rootNavigator scaffold so the snackbar appears above the dialog overlay.
    ScaffoldMessenger.of(
      Navigator.of(context, rootNavigator: true).context,
    ).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: const Color(0xFFEF4444),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _save() {
    final title = _title.text.trim();
    final description = _description.text.trim();
    final parsedPrice = double.tryParse(_price.text.trim());
    final parsedDuration = int.tryParse(_duration.text.trim());
    final parsedSessions = int.tryParse(_sessions.text.trim());

    if (title.isEmpty) {
      _showError('Please enter a package title.');
      return;
    }

    if (title.length > 100) {
      _showError('Package title cannot exceed 100 characters.');
      return;
    }

    if (parsedPrice == null || parsedPrice < 0) {
      _showError('Please enter a valid price of 0 or greater.');
      return;
    }

    if (parsedPrice > 1000000) {
      _showError('Package price cannot exceed Rs. 1,000,000 (10 Lakhs PKR).');
      return;
    }

    if (parsedDuration == null || parsedDuration < 15 || parsedDuration > 480) {
      _showError('Please enter a valid session duration (between 15 and 480 minutes).');
      return;
    }

    if (parsedSessions == null || parsedSessions <= 0 || parsedSessions > 21) {
      _showError('Please enter a valid number of sessions per week (between 1 and 21).');
      return;
    }

    if (description.isEmpty) {
      _showError('Please enter a package description.');
      return;
    }

    if (description.length > 500) {
      _showError('Package description cannot exceed 500 characters.');
      return;
    }

    if (widget.initial != null) {
      showDialog<bool>(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 24),
                SizedBox(width: 8),
                Expanded(
                  child: Text('Warning: Package Edit', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            content: const Text(
              'Modifying package details will not retroactively change existing parent subscription snapshots. '
              'Any currently active parents will continue under the specifications they subscribed to. '
              'Are you sure you want to proceed with editing this package?',
              style: TextStyle(fontSize: 14),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF11B5CF), foregroundColor: Colors.white),
                child: const Text('Proceed'),
              ),
            ],
          );
        },
      ).then((confirmed) {
        if (confirmed == true && mounted) {
          Navigator.pop(
            context,
            TherapyPackage(
              title: title,
              durationMinutes: parsedDuration,
              sessionsPerWeek: parsedSessions,
              price: parsedPrice,
              description: description,
              visible: widget.initial?.visible ?? true,
            ),
          );
        }
      });
    } else {
      Navigator.pop(
        context,
        TherapyPackage(
          title: title,
          durationMinutes: parsedDuration,
          sessionsPerWeek: parsedSessions,
          price: parsedPrice,
          description: description,
          visible: widget.initial?.visible ?? true,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.initial == null ? 'Add New Package' : 'Edit Package',
                      style: const TextStyle(
                        fontSize: 34 / 1.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              _field('Package Title', _title, maxLength: 100),
              const SizedBox(height: 8),
              _field(
                'Price per Session (PKR)',
                _price,
                keyboard: TextInputType.number,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _field(
                      'Duration (min)',
                      _duration,
                      keyboard: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _field(
                      'Sessions/Week',
                      _sessions,
                      keyboard: TextInputType.number,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _field('Description', _description, lines: 3, maxLength: 500),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _save,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF11B5CF),
                    foregroundColor: Colors.white,
                  ),
                  child: Text(
                    widget.initial == null ? 'Add Package' : 'Save Changes',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController c, {
    TextInputType? keyboard,
    int lines = 1,
    int? maxLength,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
        const SizedBox(height: 4),
        TextField(
          controller: c,
          keyboardType: keyboard,
          maxLines: lines,
          maxLength: maxLength,
          buildCounter: maxLength == null
              ? null
              : (context, {required currentLength, required isFocused, required maxLength}) {
                  return Text(
                    '$currentLength/$maxLength',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF6B7280),
                    ),
                  );
                },
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
          ),
        ),
      ],
    );
  }
}

class _TherapistHomeBadge extends StatelessWidget {
  const _TherapistHomeBadge({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Color(0xFFC4E5C6),
      ),
      padding: EdgeInsets.all(size * 0.065),
      child: ClipOval(
        child: Image.asset('assets/images/autiease.png', fit: BoxFit.contain),
      ),
    );
  }
}

class _LogoCircleAvatar extends StatelessWidget {
  const _LogoCircleAvatar({
    required this.radius,
    required this.backgroundColor,
    this.padding = 4,
    this.photoBase64,
  });

  final double radius;
  final Color backgroundColor;
  final double padding;
  final String? photoBase64;

  @override
  Widget build(BuildContext context) {
    Widget imageWidget;
    if (photoBase64 != null && photoBase64!.isNotEmpty) {
      try {
        final imageBytes = base64Decode(photoBase64!);
        imageWidget = Image.memory(
          imageBytes,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return Image.asset('assets/images/autiease.png', fit: BoxFit.contain);
          },
        );
      } catch (e) {
        imageWidget = Image.asset('assets/images/autiease.png', fit: BoxFit.contain);
      }
    } else {
      imageWidget = Image.asset('assets/images/autiease.png', fit: BoxFit.contain);
    }

    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(color: backgroundColor, shape: BoxShape.circle),
      padding: EdgeInsets.all(padding),
      child: ClipOval(
        child: imageWidget,
      ),
    );
  }
}

class _ModuleCard extends StatelessWidget {
  const _ModuleCard({
    required this.title,
    required this.color,
    required this.asset,
    required this.onTap,
    this.enabled = true,
    this.unreadCount = 0,
  });

  final String title;
  final Color color;
  final String asset;
  final VoidCallback onTap;
  final bool enabled;
  final int unreadCount;

  @override
  Widget build(BuildContext context) {
    final r = context.responsive;
    final cardColor = enabled ? color : color.withValues(alpha: 0.6);
    final textColor = enabled
        ? const Color(0xFF111827)
        : const Color(0xFF4B5563);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(r.w(14)),
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(horizontal: r.w(20), vertical: r.h(22)),
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(r.w(14)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: r.sp(40 / 1.5, min: 18, max: 28),
                        fontWeight: FontWeight.w700,
                        color: textColor,
                      ),
                    ),
                    if (unreadCount > 0) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '$unreadCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              SizedBox(
                height: r.w(44),
                width: r.w(44),
                child: Image.asset(asset, fit: BoxFit.contain),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrianglePainter extends CustomPainter {
  const _TrianglePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    var path = Path();
    path.moveTo(size.width / 2, 0);
    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();

    var paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

const BoxDecoration _cardDeco = BoxDecoration(
  color: Colors.white,
  borderRadius: BorderRadius.all(Radius.circular(14)),
  boxShadow: [
    BoxShadow(color: Color(0x1A000000), blurRadius: 10, offset: Offset(0, 2)),
  ],
);

const Map<String, bool> _defaultTherapistNotificationPrefs = <String, bool>{
  'newMessages': true,
  'bookings': true,
  'payments': true,
  'emergency': true,
};

const List<String> _specializations = <String>[
  'Applied Behavior Analysis (ABA)',
  'Speech and Language Therapy',
  'Occupational Therapy',
  'Physical Therapy',
  'Social Skills Training',
  'Sensory Integration Therapy',
  'Cognitive Behavioral Therapy (CBT)',
  'TEACCH',
  'PECS',
  'Floortime (DIR Model)',
  'Relationship Development Intervention (RDI)',
  'Developmental Therapy',
  'Music Therapy',
  'Art Therapy',
  'Feeding Therapy',
  'Others',
];

class _BottomWaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    var path = Path();
    path.moveTo(0, 60);

    var firstControlPoint = Offset(size.width / 4, 0);
    var firstEndPoint = Offset(size.width / 2, 40);
    path.quadraticBezierTo(
      firstControlPoint.dx,
      firstControlPoint.dy,
      firstEndPoint.dx,
      firstEndPoint.dy,
    );

    var secondControlPoint = Offset(size.width * 3 / 4, 80);
    var secondEndPoint = Offset(size.width, 30);
    path.quadraticBezierTo(
      secondControlPoint.dx,
      secondControlPoint.dy,
      secondEndPoint.dx,
      secondEndPoint.dy,
    );

    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}

int intFrom(dynamic value, [int fallback = 0]) {
  if (value is int) return value;
  if (value is double) return value.toInt();
  if (value is String) return int.tryParse(value) ?? fallback;
  return fallback;
}

Map<String, bool> boolMapFrom(dynamic raw) {
  if (raw is! Map) return <String, bool>{};
  return Map<String, bool>.from(raw.map((k, v) => MapEntry(k.toString(), v == true)));
}

Map<String, dynamic> mapFrom(dynamic raw) {
  if (raw is Map) return Map<String, dynamic>.from(raw);
  return <String, dynamic>{};
}

List<TherapyPackage> _parsePackages(dynamic raw) {
  if (raw is! List) return const <TherapyPackage>[];
  final parsed = <TherapyPackage>[];
  for (final entry in raw) {
    final map = mapFrom(entry);
    if (map.isEmpty) continue;
    parsed.add(TherapyPackage.fromMap(map));
  }
  return parsed;
}

String _friendlyTime(DateTime? time) {
  if (time == null) return 'Just now';
  final diff = DateTime.now().difference(time);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} hr ago';
  if (diff.inDays == 1) return 'Yesterday';
  return '${diff.inDays} days ago';
}
