import 'package:flutter/material.dart';
import '../models/app_models.dart';
import '../repositories/app_repositories.dart';
import '../widgets/figma_module_scaffold.dart';
import '../widgets/session_guard.dart';
import 'notification_settings_screen.dart';
import 'therapist_chat_screen.dart';

class NotificationInboxScreen extends StatefulWidget {
  const NotificationInboxScreen({super.key});

  @override
  State<NotificationInboxScreen> createState() => _NotificationInboxScreenState();
}

class _NotificationInboxScreenState extends State<NotificationInboxScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final List<String> _tabs = ['All', 'Messages', 'Subscriptions', 'Activities', 'System'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
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
        return Icons.chat_bubble_outline_rounded;
      case 'subscription':
        return Icons.payment_rounded;
      case 'reviews':
        return Icons.star_outline_rounded;
      case 'activities':
        return Icons.task_alt_rounded;
      case 'verification':
        return Icons.verified_user_outlined;
      case 'system':
      default:
        return Icons.info_outline_rounded;
    }
  }

  Color _getCategoryColor(String category) {
    switch (category) {
      case 'messages':
        return const Color(0xFF2563EB);
      case 'subscription':
        return const Color(0xFF16A34A);
      case 'reviews':
        return const Color(0xFFD97706);
      case 'activities':
        return const Color(0xFF7C3AED);
      case 'verification':
        return const Color(0xFF0D9488);
      case 'system':
      default:
        return const Color(0xFF4B5563);
    }
  }

  List<NotificationInboxItem> _filterNotifications(List<NotificationInboxItem> items, int tabIndex) {
    if (tabIndex == 0) return items; // 'All'
    final category = _tabs[tabIndex].toLowerCase();
    
    return items.where((item) {
      if (category == 'messages') {
        return item.category == 'messages';
      } else if (category == 'subscriptions') {
        return item.category == 'subscription';
      } else if (category == 'activities') {
        return item.category == 'activities';
      } else if (category == 'system') {
        return item.category == 'system' || item.category == 'verification' || item.category == 'reviews';
      }
      return false;
    }).toList();
  }

  Future<void> _handleNotificationTap(NotificationInboxItem item) async {
    await AppRepositories.support.markNotificationAsRead(item.id);
    
    if (!mounted) return;

    final target = item.navigationTarget;
    final route = target['route']?.toString();

    if (route == 'Reviews') {
      Navigator.popUntil(context, (route) => route.isFirst);
    } else if (route == 'ProfileStatus') {
      Navigator.popUntil(context, (route) => route.isFirst);
    } else if (route == 'Chat' && target['threadId'] != null) {
      final threadId = target['threadId'].toString();
      try {
        final threadDoc = await AppRepositories.support.watchThread(threadId).first;
        if (threadDoc != null && mounted) {
          final currentUser = AppRepositories.auth.currentUser;
          final role = currentUser?.uid == threadDoc.parentId ? 'parent' : 'therapist';
          final peerName = role == 'parent' ? threadDoc.therapistDisplayName : threadDoc.parentDisplayName;
          
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

  @override
  Widget build(BuildContext context) {
    return SessionGuard(
      role: SessionGuardRole.authenticated,
      child: FigmaModuleScaffold(
        title: 'Inbox',
        onBack: () => Navigator.pop(context),
        trailing: IconButton(
          icon: const Icon(Icons.settings_outlined, color: Color(0xFF1E293B)),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const NotificationSettingsScreen(),
              ),
            );
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
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
                            'You have $unreadCount unread notifications',
                            style: const TextStyle(
                              color: Color(0xFF64748B),
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const Spacer(),
                          TextButton.icon(
                            onPressed: () => AppRepositories.support.markAllNotificationsAsRead(),
                            icon: const Icon(Icons.done_all, size: 16, color: Color(0xFF4EA9E3)),
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
                                  'No notifications in this category',
                                  style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
                                ),
                              ],
                            ),
                          );
                        }

                        return ListView.separated(
                          padding: const EdgeInsets.fromLTRB(14, 12, 14, 120),
                          itemCount: filtered.length,
                          separatorBuilder: (context, index) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final item = filtered[index];
                            final categoryColor = _getCategoryColor(item.category);

                            return InkWell(
                              onTap: () => _handleNotificationTap(item),
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: item.isRead ? Colors.white : const Color(0xFFF0F7FF),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: item.isRead ? const Color(0xFFE2E8F0) : const Color(0xFFBFDBFE),
                                    width: 1.2,
                                  ),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: categoryColor.withValues(alpha: 0.1),
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
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  item.title,
                                                  style: TextStyle(
                                                    fontWeight: item.isRead ? FontWeight.w600 : FontWeight.bold,
                                                    fontSize: 14.5,
                                                    color: const Color(0xFF1E293B),
                                                  ),
                                                ),
                                              ),
                                              Text(
                                                _formatRelativeTime(item.timestamp),
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
