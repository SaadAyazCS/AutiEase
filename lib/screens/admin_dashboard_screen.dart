import 'package:flutter/material.dart';
import '../models/app_models.dart';
import '../repositories/app_repositories.dart';
import '../widgets/session_guard.dart';
import 'login_screen.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final List<String> _tabs = ['Overview', 'Verification', 'Reports', 'Parents', 'Feedback', 'Audit Logs'];
  bool _loading = false;
  Map<String, dynamic> _stats = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _loadStats();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadStats() async {
    setState(() => _loading = true);
    try {
      final data = await AppRepositories.admin.getAnalyticsStats();
      setState(() {
        _stats = data;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _logout() async {
    final navigator = Navigator.of(context);
    await AppRepositories.auth.signOut();
    navigator.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SessionGuard(
      role: SessionGuardRole.admin,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          title: const Text(
            'AutiEase Admin Panel',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
          ),
          backgroundColor: const Color(0xFF1E293B),
          foregroundColor: Colors.white,
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              onPressed: _loadStats,
            ),
            IconButton(
              icon: const Icon(Icons.logout_rounded),
              onPressed: _logout,
            ),
          ],
          bottom: TabBar(
            controller: _tabController,
            isScrollable: true,
            labelColor: Colors.white,
            unselectedLabelColor: const Color(0xFF94A3B8), // slate 400
            indicatorColor: const Color(0xFF38BDF8),
            tabs: _tabs.map((name) => Tab(text: name)).toList(),
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                controller: _tabController,
                children: [
                  _buildOverviewTab(),
                  _buildVerificationTab(),
                  _buildReportsTab(),
                  _buildParentsTab(),
                  _buildFeedbackTab(),
                  _buildAuditLogsTab(),
                ],
              ),
      ),
    );
  }

  Widget _buildOverviewCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: const Color(0xFFF1F5F9)), // slate 100
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  style: const TextStyle(color: Color(0xFF64748B), fontSize: 13, fontWeight: FontWeight.w500), // slate 500
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(color: Color(0xFF1E293B), fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewTab() {
    return RefreshIndicator(
      onRefresh: _loadStats,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'System Analytics',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
          ),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.6,
            children: [
              _buildOverviewCard('Total Parents', '${_stats['totalParents'] ?? 0}', Icons.people_outline, const Color(0xFF3B82F6)),
              _buildOverviewCard('Verified Therapists', '${_stats['approvedTherapists'] ?? 0}', Icons.verified_outlined, const Color(0xFF10B981)),
              _buildOverviewCard('Pending Verifications', '${_stats['pendingTherapists'] ?? 0}', Icons.hourglass_empty, const Color(0xFFF59E0B)),
              _buildOverviewCard('Suspended Therapists', '${_stats['suspendedTherapists'] ?? 0}', Icons.block_outlined, const Color(0xFFEF4444)),
              _buildOverviewCard('Active Subscriptions', '${_stats['activeSubscriptions'] ?? 0}', Icons.card_membership, const Color(0xFF8B5CF6)),
              _buildOverviewCard('Avg Rating', '${(_stats['averageTherapistRating'] ?? 0.0).toStringAsFixed(1)} ★', Icons.star, const Color(0xFFF59E0B)),
              _buildOverviewCard('Total Reports', '${_stats['totalReports'] ?? 0}', Icons.gavel, const Color(0xFFEF4444)),
              _buildOverviewCard('Reviews & Feedback', '${_stats['totalFeedback'] ?? 0}', Icons.feedback_outlined, const Color(0xFF0D9488)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildVerificationTab() {
    return FutureBuilder<List<TherapistProfile>>(
      future: AppRepositories.admin.listTherapistsByStatus('pending'),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final list = snapshot.data ?? [];
        if (list.isEmpty) {
          return const Center(
            child: Text('No pending therapist verifications.', style: TextStyle(color: Color(0xFF64748B))),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: list.length,
          separatorBuilder: (context, index) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final therapist = list[index];
            return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)), // slate 200
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: Colors.blue.shade50,
                        child: Text(therapist.displayName[0]),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              therapist.displayName,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            Text(
                              therapist.specializations.join(', '),
                              style: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Divider(),
                  const SizedBox(height: 8),
                  Text('CNIC: ${therapist.cnic}', style: const TextStyle(fontSize: 13)),
                  Text('License Number: ${therapist.licenseNumber}', style: const TextStyle(fontSize: 13)),
                  Text('Registration Number: ${therapist.registrationNumber}', style: const TextStyle(fontSize: 13)),
                  Text('Experience Details: ${therapist.experienceDetails}', style: const TextStyle(fontSize: 13)),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => _showRejectVerificationDialog(therapist.id),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            side: const BorderSide(color: Colors.red),
                          ),
                          child: const Text('Reject'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => _approveVerification(therapist.id),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Approve'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _approveVerification(String therapistId) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await AppRepositories.admin.verifyTherapist(
        therapistId: therapistId,
        status: 'approved',
        adminFeedback: 'Approved by administrator.',
      );
      messenger.showSnackBar(
        const SnackBar(content: Text('Therapist approved successfully.')),
      );
      _loadStats();
      setState(() {});
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Verification error: $e')),
      );
    }
  }

  void _showRejectVerificationDialog(String therapistId) {
    final controller = TextEditingController();
    final messenger = ScaffoldMessenger.of(context);
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Reject Verification'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'Reason for rejection',
              hintText: 'Please state missing documents or details...',
            ),
            maxLines: 3,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final reason = controller.text.trim();
                if (reason.isEmpty) return;
                try {
                  await AppRepositories.admin.verifyTherapist(
                    therapistId: therapistId,
                    status: 'rejected',
                    adminFeedback: reason,
                  );
                  if (ctx.mounted) Navigator.pop(ctx);
                  messenger.showSnackBar(
                    const SnackBar(content: Text('Therapist application rejected.')),
                  );
                  _loadStats();
                  setState(() {});
                } catch (_) {}
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
              child: const Text('Reject'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildReportsTab() {
    return StreamBuilder<List<UserReport>>(
      stream: AppRepositories.admin.watchReports(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final list = snapshot.data ?? [];
        if (list.isEmpty) {
          return const Center(
            child: Text('No active user reports.', style: TextStyle(color: Color(0xFF64748B))),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: list.length,
          separatorBuilder: (context, index) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final report = list[index];
            final pending = report.status == 'pending';

            return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: pending ? Colors.amber.shade200 : const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: pending ? Colors.amber.shade100 : const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          report.status.toUpperCase(),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: pending ? Colors.amber.shade900 : const Color(0xFF334155),
                          ),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${report.timestamp.day}/${report.timestamp.month}/${report.timestamp.year}',
                        style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text('Reporter ID: ${report.reporterId} (${report.reporterRole})', style: const TextStyle(fontSize: 12.5)),
                  Text('Reported User ID: ${report.reportedId}', style: const TextStyle(fontSize: 12.5)),
                  const SizedBox(height: 6),
                  Text('Reason: ${report.reason}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  if (report.comments.isNotEmpty) Text('Comments: ${report.comments}', style: const TextStyle(fontSize: 13.5)),
                  if (report.chatContext.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    const Text('Chat Context Snippet:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    Container(
                      padding: const EdgeInsets.all(8),
                      margin: const EdgeInsets.only(top: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: report.chatContext.take(5).map((msg) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: Text(
                              '${msg['senderRole'] ?? 'user'}: ${msg['body'] ?? ''}',
                              style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                  if (pending) ...[
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => _updateReport(report.id, 'dismissed'),
                            child: const Text('Dismiss'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => _showModerationDialog(report.reportedId, report.id),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                            child: const Text('Moderate'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _updateReport(String reportId, String status) async {
    await AppRepositories.admin.updateReportStatus(reportId, status);
    setState(() {});
  }

  void _showModerationDialog(String userId, String reportId) {
    final controller = TextEditingController();
    final messenger = ScaffoldMessenger.of(context);
    String selectedAction = 'warn';

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Take Moderation Action'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: selectedAction,
                    items: const [
                      DropdownMenuItem(value: 'warn', child: Text('Send Warning')),
                      DropdownMenuItem(value: 'suspend', child: Text('Suspend Profile')),
                      DropdownMenuItem(value: 'ban', child: Text('Permanently Ban')),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setDialogState(() => selectedAction = val);
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    decoration: const InputDecoration(
                      labelText: 'Reason for action',
                    ),
                    maxLines: 2,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final reason = controller.text.trim();
                    if (reason.isEmpty) return;
                    try {
                      await AppRepositories.admin.executeModerationAction(
                        reportedUserId: userId,
                        action: selectedAction,
                        reason: reason,
                      );
                      await AppRepositories.admin.updateReportStatus(reportId, 'resolved');
                      if (ctx.mounted) Navigator.pop(ctx);
                      messenger.showSnackBar(
                        SnackBar(content: Text('Action "$selectedAction" executed successfully.')),
                      );
                      setState(() {});
                    } catch (_) {}
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                  child: const Text('Execute'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildParentsTab() {
    return FutureBuilder<List<UserProfile>>(
      future: AppRepositories.admin.listParents(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final list = snapshot.data ?? [];
        if (list.isEmpty) {
          return const Center(
            child: Text('No parent profiles found.', style: TextStyle(color: Color(0xFF64748B))),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: list.length,
          separatorBuilder: (context, index) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final parent = list[index];
            return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    parent.fullName,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  Text('Email: ${parent.email}', style: const TextStyle(color: Color(0xFF475569), fontSize: 13.5)),
                  Text('Phone: ${parent.phone.isEmpty ? "Not set" : parent.phone}', style: const TextStyle(color: Color(0xFF475569), fontSize: 13.5)),
                  const SizedBox(height: 10),
                  FutureBuilder<List<ChildProfile>>(
                    future: AppRepositories.users.getChildrenForParent(parent.uid),
                    builder: (context, childSnapshot) {
                      if (childSnapshot.connectionState == ConnectionState.waiting) {
                        return const LinearProgressIndicator();
                      }
                      final children = childSnapshot.data ?? [];
                      if (children.isEmpty) {
                        return const Text('No children profiles setup yet.', style: TextStyle(fontStyle: FontStyle.italic, fontSize: 12));
                      }
                      return Wrap(
                        spacing: 8,
                        children: children.map((c) {
                          return Chip(
                            avatar: CircleAvatar(child: Text(c.name[0])),
                            label: Text('${c.name} (${c.supportAreas.join(", ")})'),
                            labelStyle: const TextStyle(fontSize: 11),
                          );
                        }).toList(),
                      );
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildFeedbackTab() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: AppRepositories.admin.listAllFeedbackAndReviews(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final list = snapshot.data ?? [];
        if (list.isEmpty) {
          return const Center(
            child: Text('No application feedback or reviews yet.', style: TextStyle(color: Color(0xFF64748B))),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: list.length,
          separatorBuilder: (context, index) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final fb = list[index];
            final isAppFeedback = fb['type'] == 'app_feedback';
            final date = fb['timestamp'] as DateTime;

            return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: isAppFeedback ? Colors.blue.shade50 : Colors.teal.shade50,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          fb['title'].toString().toUpperCase(),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: isAppFeedback ? Colors.blue.shade900 : Colors.teal.shade900,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${date.day}/${date.month}/${date.year}',
                        style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Text(
                        'By: ${fb['user']}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                      ),
                      const Spacer(),
                      if (fb['rating'] > 0)
                        Row(
                          children: List.generate(5, (starIdx) {
                            return Icon(
                              starIdx < fb['rating'] ? Icons.star : Icons.star_border,
                              color: Colors.amber,
                              size: 14,
                            );
                          }),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    fb['body'].toString(),
                    style: const TextStyle(fontSize: 13, color: Color(0xFF374151), height: 1.4),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildAuditLogsTab() {
    return FutureBuilder<List<AdminAuditLog>>(
      future: AppRepositories.admin.listAuditLogs(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final list = snapshot.data ?? [];
        if (list.isEmpty) {
          return const Center(
            child: Text('No audit logs available.', style: TextStyle(color: Color(0xFF64748B))),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: list.length,
          itemBuilder: (context, index) {
            final log = list[index];
            final date = log.timestamp;
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text(log.actionType.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                subtitle: Text(log.details, style: const TextStyle(fontSize: 12.5)),
                trailing: Text(
                  '${date.day}/${date.month} ${date.hour}:${date.minute.toString().padLeft(2, "0")}',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
