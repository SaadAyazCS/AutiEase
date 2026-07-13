import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/app_models.dart';
import '../repositories/app_repositories.dart';
import '../utils/app_colors.dart';
import '../widgets/session_guard.dart';
import 'therapist_chat_screen.dart';
import 'certificate_viewer_screen.dart';
import 'parent_clinical_logs_screen.dart';
import 'parent_scheduler_screen.dart';
import '../utils/currency_utils.dart';


class _TherapistPlaceholderAvatar extends StatelessWidget {
  const _TherapistPlaceholderAvatar({
    required this.size,
    this.backgroundColor = const Color(0xFFDDF7E5),
    this.padding = 4,
    this.photoBase64,
    this.isOnline = false,
  });

  final double size;
  final Color backgroundColor;
  final double padding;
  final String? photoBase64;
  final bool isOnline;

  @override
  Widget build(BuildContext context) {
    Widget imageWidget;
    if (photoBase64 != null && photoBase64!.isNotEmpty) {
      if (photoBase64!.startsWith('http://') || photoBase64!.startsWith('https://')) {
        imageWidget = Image.network(
          photoBase64!,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return Image.asset('assets/images/autiease.png', fit: BoxFit.contain);
          },
        );
      } else {
        try {
          final imageBytes = base64Decode(photoBase64!.trim());
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
      }
    } else {
      imageWidget = Image.asset('assets/images/autiease.png', fit: BoxFit.contain);
    }

    final mainAvatar = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: backgroundColor),
      padding: EdgeInsets.all(padding),
      child: ClipOval(
        child: imageWidget,
      ),
    );

    if (isOnline) {
      return Stack(
        children: [
          mainAvatar,
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: const Color(0xFF00C853),
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
            ),
          ),
        ],
      );
    }

    return mainAvatar;
  }
}

class ProfessionalSupportScreen extends StatefulWidget {
  const ProfessionalSupportScreen({super.key});

  static final Set<String> sessionSubscribedTherapistIds = <String>{};
  static final Set<String> sessionHiddenTherapistIds = <String>{};

  @override
  State<ProfessionalSupportScreen> createState() =>
      _ProfessionalSupportScreenState();
}

class _ProfessionalSupportScreenState extends State<ProfessionalSupportScreen> with WidgetsBindingObserver {
  final Set<String> _subscribedTherapistIds = ProfessionalSupportScreen.sessionSubscribedTherapistIds;
  final Set<String> _hiddenTherapistIds = ProfessionalSupportScreen.sessionHiddenTherapistIds;
  bool _showFindTherapist = false;
  bool _stateLoaded = false;
  Future<List<Object?>>? _supportDataFuture;

  Future<List<Object?>> _fetchSupportData() {
    return Future.wait<Object?>([
      AppRepositories.support.listTherapists(),
      _loadActiveSubscribedTherapistIds(),
      _loadSubscribedTherapistsIncludingInactive(),
    ]);
  }

  void _showComingSoon() {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Coming soon')));
  }

  String? _activeCheckoutTherapistId;
  bool _isCheckoutCancelled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _supportDataFuture = _fetchSupportData();
    _loadPersistedTherapistState();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _activeCheckoutTherapistId != null && !_isCheckoutCancelled) {
      final therapistId = _activeCheckoutTherapistId!;
      // Give the backend a moment to process the SafePay redirect before checking.
      // SafePay has a race condition where the failure redirect fires first (even after a
      // successful payment), temporarily writing 'payment_failed'. The polling loop
      // handles re-verification during the grace period, so we only cancel here on
      // definitively terminal states (canceled/expired), NOT on payment_failed.
      Future.delayed(const Duration(milliseconds: 4000), () async {
        if (_activeCheckoutTherapistId != therapistId || _isCheckoutCancelled) return;
        try {
          await AppRepositories.billing.syncSubscriptionStatus(therapistId);
        } catch (e) {
          debugPrint('Error syncing checkout status on resume: $e');
        }
        final sub = await AppRepositories.billing.getSubscriptionForTherapist(therapistId);
        if (sub != null) {
          final status = sub.status.trim().toLowerCase();
          // Only cancel checkout on definitively terminal failure states.
          // Do NOT cancel on 'payment_failed' — it may be a transient SafePay race
          // condition that the polling loop's grace period will automatically resolve.
          if (status == 'canceled' || status == 'expired') {
            debugPrint('Checkout cancelled on resume: subscription status = $status');
            if (mounted) {
              setState(() {
                _isCheckoutCancelled = true;
              });
            }
          }
          // If status is 'active', 'pending', or 'payment_failed', let the polling loop handle it
        }
        // Do NOT set _isCheckoutCancelled when sub is null — could be timing issue
      });
    }
  }

  Future<void> _refreshState() async {
    await _loadPersistedTherapistState();
    setState(() {
      _supportDataFuture = _fetchSupportData();
    });
  }

  Future<void> _loadPersistedTherapistState() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        if (mounted) {
          setState(() => _stateLoaded = true);
        }
        return;
      }
      final doc = await FirebaseFirestore.instance
          .collection(FirestoreCollections.users)
          .doc(uid)
          .get();
      final data = doc.data();
      if (data != null) {
        final persistedSubscribed = stringListFrom(
          data['proSupportSubscribedTherapistIds'],
        );
        final persistedHidden = stringListFrom(
          data['proSupportHiddenTherapistIds'],
        );
        _subscribedTherapistIds
          ..clear()
          ..addAll(persistedSubscribed);
        _hiddenTherapistIds
          ..clear()
          ..addAll(persistedHidden);
      }
    } catch (_) {
      // Keep session state fallback even if persistence read fails.
    } finally {
      await _syncSubscribedTherapistsFromBackend();
      if (mounted) {
        setState(() => _stateLoaded = true);
      }
    }
  }

  Future<Set<String>> _loadActiveSubscribedTherapistIds() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return <String>{};
    }
    final snapshot = await FirebaseFirestore.instance
        .collection(FirestoreCollections.subscriptions)
        .where('userId', isEqualTo: uid)
        .where('isActive', isEqualTo: true)
        .get();
    return snapshot.docs
        .map((doc) => (doc.data()['therapistId'] ?? '').toString().trim())
        .where((id) => id.isNotEmpty)
        .toSet();
  }

  Future<void> _syncSubscribedTherapistsFromBackend() async {
    final activeIds = await _loadActiveSubscribedTherapistIds();
    _subscribedTherapistIds
      ..clear()
      ..addAll(activeIds);
    await _persistTherapistState();
  }

  Future<void> _persistTherapistState() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return;
    }
    await FirebaseFirestore.instance
        .collection(FirestoreCollections.users)
        .doc(uid)
        .set({
          'proSupportSubscribedTherapistIds': _subscribedTherapistIds.toList(),
          'proSupportHiddenTherapistIds': _hiddenTherapistIds.toList(),
          'proSupportUpdatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
  }

  Future<Map<String, TherapistProfile>>
  _loadSubscribedTherapistsIncludingInactive() async {
    if (_subscribedTherapistIds.isEmpty) {
      return const <String, TherapistProfile>{};
    }
    final entries = await Future.wait(
      _subscribedTherapistIds.map((therapistId) async {
        try {
          final profile = await AppRepositories.support.getTherapistById(
            therapistId,
          );
          return MapEntry(therapistId, profile);
        } catch (_) {
          return MapEntry<String, TherapistProfile?>(therapistId, null);
        }
      }),
    );
    return {
      for (final entry in entries)
        if (entry.value != null) entry.key: entry.value!,
    };
  }

  bool _isTherapistSubscribed(
    TherapistProfile therapist,
  ) {
    return _subscribedTherapistIds.contains(therapist.id);
  }

  Widget _buildChecklistItem(IconData icon, String text) {

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: const Color(0xFF4B5563)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF4B5563),
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<bool?> _showSubscriptionWarningDialog(
    BuildContext context,
    TherapistProfile therapist,
  ) async {
    bool isChecked = false;

    // Fetch latest therapist profile to ensure we have credentials and certificate base64
    String certificateBase64 = therapist.certificateBase64;
    String licenseNumber = therapist.licenseNumber;
    String registrationNumber = therapist.registrationNumber;
    String credentials = therapist.credentials;

    try {
      final doc = await FirebaseFirestore.instance
          .collection(FirestoreCollections.therapistProfiles)
          .doc(therapist.id)
          .get();
      final data = doc.data();
      if (data != null) {
        certificateBase64 = (data['certificateBase64'] ?? '').toString();
        licenseNumber = (data['licenseNumber'] ?? data['license_number'] ?? '').toString();
        registrationNumber = (data['registrationNumber'] ?? data['registration_number'] ?? '').toString();
        credentials = (data['credentials'] ?? '').toString();
      }
    } catch (_) {}

    if (!context.mounted) return false;

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              titlePadding: EdgeInsets.zero,
              title: Container(
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                decoration: const BoxDecoration(
                  color: Color(0xFFFFF3CD),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: Color(0xFFD97706),
                      size: 28,
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Verification Consent',
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
                      'AutiEase has verified this therapist\'s documentation. However, just for backup, you must also individually and independently verify them before subscribing.',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1F2937),
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Independent Verification Checklist:',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF374151),
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildChecklistItem(
                      Icons.assignment_ind_outlined,
                      'Check their certificates and ensure their profile is aligned with their documents.',
                    ),
                    _buildChecklistItem(
                      Icons.star_border,
                      'Check ratings and reviews from other parents.',
                    ),
                    _buildChecklistItem(
                      Icons.search,
                      'Verify registry status online via professional websites (e.g. PMC, AHPC or field-related registers).',
                    ),
                    const SizedBox(height: 14),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF9FAFB),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFE5E7EB)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            therapist.displayName,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                              color: Color(0xFF1F2937),
                            ),
                          ),
                          if (credentials.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              'Credentials: $credentials',
                              style: const TextStyle(fontSize: 11, color: Color(0xFF4B5563)),
                            ),
                          ],
                          if (licenseNumber.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              'License Number: $licenseNumber',
                              style: const TextStyle(fontSize: 11, color: Color(0xFF4B5563)),
                            ),
                          ],
                          if (registrationNumber.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              'Registration ID: $registrationNumber',
                              style: const TextStyle(fontSize: 11, color: Color(0xFF4B5563)),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (certificateBase64.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            try {
                              final pdfBytes = base64Decode(certificateBase64);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => CertificateViewerScreen(
                                    pdfBytes: pdfBytes,
                                    title: '${therapist.displayName} - Certificate',
                                  ),
                                ),
                              );
                            } catch (_) {}
                          },
                          icon: const Icon(Icons.description_outlined, size: 16),
                          label: const Text(
                            'View Therapist Certificate',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF11B5CF),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 11),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    // Liability Warning Box
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFFCA5A5)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.gavel_rounded,
                            color: Color(0xFFDC2626),
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'Liability Alert: AutiEase is not responsible for any issues. You must also independently verify before subscribing.',
                              style: TextStyle(
                                color: Color(0xFF991B1B),
                                fontSize: 10.5,
                                fontWeight: FontWeight.w500,
                                height: 1.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    // Checkbox Consent row
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          height: 24,
                          width: 24,
                          child: Checkbox(
                            value: isChecked,
                            onChanged: (bool? val) {
                              setState(() {
                                isChecked = val ?? false;
                              });
                            },
                            activeColor: const Color(0xFF00C853),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                isChecked = !isChecked;
                              });
                            },
                            child: const Text(
                              'I verified therapist and I read the warning and consent to subscribe',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: Color(0xFF374151),
                                fontWeight: FontWeight.w500,
                                height: 1.3,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text(
                    'Close',
                    style: TextStyle(
                      color: Color(0xFF6B7280),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                ElevatedButton(
                  onPressed: isChecked
                      ? () => Navigator.pop(dialogContext, true)
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00C853),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.grey[300],
                    disabledForegroundColor: Colors.grey[500],
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  ),
                  child: const Text(
                    'Subscribe',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<bool> _openCheckoutForTherapist(TherapistProfile therapist, {int packageIndex = 0}) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null) {
      final hasRestriction = await AppRepositories.support.hasActiveRestrictionBetween(
        parentId: currentUser.uid,
        therapistId: therapist.id,
      );
      if (hasRestriction) {
        if (mounted) {
          final isTherapistRestricted = therapist.moderationStatus == 'restricted';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(isTherapistRestricted
                  ? "Therapist's account is restricted, so you cannot switch or buy another package."
                  : 'Your account is restricted. You cannot switch or buy another package.'),
              backgroundColor: AppColors.errorRed,
            ),
          );
        }
        return false;
      }
    }
    if (!mounted) return false;

    final confirmed = await _showSubscriptionWarningDialog(context, therapist);
    if (confirmed != true) {
      return false;
    }

    if (!mounted) return false;

    // Set class-level active checkout context
    _activeCheckoutTherapistId = therapist.id;
    _isCheckoutCancelled = false;

    // Show a dismissible checkout dialog with a Cancel button
    BuildContext? dialogContext;
    if (mounted) {
      showDialog<void>(
        context: context,
        barrierDismissible: false, // Cannot dismiss while checkout is in progress
        builder: (BuildContext dialogCtx) {
          dialogContext = dialogCtx;
          return PopScope(
            canPop: false, // Prevent accidental dismiss — only Cancel button or payment result should close
            onPopInvokedWithResult: (didPop, _) {
              // Handled programmatically or via Cancel button
            },
            child: AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Text(
                'Opening Secure Checkout',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                textAlign: TextAlign.center,
              ),
              contentPadding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
              content: const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Color(0xFF00C853)),
                  SizedBox(height: 16),
                  Text(
                    'Your secure checkout page will open in a few seconds. Please wait while we redirect you to your browser.',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: 12),
                  Text(
                    'Instructions:\n'
                    '• After a successful payment, you will be automatically redirected back to the app and your subscription will be activated.\n'
                    '• If you cancel the payment or return without completing the transaction, you will be redirected back to the app\'s home screen and no subscription will be created.\n'
                    '• If you do not wish to continue, you can tap Cancel below to stop the process before the checkout page opens.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF64748B), height: 1.4),
                    textAlign: TextAlign.left,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    setState(() {
                      _isCheckoutCancelled = true;
                    });
                    if (dialogContext != null) {
                      Navigator.pop(dialogContext!);
                    }
                  },
                  style: TextButton.styleFrom(foregroundColor: AppColors.errorRed),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          );
        },
      );
    }

    try {
      final success = await AppRepositories.billing.purchaseTherapistSubscription(
        therapist.id,
        packageIndex: packageIndex,
        isCancelledCheck: () => _isCheckoutCancelled,
      );

      // Close the dialog if still open
      debugPrint('Checkout finished. dialogContext=$dialogContext, mounted=${dialogContext?.mounted}');
      if (dialogContext != null && dialogContext!.mounted) {
        final ctxToPop = dialogContext!;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (ctxToPop.mounted) {
            Navigator.of(ctxToPop).pop();
            debugPrint('Navigator.pop executed on dialogContext post-frame');
          }
        });
      }

      if (_isCheckoutCancelled) {
        // User dismissed — clean up the pending subscription silently
        AppRepositories.billing.deletePendingSubscription(therapist.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Payment cancelled. You can subscribe again anytime.'),
              backgroundColor: Color(0xFF64748B),
              duration: Duration(seconds: 4),
            ),
          );
        }
        return false;
      }

      if (success) {
        setState(() {
          _subscribedTherapistIds.add(therapist.id);
          _hiddenTherapistIds.remove(therapist.id);
        });
        await _persistTherapistState();

        // Auto-create chat thread in the background
        Future.microtask(() async {
          try {
            final child = await AppRepositories.users.getActiveChildForCurrentParent();
            final subscription = await AppRepositories.billing.getSubscriptionForTherapist(therapist.id);
            if (child != null) {
              await AppRepositories.support.ensureThread(
                therapistId: therapist.id,
                childId: child.id,
                subscriptionId: (subscription != null && subscription.isActive)
                    ? subscription.id
                    : 'local-bypass',
              );
            }
          } catch (e) {
            debugPrint('Failed to auto-create chat thread: $e');
          }
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Subscription activated for ${therapist.displayName}.'),
              backgroundColor: const Color(0xFF00C853),
            ),
          );
        }
        return true;
      } else {
        // Payment timed out or failed — clean up pending record so user can retry
        AppRepositories.billing.deletePendingSubscription(therapist.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Payment not completed. Please try subscribing again.'),
              backgroundColor: AppColors.errorRed,
              duration: Duration(seconds: 5),
            ),
          );
        }
        return false;
      }
    } catch (e) {
      setState(() {
        _isCheckoutCancelled = true;
      });
      if (dialogContext != null && dialogContext!.mounted) {
        final ctxToPop = dialogContext!;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (ctxToPop.mounted) {
            Navigator.of(ctxToPop).pop();
          }
        });
      }
      // Clean up any pending subscription created before the error
      AppRepositories.billing.deletePendingSubscription(therapist.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Checkout failed: $e'),
            backgroundColor: AppColors.errorRed,
          ),
        );
      }
      return false;
    } finally {
      _activeCheckoutTherapistId = null;
    }
  }

  Future<bool> _cancelTherapistSubscription(TherapistProfile therapist) async {
    // 1. Show the Warning Dialog
    final cancelReason = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return CancelSubscriptionDialog(
          therapistName: therapist.displayName,
          onConfirmCancel: (reason) => Navigator.pop(dialogCtx, reason),
        );
      },
    );

    if (cancelReason == null) return false;

    // 2. Show the Chat History Choices Dialog
    if (!mounted) return false;
    final choice = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return ChatHistoryChoicesDialog(
          therapistId: therapist.id,
          cancellationReason: cancelReason,
          onComplete: (choice) {
            // Handled inside choices dialog State
          },
        );
      },
    );

    if (choice == null) return false;

    // 3. Post-Cancellation Updates
    if (mounted) {
      setState(() {
        _subscribedTherapistIds.remove(therapist.id);
        if (choice == 'delete') {
          _hiddenTherapistIds.add(therapist.id);
        }
      });
      await _persistTherapistState();
      if (!mounted) return true;
      
      final messenger = ScaffoldMessenger.of(context);
      if (choice == 'delete') {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Subscription cancelled and chat history deleted.'),
            backgroundColor: AppColors.errorRed,
          ),
        );
      } else {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Subscription cancelled. Chat locked to read-only.'),
            backgroundColor: Color(0xFF3B82F6),
          ),
        );
      }
      
      _showReviewDialog(context, therapist);
    }
    return true;
  }

  void _showReviewDialog(BuildContext context, TherapistProfile therapist) {
    int selectedRating = 5;
    final publicController = TextEditingController();
    final privateController = TextEditingController();
    final List<String> lowRatingOptions = const [
      'Poor communication',
      'Unhelpful advice',
      'Slow response times',
      'Lack of empathy',
      'Technical issues',
    ];
    final Set<String> selectedReasons = <String>{};

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Text(
                'Rate & Review\n${therapist.displayName}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1F2937),
                ),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'How was your experience with this therapist?',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, color: Color(0xFF4B5563)),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(5, (index) {
                        final starValue = index + 1;
                        return IconButton(
                          onPressed: () {
                            setDialogState(() {
                              selectedRating = starValue;
                            });
                          },
                          icon: Icon(
                            starValue <= selectedRating
                                ? Icons.star
                                : Icons.star_border,
                            color: Colors.amber,
                            size: 32,
                          ),
                        );
                      }),
                    ),
                    if (selectedRating <= 2) ...[
                      const SizedBox(height: 16),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'What went wrong? (Select all that apply)',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF374151),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...lowRatingOptions.map((option) {
                        final isChecked = selectedReasons.contains(option);
                        return CheckboxListTile(
                          title: Text(option, style: const TextStyle(fontSize: 13)),
                          value: isChecked,
                          dense: true,
                          controlAffinity: ListTileControlAffinity.leading,
                          contentPadding: EdgeInsets.zero,
                          activeColor: const Color(0xFF00C853),
                          onChanged: (val) {
                            setDialogState(() {
                              if (val == true) {
                                selectedReasons.add(option);
                              } else {
                                selectedReasons.remove(option);
                              }
                            });
                          },
                        );
                      }),
                    ],
                    const SizedBox(height: 16),
                    TextField(
                      controller: publicController,
                      maxLines: 3,
                      maxLength: 300,
                      buildCounter: (context, {required currentLength, required maxLength, required isFocused}) {
                        return Text(
                          '$currentLength/$maxLength',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF6B7280),
                          ),
                        );
                      },
                      decoration: InputDecoration(
                        labelText: 'Written Feedback (Optional)',
                        hintText: 'Share your experience with other parents...',
                        alignLabelWithHint: true,
                        contentPadding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: privateController,
                      maxLines: 2,
                      maxLength: 300,
                      buildCounter: (context, {required currentLength, required maxLength, required isFocused}) {
                        return Text(
                          '$currentLength/$maxLength',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF6B7280),
                          ),
                        );
                      },
                      decoration: InputDecoration(
                        labelText: 'Private Notes (Optional)',
                        hintText: 'Feedback visible only to admin/platform...',
                        alignLabelWithHint: true,
                        contentPadding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Maybe Later', style: TextStyle(color: Color(0xFF6B7280))),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (publicController.text.trim().length > 300 ||
                        privateController.text.trim().length > 300) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Review feedback must not exceed 300 characters.'),
                          backgroundColor: Color(0xFFEF4444),
                        ),
                      );
                      return;
                    }
                    try {
                      await AppRepositories.support.submitReview(
                        therapistId: therapist.id,
                        rating: selectedRating,
                        feedback: publicController.text.trim(),
                        privateFeedback: privateController.text.trim(),
                        lowRatingReasons: selectedRating <= 2 ? selectedReasons.toList() : const [],
                      );
                      if (ctx.mounted) {
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(
                            content: Text('Thank you! Your review has been submitted.'),
                            backgroundColor: Color(0xFF00C853),
                          ),
                        );
                      }
                    } catch (e) {
                      if (ctx.mounted) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(
                            content: Text('Failed to submit review: $e'),
                            backgroundColor: AppColors.errorRed,
                          ),
                        );
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00C853),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text('Submit'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _openExistingThread(
    TherapistThread thread,
    TherapistProfile therapist, {
    required bool chatEnabled,
  }) async {
    if (!chatEnabled) {
      _showComingSoon();
      return;
    }
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TherapistChatScreen(
          thread: thread,
          participantName: therapist.displayName,
          senderRole: 'parent',
          therapistProfile: therapist,
        ),
      ),
    );
    if (!mounted) return;
    if (result != null && result.toString().startsWith('show_review_')) {
      _showReviewDialog(context, therapist);
    }
  }

  Future<void> _openTherapistChat(
    TherapistProfile therapist, {
    required bool chatEnabled,
  }) async {
    if (!chatEnabled) {
      _showComingSoon();
      return;
    }
    try {
      final child = await AppRepositories.users
          .getActiveChildForCurrentParent();
      final subscription = await AppRepositories.billing
          .getSubscriptionForTherapist(therapist.id);
      if (!mounted) return;

      if (child == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please complete child profile before messaging.'),
            backgroundColor: AppColors.errorRed,
          ),
        );
        return;
      }

      final hasActiveBackendSubscription = subscription?.isActive == true;
      if (!_subscribedTherapistIds.contains(therapist.id) &&
          !hasActiveBackendSubscription) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please subscribe to this therapist first.'),
            backgroundColor: AppColors.errorRed,
          ),
        );
        return;
      }

      final thread = await AppRepositories.support.ensureThread(
        therapistId: therapist.id,
        childId: child.id,
        subscriptionId: (subscription != null && subscription.isActive)
            ? subscription.id
            : 'local-bypass',
      );
      if (!mounted) return;
      final result = await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TherapistChatScreen(
            thread: thread,
            participantName: therapist.displayName,
            senderRole: 'parent',
            therapistProfile: therapist,
          ),
        ),
      );
      await _refreshState();
      if (!mounted) return;
      if (result != null && result.toString().startsWith('show_review_')) {
        _showReviewDialog(context, therapist);
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to open chat: $error'),
          backgroundColor: AppColors.errorRed,
        ),
      );
    }
  }

  Future<void> _openTherapistDetails(
    TherapistProfile therapist,
    bool isSubscribed,
    ProfessionalSupportFeatureFlags featureFlags,
  ) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => SupportTherapistDetailsScreen(
          therapist: therapist,
          initiallySubscribed: isSubscribed,
          chatEnabled: featureFlags.chatEnabled,
          paymentsEnabled: featureFlags.paymentsEnabled,
          onSubscribe: (packageIndex) => _openCheckoutForTherapist(therapist, packageIndex: packageIndex),
          onCancelSubscription: () => _cancelTherapistSubscription(therapist),
          onOpenMessages: () => _openTherapistChat(
            therapist,
            chatEnabled: featureFlags.chatEnabled,
          ),
        ),
      ),
    );
    await _refreshState();
  }

  @override
  Widget build(BuildContext context) {
    if (!_stateLoaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return SessionGuard(
      role: SessionGuardRole.parent,
      child: Scaffold(
        backgroundColor: const Color(0xFFF1F5F3),
        body: SafeArea(
          child: StreamBuilder<ProfessionalSupportFeatureFlags>(
            stream: AppRepositories.content
                .watchProfessionalSupportFeatureFlags(),
            initialData: ProfessionalSupportFeatureFlags.enabled,
            builder: (context, featureSnapshot) {
              final featureFlags =
                  featureSnapshot.data ??
                  ProfessionalSupportFeatureFlags.enabled;
              return FutureBuilder<List<Object?>>(
                future: _supportDataFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  final activeTherapists =
                      snapshot.data?[0] as List<TherapistProfile>? ?? const [];
                  final activeSubscribedIds = snapshot.data?[1] as Set<String>? ?? const <String>{};
                  final subscribedTherapists =
                      snapshot.data?[2] as Map<String, TherapistProfile>? ??
                      const <String, TherapistProfile>{};

                  // Keep local state set in sync
                  _subscribedTherapistIds
                    ..clear()
                    ..addAll(activeSubscribedIds);

                  final therapistById = <String, TherapistProfile>{
                    for (final therapist in activeTherapists)
                      therapist.id: therapist,
                    ...subscribedTherapists,
                  };
                  final allKnownTherapists = therapistById.values.toList();

                  return Column(
                    children: [
                      _SupportHeaderCard(
                        title: _showFindTherapist
                            ? 'Find a Therapist'
                            : 'Professional Support',
                        subtitle: _showFindTherapist
                            ? 'Choose your specialist'
                            : 'Your therapist conversations',
                        onBack: () {
                          if (_showFindTherapist) {
                            setState(() => _showFindTherapist = false);
                            return;
                          }
                          Navigator.pop(context);
                        },
                        showAdd: !_showFindTherapist,
                        onAdd: () => setState(() => _showFindTherapist = true),
                        showHistory: !_showFindTherapist,
                        onHistory: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const ParentSubscriptionsHistoryScreen(),
                            ),
                          );
                          await _refreshState();
                        },
                      ),
                      Expanded(
                        child: _showFindTherapist
                            ? _buildFindTherapists(
                                activeTherapists,
                                featureFlags,
                              )
                            : _buildMessagesHome(
                                allKnownTherapists,
                                therapistById,
                                featureFlags.chatEnabled,
                              ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildFindTherapists(
    List<TherapistProfile> therapists,
    ProfessionalSupportFeatureFlags featureFlags,
  ) {
    if (therapists.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            'No therapists available yet. Please check back soon for updates.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF4B5563)),
          ),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 20),
      itemCount: therapists.length,
      itemBuilder: (context, index) {
        final therapist = therapists[index];
        final isSubscribed = _isTherapistSubscribed(
          therapist,
        );
        return _TherapistListCard(
          therapist: therapist,
          isSubscribed: isSubscribed,
          onTap: () =>
              _openTherapistDetails(therapist, isSubscribed, featureFlags),
        );
      },
    );
  }

  Widget _buildMessagesHome(
    List<TherapistProfile> therapists,
    Map<String, TherapistProfile> therapistById,
    bool chatEnabled,
  ) {
    final subscribedVisibleIds = _subscribedTherapistIds
        .where((id) => !_hiddenTherapistIds.contains(id))
        .toSet();


    return StreamBuilder<List<TherapistThread>>(
      stream: AppRepositories.support.watchThreadsForRole('parent'),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final backendThreads = (snapshot.data ?? const <TherapistThread>[])
            .where(
              (thread) =>
                  (subscribedVisibleIds.contains(thread.therapistId) || thread.status == 'locked') &&
                  !_hiddenTherapistIds.contains(thread.therapistId),
            )
            .toList();

        if (backendThreads.isEmpty && subscribedVisibleIds.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                'No subscribed therapist yet. Tap + to find and subscribe.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF6B7280)),
              ),
            ),
          );
        }

        final hasThreadForTherapist = <String>{
          for (final thread in backendThreads) thread.therapistId,
        };

        final localSubscribedWithoutThread = therapists
            .where(
              (therapist) =>
                  subscribedVisibleIds.contains(therapist.id) &&
                  !hasThreadForTherapist.contains(therapist.id) &&
                  !_hiddenTherapistIds.contains(therapist.id),
            )
            .toList();

        final hasAny =
            backendThreads.isNotEmpty ||
            localSubscribedWithoutThread.isNotEmpty;
        if (!hasAny) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                'No active conversation yet for subscribed therapists.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF6B7280)),
              ),
            ),
          );
        }

        return ListView(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 20),
          children: [
            for (final thread in backendThreads)
              StreamBuilder<RestrictionRecord?>(
                stream: AppRepositories.support.watchActiveRestriction(
                  parentId: thread.parentId,
                  therapistId: thread.therapistId,
                ),
                builder: (context, restSnap) {
                  final hasRest = restSnap.data != null && restSnap.data!.isActive;
                  return _MessageHomeCard(
                    therapistName: thread.therapistDisplayName.isNotEmpty
                        ? thread.therapistDisplayName
                        : (therapistById[thread.therapistId]?.displayName ??
                              'Therapist'),
                    preview: thread.lastMessagePreview.isEmpty
                        ? "I'd recommend continuing with the communication exercises at home."
                        : thread.lastMessagePreview,
                    timeLabel: _formatTime(thread.lastMessageAt),
                    photoBase64: therapistById[thread.therapistId]?.photoUrlBase64.isNotEmpty == true
                        ? therapistById[thread.therapistId]?.photoUrlBase64
                        : therapistById[thread.therapistId]?.photoUrl,
                    isOnline: (() {
                      final t = therapistById[thread.therapistId];
                      if (t == null || t.lastActiveAt == null) return false;
                      return DateTime.now().difference(t.lastActiveAt!).inMinutes < 5;
                    })(),
                    rating: therapistById[thread.therapistId]?.rating ?? 0.0,
                    isUnread: (() {
                      if (thread.lastMessageAt == null) return false;
                      if (thread.parentLastRead == null) return true;
                      return thread.lastMessageAt!.isAfter(thread.parentLastRead!);
                    })(),
                    isRestricted: hasRest,
                    onTap: () {
                      final therapist = therapistById[thread.therapistId];
                      if (therapist == null) {
                        return;
                      }
                      _openExistingThread(
                        thread,
                        therapist,
                        chatEnabled: chatEnabled,
                      );
                    },
                    onLongPress: () => _confirmDeleteChat(thread),
                  );
                },
              ),
            for (final therapist in localSubscribedWithoutThread)
              _MessageHomeCard(
                therapistName: therapist.displayName,
                preview:
                    "I'd recommend continuing with the communication exercises at home.",
                timeLabel: '10:40 AM',
                photoBase64: therapist.photoUrlBase64.isNotEmpty
                    ? therapist.photoUrlBase64
                    : therapist.photoUrl,
                isOnline: therapist.lastActiveAt != null &&
                    DateTime.now().difference(therapist.lastActiveAt!).inMinutes < 5,
                rating: therapist.rating,
                onTap: () =>
                    _openTherapistChat(therapist, chatEnabled: chatEnabled),
              ),

          ],
        );
      },
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
          'This will completely delete the chat history with this therapist. This action cannot be undone.',
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

  String _formatTime(DateTime? value) {
    if (value == null) {
      return '10:40 AM';
    }
    final hour = value.hour % 12 == 0 ? 12 : value.hour % 12;
    final minute = value.minute.toString().padLeft(2, '0');
    final suffix = value.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $suffix';
  }
}

class _SupportHeaderCard extends StatelessWidget {
  const _SupportHeaderCard({
    required this.title,
    required this.subtitle,
    this.onBack,
    this.showAdd = false,
    this.onAdd,
    this.showHistory = false,
    this.onHistory,
  });

  final String title;
  final String subtitle;
  final VoidCallback? onBack;
  final bool showAdd;
  final VoidCallback? onAdd;
  final bool showHistory;
  final VoidCallback? onHistory;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFBDF1D0),
        borderRadius: BorderRadius.circular(2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack ?? () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back, color: Color(0xFF374151)),
            style: IconButton.styleFrom(
              backgroundColor: const Color(0xFFF1F5F3),
              minimumSize: const Size(34, 34),
              shape: const CircleBorder(),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1F2937),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF6B7280),
                  ),
                ),
              ],
            ),
          ),
          if (showHistory) ...[
            IconButton(
              onPressed: onHistory,
              icon: const Icon(Icons.receipt_long, color: Color(0xFF00C853), size: 20),
              style: IconButton.styleFrom(
                backgroundColor: const Color(0xFFF1F5F3),
                minimumSize: const Size(34, 34),
                shape: const CircleBorder(),
              ),
            ),
            const SizedBox(width: 8),
          ],
          if (showAdd)
            IconButton(
              onPressed: onAdd,
              icon: const Icon(Icons.add, color: Colors.white, size: 24),
              style: IconButton.styleFrom(
                backgroundColor: const Color(0xFF00C853),
                minimumSize: const Size(34, 34),
                shape: const CircleBorder(),
              ),
            ),
        ],
      ),
    );
  }
}

class _TherapistListCard extends StatelessWidget {
  const _TherapistListCard({
    required this.therapist,
    required this.isSubscribed,
    required this.onTap,
  });

  final TherapistProfile therapist;
  final bool isSubscribed;
  final VoidCallback onTap;

  List<String> _specializations(TherapistProfile profile) {
    return profile.specializations
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  String _specialization(TherapistProfile profile) {
    final specs = _specializations(profile);
    if (specs.isNotEmpty) {
      return specs.first;
    }
    return 'Specialization not set';
  }


  @override
  Widget build(BuildContext context) {
    final specialization = _specialization(therapist);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _TherapistPlaceholderAvatar(
                  size: 44,
                  photoBase64: therapist.photoUrlBase64,
                  isOnline: therapist.lastActiveAt != null &&
                      DateTime.now().difference(therapist.lastActiveAt!).inMinutes < 5,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            therapist.displayName,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF1F2937),
                            ),
                          ),
                          if (therapist.verifiedBadge || therapist.verificationStatus == 'approved') ...[
                            const SizedBox(width: 4),
                            const Icon(Icons.verified, color: Colors.blue, size: 16),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        specialization,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFF00A63E),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (therapist.totalReviews > 0) ...[
                            const Icon(Icons.star, color: Colors.amber, size: 14),
                            const SizedBox(width: 2),
                            Text(
                              '${therapist.rating.toStringAsFixed(1)} (${therapist.totalReviews})',
                              style: const TextStyle(
                                fontSize: 12.5,
                                color: Color(0xFF1F2937),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Text('|', style: TextStyle(color: Colors.grey, fontSize: 12)),
                            const SizedBox(width: 8),
                          ],
                          Text(
                            therapist.formattedExperience,
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: Color(0xFF6B7280),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Color(0xFF9CA3AF),
                  size: 22,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              therapist.bio.isEmpty
                  ? 'Bio not provided'
                  : therapist.bio,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13.5,
                color: Color(0xFF4B5563),
                height: 1.35,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: isSubscribed
                        ? const Color(0xFFD4F7DA)
                        : const Color(0xFFDCE8FF),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    isSubscribed ? 'Subscribed' : 'View Details',
                    style: TextStyle(
                      color: isSubscribed
                          ? const Color(0xFF0B8F3E)
                          : const Color(0xFF4F46E5),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageHomeCard extends StatelessWidget {
  const _MessageHomeCard({
    required this.therapistName,
    required this.preview,
    required this.timeLabel,
    required this.onTap,
    this.onLongPress,
    this.photoBase64,
    this.isOnline = false,
    this.rating = 0.0,
    this.isUnread = false,
    this.isRestricted = false,
  });

  final String therapistName;
  final String preview;
  final String timeLabel;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final String? photoBase64;
  final bool isOnline;
  final double rating;
  final bool isUnread;
  final bool isRestricted;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                _TherapistPlaceholderAvatar(
                  size: 44,
                  photoBase64: photoBase64,
                  isOnline: isOnline,
                ),
                if (rating > 0)
                  Positioned(
                    bottom: -4,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFA000),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.18),
                              blurRadius: 4,
                              offset: const Offset(0, 1),
                            ),
                          ],
                        ),
                        child: Text(
                          '⭐ ${rating.toStringAsFixed(1)}',
                          style: const TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            height: 1.1,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          therapistName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF1F2937),
                          ),
                        ),
                      ),
                      if (isRestricted)
                        const Padding(
                          padding: EdgeInsets.only(left: 6),
                          child: Icon(Icons.lock_clock, color: Colors.amber, size: 18),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    preview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13.5,
                      color: Color(0xFF4B5563),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              children: [
                Text(
                  timeLabel,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF6B7280),
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: isUnread ? const Color(0xFFEF4444) : Colors.transparent,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}



class SupportTherapistDetailsScreen extends StatefulWidget {
  const SupportTherapistDetailsScreen({
    super.key,
    required this.therapist,
    required this.initiallySubscribed,
    required this.chatEnabled,
    required this.paymentsEnabled,
    required this.onSubscribe,
    required this.onCancelSubscription,
    required this.onOpenMessages,
  });

  final TherapistProfile therapist;
  final bool initiallySubscribed;
  final bool chatEnabled;
  final bool paymentsEnabled;
  final Future<bool> Function(int packageIndex) onSubscribe;
  final Future<bool> Function() onCancelSubscription;
  final Future<void> Function() onOpenMessages;

  @override
  State<SupportTherapistDetailsScreen> createState() =>
      SupportTherapistDetailsScreenState();
}

class SupportTherapistDetailsScreenState
    extends State<SupportTherapistDetailsScreen> {
  late bool _isSubscribed;
  bool _isSubscribing = false;
  bool _isSwitching = false;
  bool _isRestricted = false;
  bool _loadingTherapistMeta = true;
  int _yearsFromProfile = 0;
  int _monthsFromProfile = 0;
  String _credentialsFromProfile = '';
  String? _certificateBase64;
  List<_SupportServicePackage> _packages = const <_SupportServicePackage>[];
  int _activePackageIndex = 0;
  int? _subscribedPackageIndex;
  ChildProfile? _activeChild;

  String get _formattedExperience {
    if (_yearsFromProfile == 0 && _monthsFromProfile == 0) {
      return widget.therapist.formattedExperience;
    }
    if (_monthsFromProfile == 0) return '$_yearsFromProfile Years';
    return '$_yearsFromProfile.$_monthsFromProfile Years (approx)';
  }

  @override
  void initState() {
    super.initState();
    _isSubscribed = widget.initiallySubscribed;
    _loadTherapistMeta();
    _loadActiveChild();
    _checkRestriction();
  }

  Future<void> _checkRestriction() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null) {
      final res = await AppRepositories.support.hasActiveRestrictionBetween(
        parentId: currentUser.uid,
        therapistId: widget.therapist.id,
      );
      if (mounted) {
        setState(() {
          _isRestricted = res;
        });
      }
    }
  }

  Future<void> _loadActiveChild() async {
    try {
      final child = await AppRepositories.users.getActiveChildForCurrentParent();
      if (mounted) {
        setState(() {
          _activeChild = child;
        });
      }
    } catch (e) {
      debugPrint('Error loading active child: $e');
    }
  }

  Future<void> _loadTherapistMeta() async {
    try {
      final results = await Future.wait([
        FirebaseFirestore.instance
            .collection(FirestoreCollections.therapistProfiles)
            .doc(widget.therapist.id)
            .get(),
        AppRepositories.billing.getSubscriptionForTherapist(widget.therapist.id),
      ]);

      final doc = results[0] as DocumentSnapshot<Map<String, dynamic>>;
      final subscription = results[1] as UserSubscription?;

      int? subscribedPkgIdx;
      _SupportServicePackage? snapshotPkg;
      if (subscription != null && subscription.isActive) {
        final prodId = subscription.productId;
        if (prodId.startsWith('auto_${widget.therapist.id}_')) {
          final parts = prodId.split('_');
          if (parts.length >= 3) {
            subscribedPkgIdx = int.tryParse(parts.last);
          }
        } else if (prodId == 'bypass-plan' || prodId == 'local-bypass' || prodId == 'cached-offline') {
          subscribedPkgIdx = 0;
        }

        if (subscription.subscribedPackageSnapshot != null) {
          snapshotPkg = _SupportServicePackage(
            title: subscription.subscribedPackageSnapshot!.title,
            durationMinutes: subscription.subscribedPackageSnapshot!.durationMinutes,
            sessionsPerWeek: subscription.subscribedPackageSnapshot!.sessionsPerWeek,
            price: subscription.subscribedPackageSnapshot!.price,
            description: subscription.subscribedPackageSnapshot!.description,
            visible: subscription.subscribedPackageSnapshot!.visible,
          );
        }
      }

      final data = doc.data() ?? <String, dynamic>{};
      final rawParsed = _parsePackages(data['servicePackages']);
      final parsed = List<_SupportServicePackage>.from(rawParsed);

      if (subscribedPkgIdx != null && snapshotPkg != null) {
        if (subscribedPkgIdx < parsed.length) {
          parsed[subscribedPkgIdx] = snapshotPkg;
        } else {
          while (parsed.length <= subscribedPkgIdx) {
            parsed.add(const _SupportServicePackage(
              title: 'Deleted Package',
              durationMinutes: 0,
              sessionsPerWeek: 0,
              price: 0,
              description: 'This package has been removed by the therapist.',
              visible: false,
            ));
          }
          parsed[subscribedPkgIdx] = snapshotPkg;
        }
      }

      if (!mounted) {
        return;
      }
      setState(() {
        _yearsFromProfile = intFrom(data['experience_years'] ?? data['yearsOfExperience']);
        _monthsFromProfile = intFrom(data['experience_months']);
        _credentialsFromProfile = (data['credentials'] ?? '').toString();
        _certificateBase64 = (data['certificateBase64'] ?? '').toString();
        _packages = parsed;
        _subscribedPackageIndex = subscribedPkgIdx;
        _loadingTherapistMeta = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _loadingTherapistMeta = false);
      }
    }
  }

  List<_SupportServicePackage> _parsePackages(dynamic raw) {
    if (raw is! List) {
      return const <_SupportServicePackage>[];
    }
    return raw
        .whereType<Map>()
        .map(
          (entry) =>
              _SupportServicePackage.fromMap(Map<String, dynamic>.from(entry)),
        )
        .toList(growable: false);
  }

  List<_SupportServicePackage> _visiblePackages(TherapistProfile profile) {
    final visible = _packages
        .where((package) => package.visible)
        .toList(growable: false);
    return visible;
  }

  int _selectedPackageIndexWithin(int count) {
    if (count <= 0) {
      return 0;
    }
    if (_activePackageIndex < 0) {
      return 0;
    }
    if (_activePackageIndex >= count) {
      return count - 1;
    }
    return _activePackageIndex;
  }

  List<String> _specializations(TherapistProfile profile) {
    return profile.specializations
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  String _specialization(TherapistProfile profile) {
    final specs = _specializations(profile);
    if (specs.isNotEmpty) {
      return specs.first;
    }
    return 'Specialization not set';
  }



  Future<void> _subscribe() async {
    if (!widget.paymentsEnabled) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Coming soon')));
      return;
    }
    setState(() => _isSubscribing = true);
    final visiblePackages = _visiblePackages(widget.therapist);
    final safePackageIndex = _selectedPackageIndexWithin(visiblePackages.length);
    final subscribed = await widget.onSubscribe(safePackageIndex);
    if (!mounted) return;
    setState(() {
      _isSubscribing = false;
      if (subscribed) {
        _isSubscribed = true;
        _subscribedPackageIndex = safePackageIndex;
      }
    });
  }

  int? _getPackageIndex(UserSubscription? sub) {
    if (sub == null) return null;
    final prodId = sub.productId;
    if (prodId.startsWith('auto_${widget.therapist.id}_')) {
      final parts = prodId.split('_');
      if (parts.length >= 3) {
        return int.tryParse(parts.last);
      }
    } else if (prodId == 'bypass-plan' || prodId == 'local-bypass' || prodId == 'cached-offline') {
      return 0;
    }
    return null;
  }

  Future<void> _switchPackage(int newPackageIndex) async {
    if (!mounted) return;
    setState(() {
      _isSwitching = true;
    });

    try {
      // 1. Cancel existing subscription silently (keep and lock chats to preserve history)
      await AppRepositories.billing.cancelSubscriptionInStore(
        widget.therapist.id,
        keepAndLockChats: true,
      );

      // 2. Open checkout for the new package via widget.onSubscribe
      if (mounted) {
        final success = await widget.onSubscribe(newPackageIndex);
        if (mounted) {
          if (!success) {
            // If checkout failed or was cancelled, restore subscription status (silently sync back)
            await AppRepositories.billing.syncSubscriptionStatus(widget.therapist.id);
            final sub = await AppRepositories.billing.getSubscriptionForTherapist(widget.therapist.id);
            setState(() {
              _isSubscribed = sub != null && sub.isActive;
              if (_isSubscribed) {
                _subscribedPackageIndex = _getPackageIndex(sub);
              } else {
                _subscribedPackageIndex = null;
              }
            });
          } else {
            // Switch succeeded! The subscription is active. Sync local state.
            final sub = await AppRepositories.billing.getSubscriptionForTherapist(widget.therapist.id);
            setState(() {
              _isSubscribed = true;
              if (sub != null) {
                _subscribedPackageIndex = _getPackageIndex(sub);
              }
            });
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to switch package: $e'),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSwitching = false;
        });
      }
    }
  }

  Future<void> _viewCertificate() async {
    if (_certificateBase64 == null || _certificateBase64!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No certificate available.')),
      );
      return;
    }

    try {
      final pdfBytes = base64Decode(_certificateBase64!);
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => CertificateViewerScreen(
            pdfBytes: pdfBytes,
            title: '${widget.therapist.displayName} - Certificate',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to open certificate: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final therapist = widget.therapist;
    final allSpecializations = _specializations(therapist);
    final specialization = _specialization(therapist);
    final visiblePackages = _visiblePackages(therapist);
    final safePackageIndex = _selectedPackageIndexWithin(visiblePackages.length);
    final selectedPackage = visiblePackages.isNotEmpty ? visiblePackages[safePackageIndex] : null;

    return Stack(
      children: [
        Scaffold(
          backgroundColor: const Color(0xFFF1F5F3),
      body: SafeArea(
        child: Column(
          children: [
            const _SupportHeaderCard(
              title: 'Therapist Profile',
              subtitle: 'View details',
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 16),
                children: [
                  if (therapist.isAcceptingClients == false) ...[
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF2F2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFFCA5A5)),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.error_outline, color: Color(0xFFDC2626), size: 24),
                          SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'This therapist is currently at capacity or away. New subscriptions are temporarily disabled.',
                              style: TextStyle(
                                color: Color(0xFF991B1B),
                                fontSize: 13.5,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  _SupportDetailCard(
                    child: Column(
                      children: [
                        _TherapistPlaceholderAvatar(
                          size: 82,
                          padding: 6,
                          photoBase64: therapist.photoUrlBase64,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              therapist.displayName,
                              style: const TextStyle(
                                fontSize: 16.9,
                                color: Color(0xFF1F2937),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            if (therapist.verifiedBadge || therapist.verificationStatus == 'approved') ...[
                              const SizedBox(width: 4),
                              const Icon(Icons.verified, color: Colors.blue, size: 18),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          specialization,
                          style: const TextStyle(
                            color: Color(0xFF00A63E),
                            fontSize: 14,
                          ),
                        ),
                        if (allSpecializations.length > 1) ...[
                          const SizedBox(height: 8),
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 6,
                            runSpacing: 6,
                            children: allSpecializations
                                .skip(1)
                                .map(
                                  (item) => Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFE6F3FF),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      item,
                                      style: const TextStyle(
                                        fontSize: 11.5,
                                        color: Color(0xFF2563EB),
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                )
                                .toList(growable: false),
                          ),
                        ],
                        const SizedBox(height: 8),
                        if (_isSubscribed) ...[
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFD4F7DA),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.check,
                                  size: 16,
                                  color: Color(0xFF0B8F3E),
                                ),
                                SizedBox(width: 5),
                                Text(
                                  'Active Subscription',
                                  style: TextStyle(
                                    color: Color(0xFF0B8F3E),
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _SupportDetailCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Experience & Credentials',
                          style: TextStyle(
                            fontSize: 16,
                            color: Color(0xFF1F2937),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 14),
                        _DetailLine(
                          icon: Icons.access_time_rounded,
                          title: 'Experience',
                          value: _formattedExperience,
                        ),
                        const SizedBox(height: 10),
                        _DetailLine(
                          icon: Icons.verified_outlined,
                          title: 'Certifications',
                          value: _credentialsFromProfile.trim().isEmpty
                              ? 'No certifications listed'
                              : _credentialsFromProfile.trim(),
                        ),
                        if (_certificateBase64 != null && _certificateBase64!.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: _viewCertificate,
                            icon: const Icon(Icons.description_outlined),
                            label: const Text('View Therapist Certificate'),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(40),
                              side: const BorderSide(color: Color(0xFF11B5CF)),
                              foregroundColor: const Color(0xFF11B5CF),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _SupportDetailCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'About',
                          style: TextStyle(
                            fontSize: 16,
                            color: Color(0xFF1F2937),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          therapist.bio.trim().isEmpty
                              ? 'Bio not provided'
                              : therapist.bio,
                          style: const TextStyle(
                            color: Color(0xFF4B5563),
                            height: 1.5,
                            fontSize: 13.6,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_isSubscribed) ...[
                    const SizedBox(height: 12),
                    _SupportDetailCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Therapy & Progress Management',
                            style: TextStyle(
                              fontSize: 16,
                              color: Color(0xFF1F2937),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () {
                                    if (_activeChild == null) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('Please select or create a child profile first.'),
                                          backgroundColor: Color(0xFFEF4444),
                                        ),
                                      );
                                      return;
                                    }
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => ParentClinicalLogsScreen(
                                          therapistId: therapist.id,
                                          childId: _activeChild!.id,
                                          therapistName: therapist.displayName,
                                        ),
                                      ),
                                    );
                                  },
                                  icon: const Icon(Icons.description_outlined, size: 16),
                                  label: const Text('Clinical Logs', style: TextStyle(fontSize: 12)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF0D9488),
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () {
                                    if (_activeChild == null) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('Please select or create a child profile first.'),
                                          backgroundColor: Color(0xFFEF4444),
                                        ),
                                      );
                                      return;
                                    }
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => ParentSchedulerScreen(
                                          therapistId: therapist.id,
                                          therapistName: therapist.displayName,
                                          parentId: FirebaseAuth.instance.currentUser!.uid,
                                          childId: _activeChild!.id,
                                          childName: _activeChild!.name,
                                        ),
                                      ),
                                    );
                                  },
                                  icon: const Icon(Icons.calendar_month_outlined, size: 16),
                                  label: const Text('Schedule', style: TextStyle(fontSize: 12)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF0284C7),
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  _SupportTherapistReviewsSection(therapistId: therapist.id),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00C853),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.14),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Monthly Subscription',
                          style: TextStyle(color: Colors.white, fontSize: 18),
                        ),
                        const SizedBox(height: 10),
                        if (_loadingTherapistMeta)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 26),
                            child: Center(
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                                color: Colors.white,
                              ),
                            ),
                          )
                        else if (visiblePackages.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 20),
                            child: Center(
                              child: Text(
                                'No packages listed',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                          )
                        else
                          _PackageSelectionList(
                            packages: visiblePackages,
                            currentIndex: safePackageIndex,
                            isSubscribed: _isSubscribed,
                            subscribedPackageIndex: _subscribedPackageIndex,
                            isRestricted: _isRestricted,
                            isTherapistRestricted: widget.therapist.moderationStatus == 'restricted',
                            onPackageSelected: (index) {
                              if (!mounted) {
                                return;
                              }
                              setState(() => _activePackageIndex = index);
                            },
                            onSwitchPackage: (newIndex) {
                              _switchPackage(newIndex);
                            },
                            onManageSubscription: () {
                              Navigator.pop(context); // Pop therapist details screen
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => const ParentSubscriptionsHistoryScreen(),
                                ),
                              );
                            },
                          ),
                        const SizedBox(height: 12),
                        if (visiblePackages.isNotEmpty && selectedPackage != null) ...[
                          const SizedBox(height: 12),
                          if (_isSubscribed) ...[
                            const Center(
                              child: Text(
                                'You already have an active subscription',
                                style: TextStyle(color: Colors.white),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Center(
                              child: TextButton(
                                onPressed: widget.chatEnabled
                                    ? () => widget.onOpenMessages()
                                    : () {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text('Coming soon'),
                                          ),
                                        );
                                      },
                                style: TextButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  textStyle: const TextStyle(
                                    fontSize: 12,
                                    decoration: TextDecoration.underline,
                                  ),
                                ),
                                child: const Text(
                                  'Go to Messages to start chatting',
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton(
                                onPressed: widget.paymentsEnabled
                                    ? () async {
                                        final success = await widget.onCancelSubscription();
                                        if (!context.mounted) {
                                           return;
                                         }
                                         if (success) {
                                           if (context.mounted) {
                                             Navigator.pop(context);
                                           }
                                         }
                                      }
                                    : () {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text('Coming soon'),
                                          ),
                                        );
                                      },
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  side: const BorderSide(
                                    color: Colors.white,
                                    width: 1.2,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 11,
                                  ),
                                ),
                                child: const Text('Cancel Subscription'),
                              ),
                            ),
                          ] else
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: _isSubscribing || therapist.isAcceptingClients == false
                                    ? null
                                    : (widget.paymentsEnabled
                                          ? (_isRestricted
                                              ? () {
                                                  final isTherapistRestricted = therapist.moderationStatus == 'restricted';
                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                    SnackBar(
                                                      content: Text(isTherapistRestricted
                                                          ? "Therapist's account is restricted, so you cannot switch or buy another package."
                                                          : 'Your account is restricted. You cannot switch or buy another package.'),
                                                      backgroundColor: const Color(0xFFEF4444),
                                                    ),
                                                  );
                                                }
                                              : _subscribe)
                                          : () {
                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                const SnackBar(
                                                  content: Text('Coming soon'),
                                                ),
                                              );
                                            }),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: const Color(0xFF00A63E),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 13,
                                  ),
                                ),
                                child: _isSubscribing
                                    ? const SizedBox(
                                        height: 16,
                                        width: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Color(0xFF00A63E),
                                        ),
                                      )
                                    : Text(
                                        therapist.isAcceptingClients == false
                                            ? 'Subscriptions Disabled (Busy)'
                                            : 'Subscribe ${selectedPackage.priceLabel}/month',
                                      ),
                              ),
                            ),
                          const SizedBox(height: 10),
                          Text(
                            widget.paymentsEnabled
                                ? 'Secure payment powered by SafePay. Cancel your subscription anytime from your account settings.'
                                : 'Coming soon',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF6B7280),
                            ),
                          ),
                        ],
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
    if (_isSwitching)
      Positioned.fill(
        child: Container(
          color: Colors.black.withValues(alpha: 0.5),
          child: const Center(
            child: CircularProgressIndicator(
              color: Color(0xFF00C853),
            ),
          ),
        ),
      ),
    ],
  );
}
}

class _PackageSelectionList extends StatelessWidget {
  const _PackageSelectionList({
    required this.packages,
    required this.currentIndex,
    required this.onPackageSelected,
    this.subscribedPackageIndex,
    required this.isSubscribed,
    required this.onSwitchPackage,
    required this.onManageSubscription,
    required this.isRestricted,
    required this.isTherapistRestricted,
  });

  final List<_SupportServicePackage> packages;
  final int currentIndex;
  final ValueChanged<int> onPackageSelected;
  final int? subscribedPackageIndex;
  final bool isSubscribed;
  final ValueChanged<int> onSwitchPackage;
  final VoidCallback onManageSubscription;
  final bool isRestricted;
  final bool isTherapistRestricted;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (int i = 0; i < packages.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _PackageListItem(
              package: packages[i],
              isSelected: isSubscribed
                  ? (subscribedPackageIndex == i)
                  : (i == currentIndex),
              isLocked: isSubscribed && subscribedPackageIndex != null && (subscribedPackageIndex != i),
              onTap: () {
                if (isRestricted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(isTherapistRestricted
                          ? "Therapist's account is restricted, so you cannot switch or buy another package."
                          : 'Your account is restricted. You cannot switch or buy another package.'),
                      backgroundColor: const Color(0xFFEF4444),
                    ),
                  );
                  return;
                }
                if (isSubscribed && subscribedPackageIndex != null && (subscribedPackageIndex != i)) {
                  showDialog<void>(
                    context: context,
                    builder: (BuildContext ctx) {
                      return AlertDialog(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        title: const Row(
                          children: [
                            Icon(Icons.swap_horiz, color: Colors.orange, size: 24),
                            SizedBox(width: 8),
                            Text('Switch Package?', style: TextStyle(fontWeight: FontWeight.bold)),
                          ],
                        ),
                        content: const Text(
                          'You already have an active subscription to one of this therapist\'s packages. '
                          'Would you like to switch to this package? This will cancel your existing subscription and start checkout for the new package.',
                          style: TextStyle(fontSize: 14),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () {
                              Navigator.pop(ctx);
                              onManageSubscription();
                            },
                            child: const Text('Manage Active Subscription', style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
                          ),
                          ElevatedButton(
                            onPressed: () {
                              Navigator.pop(ctx);
                              onSwitchPackage(i);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF00C853),
                            ),
                            child: const Text('Switch Plan', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      );
                    },
                  );
                } else if (!isSubscribed) {
                  onPackageSelected(i);
                }
              },
            ),
          ),
      ],
    );
  }
}

class _PackageListItem extends StatelessWidget {
  const _PackageListItem({
    required this.package,
    required this.isSelected,
    required this.onTap,
    this.isLocked = false,
  });

  final _SupportServicePackage package;
  final bool isSelected;
  final VoidCallback onTap;
  final bool isLocked;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        decoration: BoxDecoration(
          color: isLocked
              ? const Color(0xFF81C784)
              : (isSelected
                  ? Colors.white.withValues(alpha: 0.15)
                  : const Color(0xFF3ACB6D)),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.3),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    package.title,
                    style: TextStyle(
                      color: isLocked ? Colors.white70 : Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      decoration: isLocked ? TextDecoration.lineThrough : null,
                    ),
                  ),
                ),
                if (isSelected)
                  const Icon(Icons.check_circle, color: Colors.white, size: 20)
                else if (isLocked)
                  const Icon(Icons.lock_outline, color: Colors.white70, size: 20),
              ],
            ),
            const SizedBox(height: 4),
            RichText(
              text: TextSpan(
                text: package.priceLabel,
                style: TextStyle(
                  color: isLocked ? Colors.white70 : Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
                children: [
                  TextSpan(
                    text: '/month',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                      color: isLocked ? Colors.white70 : Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            _FeatureLine(
              text:
                  '${package.durationMinutes} min/session • ${package.sessionsPerWeek} sessions/week',
            ),
            if (package.description.trim().isNotEmpty)
              _FeatureLine(text: package.description.trim()),
          ],
        ),
      ),
    );
  }
}

class _SupportServicePackage {
  const _SupportServicePackage({
    required this.title,
    required this.durationMinutes,
    required this.sessionsPerWeek,
    required this.price,
    required this.description,
    required this.visible,
  });

  final String title;
  final int durationMinutes;
  final int sessionsPerWeek;
  final double price;
  final String description;
  final bool visible;

  String get priceLabel => formatPrice(price);

  factory _SupportServicePackage.fromMap(Map<String, dynamic> data) {
    final rawPrice = data['price'];
    final parsedPrice = rawPrice is num
        ? rawPrice.toDouble()
        : double.tryParse(rawPrice?.toString() ?? '') ?? 49.99;
    return _SupportServicePackage(
      title: (data['title'] ?? 'Therapy Package').toString(),
      durationMinutes: intFrom(data['durationMinutes'], 60),
      sessionsPerWeek: intFrom(data['sessionsPerWeek'], 3),
      price: parsedPrice,
      description: (data['description'] ?? '').toString(),
      visible: data['visible'] != false,
    );
  }
}

class _DemoTherapistChatScreen extends StatefulWidget {
  const _DemoTherapistChatScreen({
    required this.therapist,
    required this.onCancelSubscription,
  });

  final TherapistProfile therapist;
  final Future<void> Function() onCancelSubscription;

  @override
  State<_DemoTherapistChatScreen> createState() =>
      _DemoTherapistChatScreenState();
}

class _DemoTherapistChatScreenState extends State<_DemoTherapistChatScreen> {
  late final List<_DemoChatMessage> _messages = <_DemoChatMessage>[
    const _DemoChatMessage(
      text: 'Hello! How can I help you today?',
      time: '10:30 AM',
      isMine: false,
    ),
    const _DemoChatMessage(
      text: "Hi! I wanted to discuss my child\\'s progress this week.",
      time: '10:32 AM',
      isMine: true,
    ),
    const _DemoChatMessage(
      text:
          "Of course! I've noticed great improvement in social interactions. Your child has been participating more actively in group activities.",
      time: '10:35 AM',
      isMine: false,
    ),
    const _DemoChatMessage(
      text: "That\\'s wonderful to hear! Any areas we should focus on?",
      time: '10:37 AM',
      isMine: true,
    ),
    const _DemoChatMessage(
      text:
          "I\\'d recommend continuing with the communication exercises at home. The daily practice is showing excellent results!",
      time: '10:40 AM',
      isMine: false,
    ),
  ];

  bool _emergencyActive = true;

  List<String> _specializations(TherapistProfile profile) {
    return profile.specializations
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
  }

  int _yearsExp(TherapistProfile profile) {
    if (profile.yearsOfExperience > 0) {
      return profile.yearsOfExperience;
    }
    final source = '${profile.availability} ${profile.bio}';
    final match = RegExp(r'(\d{1,2})\s*\+?\s*years?').firstMatch(source);
    if (match != null) {
      return int.tryParse(match.group(1) ?? '') ?? 8;
    }
    return 0;
  }

  String _specialization(TherapistProfile profile) {
    final specs = _specializations(profile);
    if (specs.isNotEmpty) {
      return specs.first;
    }
    return 'Specialization not set';
  }

  Future<void> _showTherapistProfileSheet() async {
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black54,
      builder: (context) {
        final therapist = widget.therapist;
        final years = _yearsExp(therapist);
        final yearsText = years > 0
            ? '$years years of practice'
            : 'Experience not set';
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 24,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          child: Container(
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(18)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                  decoration: const BoxDecoration(
                    color: Color(0xFF00C853),
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(18),
                    ),
                  ),
                  child: Stack(
                    children: [
                      Align(
                        child: Column(
                          children: [
                            _TherapistPlaceholderAvatar(
                              size: 70,
                              backgroundColor: const Color(0xFF3ACB6D),
                              padding: 5,
                              photoBase64: therapist.photoUrlBase64.isNotEmpty
                                  ? therapist.photoUrlBase64
                                  : therapist.photoUrl,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              therapist.displayName,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 29 / 1.6,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _specialization(therapist),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Positioned(
                        right: 0,
                        top: 0,
                        child: IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close, color: Colors.white),
                          style: IconButton.styleFrom(
                            backgroundColor: const Color(0x334B5563),
                            minimumSize: const Size(32, 32),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Hardcoded rating/reviews removed for now.
                      const SizedBox(height: 12),
                      const Divider(height: 1),
                      const SizedBox(height: 10),
                      Text(
                        'Experience\n$yearsText',
                        style: const TextStyle(height: 1.4),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Certifications\n${therapist.credentials.trim().isEmpty ? 'No certifications listed' : therapist.credentials.trim()}',
                        style: const TextStyle(height: 1.4),
                      ),
                      const SizedBox(height: 10),
                      const Divider(height: 1),
                      const SizedBox(height: 10),
                      const Text(
                        'About',
                        style: TextStyle(
                          color: Color(0xFF4B5563),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        therapist.bio.trim().isEmpty
                            ? 'Bio not provided'
                            : therapist.bio,
                        style: const TextStyle(height: 1.4),
                      ),
                      const SizedBox(height: 10),
                      const Center(
                        child: Text(
                          '- Active now',
                          style: TextStyle(color: Color(0xFF00A63E)),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _confirmCancelSubscription,
                          icon: const Icon(Icons.cancel_outlined),
                          label: const Text('Cancel Subscription'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFF3040),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 13),
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
      },
    );
  }

  Future<void> _confirmCancelSubscription() async {
    final therapist = widget.therapist;
    // 1. Show the Warning Dialog
    final cancelReason = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return CancelSubscriptionDialog(
          therapistName: therapist.displayName,
          onConfirmCancel: (reason) => Navigator.pop(dialogCtx, reason),
        );
      },
    );

    if (cancelReason == null) return;

    // 2. Show the Chat History Choices Dialog
    if (!mounted) return;
    final choice = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return ChatHistoryChoicesDialog(
          therapistId: therapist.id,
          cancellationReason: cancelReason,
          onComplete: (choice) {
            // Handled inside choices dialog State
          },
        );
      },
    );

    if (choice == null) return;

    await widget.onCancelSubscription();
    if (!mounted) {
      return;
    }
    Navigator.pop(context); // close profile dialog
    Navigator.pop(context); // close chat and return to messages home
  }

  void _endEmergency() {
    if (!_emergencyActive) {
      return;
    }
    setState(() {
      _emergencyActive = false;
      _messages.add(
        const _DemoChatMessage(
          text: 'Emergency has been resolved. Thank you.',
          time: '6:28 PM',
          isMine: false,
        ),
      );
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Emergency ended successfully.'),
        backgroundColor: Color(0xFF00C853),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final therapist = widget.therapist;
    return Scaffold(
      backgroundColor: const Color(0xFFEFF4F1),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              color: const Color(0xFFBDF1D0),
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(
                      Icons.arrow_back,
                      color: Color(0xFF374151),
                    ),
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFFF1F5F3),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _showTherapistProfileSheet,
                    child: Row(
                      children: [
                        _TherapistPlaceholderAvatar(
                          size: 38,
                          backgroundColor: const Color(0xFF00C853),
                          padding: 3,
                          photoBase64: therapist.photoUrlBase64.isNotEmpty
                              ? therapist.photoUrlBase64
                              : therapist.photoUrl,
                        ),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              therapist.displayName,
                              style: const TextStyle(
                                fontSize: 18 / 1.2,
                                color: Color(0xFF1F2937),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            Text(
                              _specialization(therapist),
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF4B5563),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Container(
                    width: 9,
                    height: 9,
                    decoration: const BoxDecoration(
                      color: Color(0xFF00C853),
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  final message = _messages[index];
                  return Align(
                    alignment: message.isMine
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.74,
                      ),
                      decoration: BoxDecoration(
                        color: message.isMine
                            ? const Color(0xFF00C853)
                            : const Color(0xFFE5E7EB),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            message.text,
                            style: TextStyle(
                              color: message.isMine
                                  ? Colors.white
                                  : const Color(0xFF374151),
                              height: 1.35,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            message.time,
                            style: TextStyle(
                              fontSize: 11,
                              color: message.isMine
                                  ? Colors.white70
                                  : const Color(0xFF6B7280),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            if (_emergencyActive)
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _endEmergency,
                      icon: const Icon(Icons.warning_amber_rounded),
                      label: const Text('End Emergency'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF3040),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DemoChatMessage {
  const _DemoChatMessage({
    required this.text,
    required this.time,
    required this.isMine,
  });

  final String text;
  final String time;
  final bool isMine;
}

class ParentSubscriptionsHistoryScreen extends StatefulWidget {
  const ParentSubscriptionsHistoryScreen({super.key});

  @override
  State<ParentSubscriptionsHistoryScreen> createState() =>
      _ParentSubscriptionsHistoryScreenState();
}

class _ParentSubscriptionsHistoryScreenState
    extends State<ParentSubscriptionsHistoryScreen> {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  Future<List<Map<String, dynamic>>> _loadSubscriptionsWithTherapists() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) {
      return [];
    }
    final snapshot = await _firestore
        .collection(FirestoreCollections.subscriptions)
        .where('userId', isEqualTo: uid)
        .get();

    final list = <Map<String, dynamic>>[];
    for (final doc in snapshot.docs) {
      final subData = doc.data();
      final therapistId = subData['therapistId']?.toString() ?? '';
      TherapistProfile? therapist;
      if (therapistId.isNotEmpty) {
        try {
          therapist = await AppRepositories.support.getTherapistById(therapistId);
        } catch (_) {}
      }
      list.add({
        'subscription': UserSubscription.fromMap(doc.id, subData),
        'therapist': therapist,
      });
    }
    return list;
  }

  Future<void> _cancelSubscription(TherapistProfile therapist) async {
    // 1. Show the Warning Dialog
    final cancelReason = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return CancelSubscriptionDialog(
          therapistName: therapist.displayName,
          onConfirmCancel: (reason) => Navigator.pop(dialogCtx, reason),
        );
      },
    );

    if (cancelReason == null) return;

    // 2. Show the Chat History Choices Dialog
    if (!mounted) return;
    final choice = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return ChatHistoryChoicesDialog(
          therapistId: therapist.id,
          cancellationReason: cancelReason,
          onComplete: (choice) {
            // Handled inside choices dialog State
          },
        );
      },
    );

    if (choice == null) return;

    // 3. Post-Cancellation Updates
    if (mounted) {
      // Modify static sets so the changes reflect immediately in parent home
      ProfessionalSupportScreen.sessionSubscribedTherapistIds.remove(therapist.id);
      if (choice == 'delete') {
        ProfessionalSupportScreen.sessionHiddenTherapistIds.add(therapist.id);
      }
      
      // Persist therapist state for current user
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        try {
          await FirebaseFirestore.instance
              .collection(FirestoreCollections.users)
              .doc(uid)
              .set({
            'proSupportSubscribedTherapistIds': ProfessionalSupportScreen.sessionSubscribedTherapistIds.toList(),
            'proSupportHiddenTherapistIds': ProfessionalSupportScreen.sessionHiddenTherapistIds.toList(),
            'proSupportUpdatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        } catch (_) {}
      }

      if (!mounted) return;
      setState(() {}); // Reload history screen list
      
      final messenger = ScaffoldMessenger.of(context);
      if (choice == 'delete') {
        messenger.showSnackBar(
          SnackBar(
            content: Text('Subscription cancelled and chat history deleted.'),
            backgroundColor: AppColors.errorRed,
          ),
        );
      } else {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Subscription cancelled. Chat locked to read-only.'),
            backgroundColor: Color(0xFF3B82F6),
          ),
        );
      }

      _showReviewDialog(context, therapist);
    }
  }

  void _showReviewDialog(BuildContext context, TherapistProfile therapist) {
    int selectedRating = 5;
    final publicController = TextEditingController();
    final privateController = TextEditingController();
    final List<String> lowRatingOptions = const [
      'Poor communication',
      'Unhelpful advice',
      'Slow response times',
      'Lack of empathy',
      'Technical issues',
    ];
    final Set<String> selectedReasons = <String>{};

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Text(
                'Rate & Review\n${therapist.displayName}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1F2937),
                ),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'How was your experience with this therapist?',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, color: Color(0xFF4B5563)),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(5, (index) {
                        final starValue = index + 1;
                        return IconButton(
                          onPressed: () {
                            setDialogState(() {
                              selectedRating = starValue;
                            });
                          },
                          icon: Icon(
                            starValue <= selectedRating
                                ? Icons.star
                                : Icons.star_border,
                            color: Colors.amber,
                            size: 32,
                          ),
                        );
                      }),
                    ),
                    if (selectedRating <= 2) ...[
                      const SizedBox(height: 16),
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'What went wrong? (Select all that apply)',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF374151),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...lowRatingOptions.map((option) {
                        final isChecked = selectedReasons.contains(option);
                        return CheckboxListTile(
                          title: Text(option, style: const TextStyle(fontSize: 13)),
                          value: isChecked,
                          dense: true,
                          controlAffinity: ListTileControlAffinity.leading,
                          contentPadding: EdgeInsets.zero,
                          activeColor: const Color(0xFF00C853),
                          onChanged: (val) {
                            setDialogState(() {
                              if (val == true) {
                                selectedReasons.add(option);
                              } else {
                                selectedReasons.remove(option);
                              }
                            });
                          },
                        );
                      }),
                    ],
                    const SizedBox(height: 16),
                    TextField(
                      controller: publicController,
                      maxLines: 3,
                      maxLength: 300,
                      buildCounter: (context, {required currentLength, required maxLength, required isFocused}) {
                        return Text(
                          '$currentLength/$maxLength',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF6B7280),
                          ),
                        );
                      },
                      decoration: InputDecoration(
                        labelText: 'Written Feedback (Optional)',
                        hintText: 'Share your experience with other parents...',
                        alignLabelWithHint: true,
                        contentPadding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: privateController,
                      maxLines: 2,
                      maxLength: 300,
                      buildCounter: (context, {required currentLength, required maxLength, required isFocused}) {
                        return Text(
                          '$currentLength/$maxLength',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF6B7280),
                          ),
                        );
                      },
                      decoration: InputDecoration(
                        labelText: 'Private Notes (Optional)',
                        hintText: 'Feedback visible only to admin/platform...',
                        alignLabelWithHint: true,
                        contentPadding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Maybe Later', style: TextStyle(color: Color(0xFF6B7280))),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (publicController.text.trim().length > 300 ||
                        privateController.text.trim().length > 300) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Review feedback must not exceed 300 characters.'),
                          backgroundColor: Color(0xFFEF4444),
                        ),
                      );
                      return;
                    }
                    try {
                      await AppRepositories.support.submitReview(
                        therapistId: therapist.id,
                        rating: selectedRating,
                        feedback: publicController.text.trim(),
                        privateFeedback: privateController.text.trim(),
                        lowRatingReasons: selectedRating <= 2 ? selectedReasons.toList() : const [],
                      );
                      if (ctx.mounted) {
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(
                            content: Text('Thank you! Your review has been submitted.'),
                            backgroundColor: Color(0xFF00C853),
                          ),
                        );
                      }
                    } catch (e) {
                      if (ctx.mounted) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(
                            content: Text('Failed to submit review: $e'),
                            backgroundColor: AppColors.errorRed,
                          ),
                        );
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00C853),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text('Submit'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _reactivateSubscription(TherapistProfile therapist) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return const PopScope(
          canPop: false,
          child: AlertDialog(
            content: Row(
              children: [
                CircularProgressIndicator(color: Color(0xFF00C853)),
                SizedBox(width: 20),
                Expanded(
                  child: Text(
                    'Reactivating subscription...',
                    style: TextStyle(fontSize: 14),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    try {
      await AppRepositories.billing.reactivateSubscriptionInStore(therapist.id);
      if (mounted) {
        Navigator.pop(context); // Close loading dialog
        setState(() {}); // Re-load
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Subscription reactivated successfully.'),
            backgroundColor: Color(0xFF00C853),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Close loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to reactivate subscription: $e'),
            backgroundColor: AppColors.errorRed,
          ),
        );
      }
    }
  }

  Widget _buildSubscriptionCard(Map<String, dynamic> item) {
    final UserSubscription sub = item['subscription'] as UserSubscription;
    final TherapistProfile? therapist = item['therapist'] as TherapistProfile?;

    if (therapist == null) {
      return const SizedBox.shrink();
    }

    final visiblePackages = therapist.servicePackages.where((p) => p.visible).toList();
    TherapyPackage? selectedPackage;
    if (sub.productId.startsWith('auto_${therapist.id}_')) {
      final parts = sub.productId.split('_');
      if (parts.length >= 3) {
        final idx = int.tryParse(parts.last) ?? 0;
        if (idx >= 0 && idx < visiblePackages.length) {
          selectedPackage = visiblePackages[idx];
        }
      }
    }

    if (selectedPackage == null && visiblePackages.isNotEmpty) {
      selectedPackage = visiblePackages.first;
    }

    final priceLabel = selectedPackage != null
        ? '${formatPrice(selectedPackage.price)}/month'
        : (therapist.pricing.isNotEmpty 
            ? formatPriceString(therapist.pricing) 
            : 'Rs. 4,999 PKR/month');

    Color statusColor;
    String statusText;
    if (sub.status == 'active') {
      statusColor = sub.cancelAtPeriodEnd ? Colors.red : const Color(0xFF00C853);
      statusText = sub.cancelAtPeriodEnd ? 'Canceled' : 'Active';
    } else if (sub.status == 'grace_period') {
      statusColor = const Color(0xFFF08C00);
      statusText = 'Grace Period';
    } else if (sub.status == 'pending') {
      statusColor = Colors.orange;
      statusText = 'Pending Verification';
    } else if (sub.status == 'payment_failed') {
      statusColor = Colors.redAccent;
      statusText = 'Payment Failed';
    } else {
      statusColor = Colors.red;
      statusText = sub.status.toUpperCase();
    }

    final dateStr = sub.currentPeriodEnd != null
        ? '${sub.currentPeriodEnd!.day}/${sub.currentPeriodEnd!.month}/${sub.currentPeriodEnd!.year}'
        : 'N/A';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
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
        border: Border.all(color: const Color(0xFFF1F5F9), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _TherapistPlaceholderAvatar(
                size: 44,
                photoBase64: therapist.photoUrlBase64.isNotEmpty ? therapist.photoUrlBase64 : therapist.photoUrl,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      therapist.displayName,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1E293B)),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      therapist.specializations.isNotEmpty ? therapist.specializations.first : 'Therapist',
                      style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  statusText,
                  style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 11),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Price: $priceLabel',
                style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF475569), fontSize: 13),
              ),
              Text(
                'Expiry: $dateStr',
                style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
              ),
            ],
          ),
          if (sub.isActive) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: sub.cancelAtPeriodEnd
                      ? ElevatedButton.icon(
                          onPressed: () => _reactivateSubscription(therapist),
                          icon: const Icon(Icons.refresh_rounded, size: 14),
                          label: const Text('Reactivate', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00C853),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        )
                      : OutlinedButton.icon(
                          onPressed: () => _cancelSubscription(therapist),
                          icon: const Icon(Icons.cancel_outlined, size: 14),
                          label: const Text('Cancel Subscription', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            side: const BorderSide(color: Color(0xFFFCA5A5)),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                ),
              ],
            ),
          ],
          if (sub.status == 'grace_period') ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF9DB),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFFEC99)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Color(0xFFF08C00), size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Your renewal failed. You have a 24-hour grace period to retry payment before your subscription expires.',
                      style: TextStyle(color: Color(0xFFE67700), fontSize: 12, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (sub.status == 'pending' || sub.status == 'payment_failed') ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () async {
                      showDialog<void>(
                        context: context,
                        barrierDismissible: false,
                        builder: (BuildContext context) {
                          return const PopScope(
                            canPop: false,
                            child: AlertDialog(
                              content: Row(
                                children: [
                                  CircularProgressIndicator(color: Color(0xFF00C853)),
                                  SizedBox(width: 20),
                                  Expanded(
                                    child: Text(
                                      'Reconciling payment status. Please wait...',
                                      style: TextStyle(fontSize: 13),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                      try {
                        await AppRepositories.billing.syncSubscriptionStatus(therapist.id);
                        final latest = await AppRepositories.billing.getSubscriptionForTherapist(therapist.id);
                        bool cleanedUp = false;
                        if (latest == null || !latest.isActive) {
                          await AppRepositories.billing.deletePendingSubscription(therapist.id);
                          cleanedUp = true;
                        }
                        if (mounted) {
                          Navigator.pop(context); // Close loading dialog
                          setState(() {}); // Reload history screen
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(cleanedUp
                                  ? 'No completed payment found. Cleaned up pending request.'
                                  : 'Payment verified and subscription activated!'),
                              backgroundColor: cleanedUp ? const Color(0xFF64748B) : const Color(0xFF00C853),
                            ),
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Verification update: $e'),
                              backgroundColor: AppColors.errorRed,
                            ),
                          );
                        }
                      }
                    },
                    icon: const Icon(Icons.sync_rounded, size: 14),
                    label: const Text('Refresh Payment Status', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0284C7),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  void _showReceiptModal(BuildContext context, Map<String, dynamic> txn) {
    final grossAmount = double.tryParse((txn['grossAmount'] ?? 0.0).toString()) ?? 0.0;
    final platformFee = double.tryParse((txn['platformFee'] ?? 0.0).toString()) ?? 0.0;
    final safepayFee = double.tryParse((txn['safepayFee'] ?? 0.0).toString()) ?? 0.0;
    final netAmount = double.tryParse((txn['netAmount'] ?? txn['amount'] ?? 0.0).toString()) ?? 0.0;
    final displayAmount = grossAmount > 0 ? grossAmount : netAmount;
    final amountStr = formatPrice(displayAmount);

    final date = dateTimeFromFirestore(txn['createdAt']) ?? DateTime.now();
    final dateStr = '${date.day}/${date.month}/${date.year} at ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    final hasBreakdown = grossAmount > 0 && (platformFee > 0 || safepayFee > 0);

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
                decoration: const BoxDecoration(
                  color: Color(0xFFE0F2FE),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Center(
                  child: Column(
                    children: [
                      const Icon(Icons.receipt_long_rounded, color: Color(0xFF0284C7), size: 48),
                      const SizedBox(height: 10),
                      const Text(
                        'Payment Receipt',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F172A)),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        amountStr,
                        style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Color(0xFF0284C7)),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    _buildModalDetailRow('Status', 'SUCCESSFUL', valueColor: const Color(0xFF00C853), isBoldValue: true),
                    const Divider(),
                    _buildModalDetailRow('Payment Date', dateStr),
                    const Divider(),
                    _buildModalDetailRow('Payment Provider', 'SafePay Pakistan'),
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
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionRow(Map<String, dynamic> txn) {
    final grossAmount = double.tryParse((txn['grossAmount'] ?? 0.0).toString()) ?? 0.0;
    final netAmount = double.tryParse((txn['netAmount'] ?? txn['amount'] ?? 0.0).toString()) ?? 0.0;
    final displayAmount = grossAmount > 0 ? grossAmount : netAmount;
    final amountStr = formatPrice(displayAmount);
    final date = dateTimeFromFirestore(txn['createdAt']) ?? DateTime.now();
    final dateStr = '${date.day}/${date.month}/${date.year}';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _showReceiptModal(context, txn),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
          child: Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: const Color(0xFFE0F2FE),
                child: const Icon(
                  Icons.receipt_long_rounded,
                  size: 16,
                  color: Color(0xFF0284C7),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Subscription Payment',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E293B)),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      dateStr,
                      style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    amountStr,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E293B)),
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    'Paid',
                    style: TextStyle(color: Color(0xFF00C853), fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F3),
      appBar: AppBar(
        backgroundColor: const Color(0xFFBDF1D0),
        elevation: 0,
        title: const Text(
          'Billing & Subscriptions',
          style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E293B), fontSize: 18),
        ),
        iconTheme: const IconThemeData(color: Color(0xFF1E293B)),
      ),
      body: FutureBuilder<List<Map<String, dynamic>>>(
        future: _loadSubscriptionsWithTherapists(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Color(0xFF00C853)));
          }

          final list = snapshot.data ?? [];
          final displayList = list.where((item) {
            final UserSubscription sub = item['subscription'] as UserSubscription;
            return sub.isActive || sub.status == 'pending' || sub.status == 'payment_failed';
          }).toList();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'My Subscriptions',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1E293B)),
              ),
              const SizedBox(height: 10),
              if (displayList.isEmpty)
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Center(
                    child: Text(
                      'No subscriptions found.',
                      style: TextStyle(color: Color(0xFF64748B), fontSize: 14),
                    ),
                  ),
                )
              else
                ...displayList.map(_buildSubscriptionCard),
              const SizedBox(height: 24),
              const Text(
                'Payment History',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1E293B)),
              ),
              const SizedBox(height: 10),
              FutureBuilder<List<Map<String, dynamic>>>(
                future: AppRepositories.billing.getParentTransactions(),
                builder: (context, txnSnapshot) {
                  if (txnSnapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator(color: Color(0xFF00C853)));
                  }
                  final txns = txnSnapshot.data ?? [];
                  if (txns.isEmpty) {
                    return Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Center(
                        child: Text(
                          'No payment history found.',
                          style: TextStyle(color: Color(0xFF64748B), fontSize: 14),
                        ),
                      ),
                    );
                  }
                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: txns.map(_buildTransactionRow).toList(),
                    ),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SupportDetailCard extends StatelessWidget {
  const _SupportDetailCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({
    required this.icon,
    required this.title,
    required this.value,
  });

  final IconData icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: const Color(0xFF00A63E)),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 12.5,
                  color: Color(0xFF6B7280),
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14.5,
                  color: Color(0xFF1F2937),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FeatureLine extends StatelessWidget {
  const _FeatureLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          const Icon(Icons.check, color: Colors.white, size: 15),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: Colors.white, fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _SupportTherapistReviewsSection extends StatelessWidget {
  const _SupportTherapistReviewsSection({required this.therapistId});

  final String therapistId;

  Widget _buildBreakdownRow(int star, int count, int total) {
    final percentage = total > 0 ? count / total : 0.0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        children: [
          Text(
            '$star ★',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Color(0xFF4B5563),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: percentage,
                backgroundColor: const Color(0xFFE5E7EB),
                color: Colors.amber,
                minHeight: 8,
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 24,
            child: Text(
              '$count',
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<TherapistReview>>(
      stream: AppRepositories.support.watchReviewsForTherapist(therapistId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const _SupportDetailCard(
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
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

        return _SupportDetailCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Ratings & Reviews',
                style: TextStyle(
                  fontSize: 16,
                  color: Color(0xFF1F2937),
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 14),
              if (totalReviews == 0)
                const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      'No reviews yet. Be the first to leave a review!',
                      style: TextStyle(color: Color(0xFF6B7280), fontStyle: FontStyle.italic),
                    ),
                  ),
                )
              else ...[
                Row(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          averageRating.toStringAsFixed(1),
                          style: const TextStyle(
                            fontSize: 36,
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
                              size: 16,
                            );
                          }),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$totalReviews ${totalReviews == 1 ? "Review" : "Reviews"}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF6B7280),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 24),
                    Expanded(
                      child: Column(
                        children: [
                          for (int i = 5; i >= 1; i--)
                            _buildBreakdownRow(
                              i,
                              breakdown[i.toString()] ?? 0,
                              totalReviews,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: reviews.length,
                  separatorBuilder: (context, index) => const Divider(height: 16),
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
                                fontSize: 13,
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
                                  size: 14,
                                );
                              }),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          review.feedback.trim().isEmpty
                              ? 'No written feedback provided.'
                              : review.feedback,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF4B5563),
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _formatDate(review.createdAt),
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF9CA3AF),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}
