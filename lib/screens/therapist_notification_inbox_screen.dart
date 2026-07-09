import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/app_models.dart';
import '../repositories/app_repositories.dart';
import '../widgets/figma_module_scaffold.dart';
import '../widgets/session_guard.dart';
import 'therapist_home_screen.dart';
import 'therapist_chat_screen.dart';

class TherapistNotificationInboxScreen extends StatefulWidget {
  const TherapistNotificationInboxScreen({
    super.key,
    required this.initialPrefs,
  });

  final Map<String, bool> initialPrefs;

  @override
  State<TherapistNotificationInboxScreen> createState() =>
      _TherapistNotificationInboxScreenState();
}

class _TherapistNotificationInboxScreenState
    extends State<TherapistNotificationInboxScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final List<String> _tabs = [
    'All',
    'Messages',
    'Subscriptions',
    'Activities',
    'System',
    'Reports'
  ];

  late Map<String, bool> _currentPrefs;


  static const Map<String, bool> _defaultTherapistNotificationPrefs = <String, bool>{
    'newMessages': false,
    'bookings': false,
    'payments': false,
    'emergency': true,
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _currentPrefs = Map<String, bool>.from(widget.initialPrefs);
    // Auto-generate session reminder and completion notifications
    _checkAndGenerateSessionNotifications();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String _formatRelativeTime(DateTime timestamp) {
    final diff = DateTime.now().difference(timestamp);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    return '${timestamp.day}/${timestamp.month}/${timestamp.year}';
  }

  IconData _getCategoryIcon(String category) {
    switch (category) {
      case 'messages':
        return Icons.chat_bubble_rounded;
      case 'subscription':
        return Icons.credit_card_rounded;
      case 'reviews':
        return Icons.star_rounded;
      case 'activities':
        return Icons.today_rounded;
      case 'progress':
        return Icons.emoji_events_rounded;
      case 'verification':
        return Icons.verified_user_rounded;
      case 'reports':
        return Icons.flag_rounded;
      case 'system':
      default:
        return Icons.notifications_active_rounded;
    }
  }

  Color _getCategoryColor(String category) {
    switch (category) {
      case 'messages':
        return const Color(0xFF2563EB); // blue 600
      case 'subscription':
        return const Color(0xFF10B981); // emerald 500
      case 'reviews':
        return const Color(0xFFF59E0B); // amber 500
      case 'activities':
        return const Color(0xFF8B5CF6); // purple 500
      case 'progress':
        return const Color(0xFFD97706); // amber 600
      case 'verification':
        return const Color(0xFF06B6D4); // cyan 500
      case 'reports':
        return const Color(0xFFEF4444); // red 500
      case 'system':
      default:
        return const Color(0xFF64748B); // slate 500
    }
  }

  /// Auto-generates in-app activity notifications for upcoming session reminders
  /// (30 minutes before) and session completions (slots that have passed).
  Future<void> _checkAndGenerateSessionNotifications() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final now = DateTime.now();
      final slotsSnap = await FirebaseFirestore.instance
          .collection(FirestoreCollections.appointmentSlots)
          .where('therapistId', isEqualTo: uid)
          .where('status', isEqualTo: 'booked')
          .get();

      for (final slotDoc in slotsSnap.docs) {
        final data = slotDoc.data();
        final tsRaw = data['dateTime'];
        if (tsRaw == null) continue;
        final sessionDt = (tsRaw as Timestamp).toDate().toLocal();
        final parentName = (data['bookedForChildName']?.toString() ?? '').isNotEmpty
            ? data['bookedForChildName'].toString()
            : 'A parent';

        final minutesUntil = sessionDt.difference(now).inMinutes;

        if (minutesUntil > 0 && minutesUntil <= 30) {
          // Upcoming in ≤30 minutes — send reminder if not already sent
          final existingReminder = await FirebaseFirestore.instance
              .collection('notifications')
              .where('userId', isEqualTo: uid)
              .where('navigationTarget.slotId', isEqualTo: slotDoc.id)
              .where('title', isEqualTo: '⏰ Session Reminder')
              .limit(1)
              .get();
          if (existingReminder.docs.isEmpty) {
            await FirebaseFirestore.instance.collection('notifications').add({
              'userId': uid,
              'title': '\u23f0 Session Reminder',
              'message': 'Reminder: You have a therapy session with $parentName in $minutesUntil minutes.',
              'category': 'activities',
              'timestamp': FieldValue.serverTimestamp(),
              'isRead': false,
              'navigationTarget': {
                'route': 'TherapistScheduler',
                'slotId': slotDoc.id,
              },
            });
          }
        } else if (minutesUntil <= 0) {
          // Session time has passed — mark as completed and notify if not already done
          final existingCompletion = await FirebaseFirestore.instance
              .collection('notifications')
              .where('userId', isEqualTo: uid)
              .where('navigationTarget.slotId', isEqualTo: slotDoc.id)
              .where('title', isEqualTo: '✅ Session Completed')
              .limit(1)
              .get();
          if (existingCompletion.docs.isEmpty) {
            await FirebaseFirestore.instance.collection('notifications').add({
              'userId': uid,
              'title': '✅ Session Completed',
              'message': 'Your session with $parentName has been marked as completed.',
              'category': 'activities',
              'timestamp': FieldValue.serverTimestamp(),
              'isRead': false,
              'navigationTarget': {
                'route': 'TherapistScheduler',
                'slotId': slotDoc.id,
              },
            });
          }
          // Mark the slot as completed
          try {
            await slotDoc.reference.update({'status': 'completed'});
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('_checkAndGenerateSessionNotifications error: $e');
    }
  }

  List<NotificationInboxItem> _filterNotifications(
      List<NotificationInboxItem> items, int tabIndex) {
    if (tabIndex == 0) return items; // 'All'
    final category = _tabs[tabIndex].toLowerCase();

    return items.where((item) {
      if (category == 'messages') {
        return item.category == 'messages';
      } else if (category == 'subscriptions') {
        return item.category == 'subscription';
      } else if (category == 'activities') {
        return item.category == 'activities' || item.category == 'progress';
      } else if (category == 'system') {
        return item.category == 'system' ||
            item.category == 'verification' ||
            item.category == 'reviews';
      } else if (category == 'reports') {
        return item.category == 'reports';
      }
      return false;
    }).toList();
  }

  Future<void> _handleNotificationTap(NotificationInboxItem item) async {
    await AppRepositories.support.markNotificationAsRead(item.id);

    if (!mounted) return;

    final target = item.navigationTarget;
    final route = target['route']?.toString();

    if (route == 'Reviews' || route == 'reviews') {
      // Just mark as read, keep user in the inbox
    } else if (route == 'ProfileStatus' || route == 'profilestatus') {
      // Just mark as read, keep user in the inbox
    } else if ((route == 'Chat' || route == 'chat') && target['threadId'] != null) {
      final threadId = target['threadId'].toString();
      try {
        final threadDoc =
            await AppRepositories.support.watchThread(threadId).first;
        if (threadDoc != null && mounted) {
          final currentUser = AppRepositories.auth.currentUser;
          final role = currentUser?.uid == threadDoc.parentId
              ? 'parent'
              : 'therapist';
          final peerName = role == 'parent'
              ? threadDoc.therapistDisplayName
              : threadDoc.parentDisplayName;

          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => TherapistChatScreen(
                thread: threadDoc,
                participantName: peerName,
                senderRole: role,
              ),
            ),
          );
        }
      } catch (_) {}
    }
  }

  Future<void> _saveNotificationPreferences(Map<String, bool> values) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;



    final sanitised = <String, bool>{
      for (final key in _defaultTherapistNotificationPrefs.keys)
        key: values[key] ?? _defaultTherapistNotificationPrefs[key]!,
    };

    try {
      await Future.wait([
        FirebaseFirestore.instance
            .collection(FirestoreCollections.therapistProfiles)
            .doc(uid)
            .update({
          'therapistNotificationPreferences': sanitised,
          'updatedAt': FieldValue.serverTimestamp(),
        }),
        FirebaseFirestore.instance
            .collection(FirestoreCollections.users)
            .doc(uid)
            .update({
          'notificationPreferences': sanitised,
          'updatedAt': FieldValue.serverTimestamp(),
        }),
      ]);
      if (!mounted) return;
      setState(() {
        _currentPrefs = sanitised;
      });
      ScaffoldMessenger.of(context).showSnackBar(
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
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.error_outline, color: Colors.white, size: 20),
              SizedBox(width: 10),
              Text(
                'Failed to save notification preferences.',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
            ],
          ),
          backgroundColor: const Color(0xFFE74C3C),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SessionGuard(
      role: SessionGuardRole.therapist,
      child: FigmaModuleScaffold(
        title: 'Alerts',
        onBack: () => Navigator.pop(context, _currentPrefs),
        trailing: IconButton(
          icon: const Icon(Icons.settings_outlined, color: Color(0xFF1E293B)),
          onPressed: () async {
            final updated = await Navigator.push<Map<String, bool>>(
              context,
              MaterialPageRoute(
                builder: (_) => TherapistNotificationSettingsScreen(
                  initialValues: _currentPrefs,
                ),
              ),
            );
            if (updated != null) {
              await _saveNotificationPreferences(updated);
            }
          },
        ),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(bottomRight: Radius.circular(38)),
          ),
          child: StreamBuilder<List<NotificationInboxItem>>(
            stream: AppRepositories.support.watchNotifications(),
            builder: (context, snapshot) {
              final items = snapshot.data ?? const [];
              final unreadCount = items.where((item) => !item.isRead).length;

              return Column(
                children: [
                  TabBar(
                    controller: _tabController,
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    padding: EdgeInsets.zero,
                    labelColor: const Color(0xFF4EA9E3),
                    unselectedLabelColor: const Color(0xFF64748B),
                    indicatorColor: const Color(0xFF4EA9E3),
                    tabs: _tabs.map((tab) {
                      int count = 0;
                      if (tab == 'All') {
                        count = unreadCount;
                      } else {
                        count = _filterNotifications(items, _tabs.indexOf(tab))
                            .where((item) => !item.isRead)
                            .length;
                      }
                      return Tab(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(tab),
                            if (count > 0) ...[
                              const SizedBox(width: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEF4444),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '$count',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                  if (unreadCount > 0)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: Row(
                        children: [
                          Text(
                            'You have $unreadCount unread alerts',
                            style: const TextStyle(
                              color: Color(0xFF64748B),
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: () => AppRepositories.support
                                .markAllNotificationsAsRead(),
                            icon: const Icon(Icons.done_all,
                                size: 16, color: Color(0xFF4EA9E3)),
                            label: const Text(
                              'Mark all as read',
                              style: TextStyle(
                                color: Color(0xFF4EA9E3),
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: List.generate(_tabs.length, (tabIndex) {
                        final filtered = _filterNotifications(items, tabIndex);

                        if (filtered.isEmpty) {
                          return Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.notifications_off_outlined,
                                  size: 64,
                                  color: Colors.grey.shade300,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'No alerts in this category',
                                  style: TextStyle(
                                      color: Colors.grey.shade500,
                                      fontSize: 14),
                                ),
                              ],
                            ),
                          );
                        }

                        return ListView.separated(
                          padding: const EdgeInsets.fromLTRB(14, 12, 14, 120),
                          itemCount: filtered.length,
                          separatorBuilder: (context, index) =>
                              const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final item = filtered[index];
                            final categoryColor =
                                _getCategoryColor(item.category);

                            return InkWell(
                              onTap: () => _handleNotificationTap(item),
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: item.isRead
                                      ? Colors.white
                                      : const Color(0xFFF0F7FF),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: item.isRead
                                        ? const Color(0xFFE2E8F0)
                                        : const Color(0xFFBFDBFE),
                                    width: 1.2,
                                  ),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: categoryColor.withValues(
                                            alpha: 0.1),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        _getCategoryIcon(item.category),
                                        color: categoryColor,
                                        size: 20,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  item.title,
                                                  style: TextStyle(
                                                    fontWeight: item.isRead
                                                        ? FontWeight.w600
                                                        : FontWeight.bold,
                                                    fontSize: 14.5,
                                                    color:
                                                        const Color(0xFF1E293B),
                                                  ),
                                                ),
                                              ),
                                              Text(
                                                _formatRelativeTime(
                                                    item.timestamp),
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  color: Color(0xFF64748B),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            item.message,
                                            style: const TextStyle(
                                              fontSize: 13,
                                              color: Color(0xFF475569),
                                              height: 1.35,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    if (!item.isRead) ...[
                                      const SizedBox(width: 8),
                                      Container(
                                        width: 8,
                                        height: 8,
                                        decoration: const BoxDecoration(
                                          color: Color(0xFF2563EB),
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            );
                          },
                        );
                      }),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
