import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/app_models.dart';
import '../repositories/app_repositories.dart';
import '../widgets/session_guard.dart';
import '../utils/currency_utils.dart';
import 'certificate_viewer_screen.dart';
import 'login_screen.dart';
import 'receipt_viewer_screen.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final List<String> _tabs = ['Overview', 'Verification', 'Reports', 'Subscriptions', 'Parents', 'Therapists', 'Feedback', 'Audit Logs', 'Withdrawals'];
  bool _loading = false;
  Map<String, dynamic> _stats = {};
  
  // Cache maps for resolving UIDs to human-readable names and emails
  Map<String, String> _userNames = {};
  Map<String, String> _userEmails = {};
  Map<String, String> _therapistNames = {};

  // Stream subscription for reports badge count
  StreamSubscription<List<UserReport>>? _reportsSubscription;
  StreamSubscription<QuerySnapshot>? _usersSubscription;
  StreamSubscription<QuerySnapshot>? _subscriptionsSubscription;
  StreamSubscription<QuerySnapshot>? _withdrawalsSubscription;
  int _pendingReportsCount = 0;
  int _pendingWithdrawalsCount = 0;

  // Subscriptions search/filter state
  final TextEditingController _subSearchController = TextEditingController();
  String _subSearchQuery = '';
  String _subFilterStatus = 'All';

  // Audit Logs search/filter state
  Future<List<AdminAuditLog>>? _auditLogsFuture;
  final TextEditingController _auditSearchController = TextEditingController();
  String _auditSearchQuery = '';
  String _auditFilterType = 'All';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _loadStats();

    // Subscribe to reports stream to dynamically update badge count in real-time
    _reportsSubscription = AppRepositories.admin.watchReports().listen((reports) {
      final pendingCount = reports.where((r) => r.status == 'pending').length;
      if (mounted && pendingCount != _pendingReportsCount) {
        setState(() {
          _pendingReportsCount = pendingCount;
        });
      }
    });

    // Subscribe to withdrawals stream to dynamically update badge count in real-time
    _withdrawalsSubscription = FirebaseFirestore.instance
        .collection('withdrawal_requests')
        .where('status', isEqualTo: 'pending')
        .snapshots()
        .listen((snapshot) {
      if (mounted) {
        setState(() {
          _pendingWithdrawalsCount = snapshot.docs.length;
        });
      }
    });

    _subSearchController.addListener(() {
      setState(() {
        _subSearchQuery = _subSearchController.text;
      });
    });

    _auditSearchController.addListener(() {
      setState(() {
        _auditSearchQuery = _auditSearchController.text;
      });
    });

    _usersSubscription = FirebaseFirestore.instance
        .collection('users')
        .snapshots()
        .listen((_) => _silentReloadStats());

    _subscriptionsSubscription = FirebaseFirestore.instance
        .collection('subscriptions')
        .snapshots()
        .listen((_) => _silentReloadStats());
  }

  @override
  void dispose() {
    _tabController.dispose();
    _subSearchController.dispose();
    _auditSearchController.dispose();
    _reportsSubscription?.cancel();
    _usersSubscription?.cancel();
    _subscriptionsSubscription?.cancel();
    _withdrawalsSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadUserAndTherapistNames() async {
    try {
      final usersSnap = await FirebaseFirestore.instance.collection('users').get();
      final therapistsSnap = await FirebaseFirestore.instance.collection('therapist_profiles').get();
      
      final Map<String, String> userNames = {};
      final Map<String, String> userEmails = {};
      for (var doc in usersSnap.docs) {
        final data = doc.data();
        final firstName = data['firstName'] ?? '';
        final lastName = data['lastName'] ?? '';
        final fullName = data['fullName'] ?? '$firstName $lastName'.trim();
        userNames[doc.id] = fullName.isNotEmpty ? fullName : (data['email'] ?? 'Unknown User');
        userEmails[doc.id] = data['email'] ?? '';
      }
      
      final Map<String, String> therapistNames = {};
      for (var doc in therapistsSnap.docs) {
        final data = doc.data();
        therapistNames[doc.id] = data['displayName'] ?? 'Unknown Therapist';
      }
      
      if (mounted) {
        setState(() {
          _userNames = userNames;
          _userEmails = userEmails;
          _therapistNames = therapistNames;
        });
      }
    } catch (e) {
      debugPrint('Error loading names for subscriptions: $e');
    }
  }

  Future<void> _silentReloadStats() async {
    try {
      final data = await AppRepositories.admin.getAnalyticsStats();
      await _loadUserAndTherapistNames();
      if (mounted) {
        setState(() {
          _stats = data;
        });
      }
    } catch (e) {
      debugPrint('Silent stats reload failed: $e');
    }
  }

  Future<void> _loadStats() async {
    setState(() {
      _loading = true;
      _auditLogsFuture = null;
      _subSearchController.clear();
      _auditSearchController.clear();
    });
    try {
      final data = await AppRepositories.admin.getAnalyticsStats();
      await _loadUserAndTherapistNames();
      setState(() {
        _stats = data;
        _loading = false;
      });
    } catch (e, stack) {
      debugPrint('Error loading admin stats: $e\n$stack');
      setState(() => _loading = false);
    }
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

    await AppRepositories.auth.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
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
            tabAlignment: TabAlignment.start,
            padding: EdgeInsets.zero,
            labelColor: Colors.white,
            unselectedLabelColor: const Color(0xFF94A3B8), // slate 400
            indicatorColor: const Color(0xFF38BDF8),
            tabs: _tabs.map((name) => _buildTabTitle(name)).toList(),
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
                  _buildSubscriptionsTab(),
                  _buildParentsTab(),
                  _buildTherapistsTab(),
                  _buildFeedbackTab(),
                  _buildAuditLogsTab(),
                  _buildWithdrawalsTab(),
                ],
              ),
      ),
    );
  }

  Widget _buildOverviewCard(String title, String value, IconData icon, Color color) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final useVerticalLayout = constraints.maxWidth < 150;
        final paddingVal = constraints.maxWidth < 160 ? 10.0 : 14.0;
        final gapVal = constraints.maxWidth < 160 ? 8.0 : 12.0;

        return Container(
          padding: EdgeInsets.all(paddingVal),
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
          child: useVerticalLayout
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(icon, color: color, size: 20),
                    ),
                    const SizedBox(height: 8),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        value,
                        style: const TextStyle(
                          color: Color(0xFF1E293B),
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                )
              : Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(icon, color: color, size: 22),
                    ),
                    SizedBox(width: gapVal),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF64748B),
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 2),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              value,
                              style: const TextStyle(
                                color: Color(0xFF1E293B),
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
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
            childAspectRatio: 1.3,
            children: [
              _buildOverviewCard('Total Parents', '${_stats['totalParents'] ?? 0}', Icons.people_outline, const Color(0xFF3B82F6)),
              _buildOverviewCard('Verified Therapists', '${_stats['approvedTherapists'] ?? 0}', Icons.verified_outlined, const Color(0xFF10B981)),
              _buildOverviewCard('Pending Verifications', '${_stats['pendingTherapists'] ?? 0}', Icons.hourglass_empty, const Color(0xFFF59E0B)),
              _buildOverviewCard('Suspended Therapists', '${_stats['suspendedTherapists'] ?? 0}', Icons.block_outlined, const Color(0xFFEF4444)),
              _buildOverviewCard('Subscriptions', '${_stats['activeSubscriptions'] ?? 0}', Icons.card_membership, const Color(0xFF8B5CF6)),
              _buildOverviewCard('Avg Rating', '${double.tryParse(_stats['averageTherapistRating']?.toString() ?? '0.0')?.toStringAsFixed(1) ?? "0.0"} ★', Icons.star, const Color(0xFFF59E0B)),
              _buildOverviewCard('Total Reports', '${_stats['totalReports'] ?? 0}', Icons.gavel, const Color(0xFFEF4444)),
              _buildOverviewCard('Reviews & Feedback', '${_stats['totalFeedback'] ?? 0}', Icons.feedback_outlined, const Color(0xFF0D9488)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTabTitle(String name) {
    int count = 0;
    Color badgeColor = Colors.transparent;

    if (name == 'Verification') {
      count = int.tryParse(_stats['pendingTherapists']?.toString() ?? '0') ?? 0;
      badgeColor = const Color(0xFFF59E0B); // Amber
    } else if (name == 'Reports') {
      count = _pendingReportsCount;
      badgeColor = const Color(0xFFEF4444); // Red
    } else if (name == 'Withdrawals') {
      count = _pendingWithdrawalsCount;
      badgeColor = const Color(0xFF3B82F6); // Blue
    }

    if (count == 0) {
      return Tab(text: name);
    }

    return Tab(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(name),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: badgeColor,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _exportAuditLogs(List<AdminAuditLog> logs) {
    if (logs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No logs available to export.')),
      );
      return;
    }

    final csvBuffer = StringBuffer();
    csvBuffer.writeln('ID,Timestamp,Action Type,Admin Email,Admin UID,Target UID,Details');
    for (final log in logs) {
      final escapedDetails = log.details.replaceAll('"', '""');
      final email = log.adminEmail.isNotEmpty ? log.adminEmail : 'System';
      csvBuffer.writeln(
        '"${log.id}","${log.timestamp.toIso8601String()}","${log.actionType}","$email","${log.adminUid}","${log.targetUid}","$escapedDetails"'
      );
    }
    final csvString = csvBuffer.toString();

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.download_rounded, color: Color(0xFF3B82F6)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Export ${logs.length} Logs',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Below is the formatted CSV representation of your filtered logs. Tap the button below to copy the complete text block.',
                style: TextStyle(fontSize: 13, color: Color(0xFF475569), height: 1.4),
              ),
              const SizedBox(height: 12),
              Container(
                height: 180,
                width: double.maxFinite,
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Scrollbar(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(10),
                    child: SelectableText(
                      csvString,
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Color(0xFF334155)),
                    ),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: csvString));
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('CSV copied to clipboard successfully!')),
                );
              },
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.copy_rounded, size: 16),
                  SizedBox(width: 4),
                  Text('Copy CSV'),
                ],
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  void _viewFullScreenImage(BuildContext context, String source, bool isUrl) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(10),
        child: Stack(
          alignment: Alignment.center,
          children: [
            InteractiveViewer(
              maxScale: 4.0,
              child: isUrl
                  ? Image.network(
                      source,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) =>
                          const Icon(Icons.broken_image, size: 80, color: Colors.white),
                    )
                  : Image.memory(
                      base64Decode(source.contains('base64,')
                          ? source.substring(source.indexOf('base64,') + 7)
                          : source),
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) =>
                          const Icon(Icons.broken_image, size: 80, color: Colors.white),
                    ),
            ),
            Positioned(
              top: 10,
              right: 10,
              child: CircleAvatar(
                backgroundColor: Colors.black54,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContextMessage(Map<String, dynamic> msg) {
    return Builder(
      builder: (context) {
        final senderRole = (msg['senderRole'] ?? 'user').toString().toUpperCase();
        final body = msg['body']?.toString() ?? '';
        final type = msg['messageType'] ?? msg['type'] ?? 'text';
        final attachments = msg['attachments'] is List ? List.from(msg['attachments']) : [];

        Widget contentWidget;
        if (type == 'image' && attachments.isNotEmpty) {
          final attachStr = attachments.first.toString().trim();
          final isUrl = attachStr.startsWith('http://') || attachStr.startsWith('https://');

          contentWidget = GestureDetector(
            onTap: () => _viewFullScreenImage(context, attachStr, isUrl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: isUrl
                      ? Image.network(
                          attachStr,
                          height: 180,
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) => const Icon(Icons.broken_image, size: 40, color: Colors.grey),
                        )
                      : Image.memory(
                          base64Decode(attachStr.contains('base64,')
                              ? attachStr.substring(attachStr.indexOf('base64,') + 7)
                              : attachStr),
                          height: 180,
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) => const Icon(Icons.broken_image, size: 40, color: Colors.grey),
                        ),
                ),
                if (body.isNotEmpty && body != 'Sent an image')
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(body, style: const TextStyle(fontSize: 12, color: Color(0xFF334155))),
                  ),
              ],
            ),
          );
        } else if (type == 'file' && attachments.isNotEmpty) {
          final attachStr = attachments.first.toString().trim();
          final isUrl = attachStr.startsWith('http://') || attachStr.startsWith('https://');

          contentWidget = InkWell(
            onTap: () async {
              if (isUrl) {
                try {
                  await launchUrl(Uri.parse(attachStr), mode: LaunchMode.externalApplication);
                } catch (_) {}
              } else {
                var cleanBase64 = attachStr;
                if (cleanBase64.contains('base64,')) {
                  cleanBase64 = cleanBase64.substring(cleanBase64.indexOf('base64,') + 7);
                }
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ReceiptViewerScreen(
                      base64String: cleanBase64,
                      title: 'Document Attachment',
                    ),
                  ),
                );
              }
            },
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.insert_drive_file_rounded, size: 16, color: Colors.blue),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    body.isNotEmpty && body != 'Sent a file' ? body : '[File Attachment]',
                    style: const TextStyle(color: Colors.blue, fontSize: 12, decoration: TextDecoration.underline),
                  ),
                ),
              ],
            ),
          );
        } else if ((type == 'audio' || type == 'voice') && attachments.isNotEmpty) {
          contentWidget = _AdminVoicePlayer(payload: attachments.first.toString());
        } else {
          contentWidget = Text(body, style: const TextStyle(fontSize: 12, color: Color(0xFF334155)));
        }

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$senderRole:',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: senderRole == 'PARENT' ? Colors.blue.shade800 : Colors.green.shade800,
                ),
              ),
              const SizedBox(height: 2),
              contentWidget,
            ],
          ),
        );
      },
    );
  }

  void _showReportDetailsDialog(UserReport report) {
    showDialog(
      context: context,
      builder: (ctx) {
        final pending = report.status == 'pending';
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.flag_rounded, color: Color(0xFFEF4444)),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'User Report Details',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _detailRow('Report ID', report.id),
                _detailRow('Status', report.status.toUpperCase()),
                _detailRow('Date', '${report.timestamp.day}/${report.timestamp.month}/${report.timestamp.year}'),
                _detailRow('Reporter ID', report.reporterId),
                _detailRow('Reporter Role', report.reporterRole),
                _detailRow('Reported ID', report.reportedId),
                if (report.reporterRole == 'parent') ...[
                  _detailRow('Subscription Status', report.subscriptionStatus.toUpperCase()),
                  _detailRow('Parent Action', report.parentAction == 'kept' ? 'KEPT ACTIVE' : (report.parentAction == 'cancelled' ? 'CANCELLED' : report.parentAction.toUpperCase())),
                ],
                const SizedBox(height: 10),
                const Text(
                  'Reason & Details',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E293B)),
                ),
                const Divider(),
                Text(
                  report.reason,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFFEF4444)),
                ),
                if (report.comments.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Comments: ${report.comments}',
                    style: const TextStyle(fontSize: 13, color: Color(0xFF475569)),
                  ),
                ],
                if (report.chatContext.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'Complete Conversation Context',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E293B)),
                  ),
                  const Divider(),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: report.chatContext.map((msg) => _buildContextMessage(msg)).toList(),
                    ),
                  ),
                ],

                // ── One-Time Messages ───────────────────────────
                const SizedBox(height: 16),
                const Text(
                  'One-Time Messages (Additional Info)',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E293B)),
                ),
                const Divider(),
                StreamBuilder<List<ReportMessage>>(
                  stream: AppRepositories.support.watchReportMessages(report.id),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: Padding(
                        padding: EdgeInsets.all(8.0),
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ));
                    }
                    final msgs = snapshot.data ?? [];
                    if (msgs.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          'No additional information submitted yet.',
                          style: TextStyle(fontSize: 12.5, fontStyle: FontStyle.italic, color: Color(0xFF64748B)),
                        ),
                      );
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: msgs.map((msg) {
                        final formattedTime = '${msg.timestamp.day}/${msg.timestamp.month}/${msg.timestamp.year} ${msg.timestamp.hour.toString().padLeft(2, '0')}:${msg.timestamp.minute.toString().padLeft(2, '0')}';
                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFFBEB), // soft amber background
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFFCD34D)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    '${msg.senderRole.toUpperCase()} (ID: ${msg.senderId})',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: Color(0xFFB45309)),
                                  ),
                                  Text(
                                    formattedTime,
                                    style: const TextStyle(fontSize: 10, color: Color(0xFFB45309)),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                msg.content,
                                style: const TextStyle(fontSize: 13, color: Color(0xFF78350F)),
                              ),
                              if (msg.attachments.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                ...msg.attachments.map((att) {
                                  final type = att['type']?.toString() ?? 'file';
                                  final filename = att['filename']?.toString() ?? 'Attachment';
                                  final data = att['data']?.toString() ?? '';

                                  if (type == 'image') {
                                    Widget imgWidget;
                                    try {
                                      final bytes = base64Decode(data);
                                      imgWidget = ClipRRect(
                                        borderRadius: BorderRadius.circular(8),
                                        child: Image.memory(bytes, fit: BoxFit.cover, height: 150),
                                      );
                                    } catch (_) {
                                      imgWidget = const Icon(Icons.broken_image, color: Colors.grey);
                                    }
                                    return Padding(
                                      padding: const EdgeInsets.only(top: 6),
                                      child: imgWidget,
                                    );
                                  } else if (type == 'voice') {
                                    return Padding(
                                      padding: const EdgeInsets.only(top: 6),
                                      child: _AdminVoicePlayer(payload: 'audio:10:$data'),
                                    );
                                  } else {
                                    return Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.picture_as_pdf, color: Colors.redAccent, size: 16),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              filename,
                                              style: const TextStyle(fontSize: 12, color: Colors.blue, decoration: TextDecoration.underline),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }
                                })
                              ]
                            ],
                          ),
                        );
                      }).toList(),
                    );
                  },
                ),
              ],
            ),
          ),
          actions: [
            if (pending) ...[
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _showModerationDialog(report.reportedId, report.id);
                },
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                child: const Text('Moderate'),
              ),
            ],
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _inspectTarget(String targetId) async {
    if (targetId.isEmpty) return;
    
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(20.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(width: 16),
                Text('Loading target details...', style: TextStyle(fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(targetId).get();
      
      if (userDoc.exists && userDoc.data() != null) {
        final parent = UserProfile.fromMap(userDoc.id, userDoc.data()!);
        
        if (parent.role == 'parent') {
          final children = await AppRepositories.users.getChildrenForParent(targetId);
          if (mounted) {
            Navigator.pop(context); // Dismiss loading
            _showParentDetailsDialog(parent, children);
          }
          return;
        } else if (parent.role == 'therapist') {
          final therapistDoc = await FirebaseFirestore.instance.collection('therapist_profiles').doc(targetId).get();
          if (therapistDoc.exists && therapistDoc.data() != null) {
            final therapist = TherapistProfile.fromMap(therapistDoc.id, therapistDoc.data()!);
            if (mounted) {
              Navigator.pop(context); // Dismiss loading
              _showTherapistDetailsDialog(therapist);
            }
            return;
          }
        }
      }
      
      final reportDoc = await FirebaseFirestore.instance.collection('reports').doc(targetId).get();
      if (reportDoc.exists && reportDoc.data() != null) {
        final report = UserReport.fromMap(reportDoc.id, reportDoc.data()!);
        if (mounted) {
          Navigator.pop(context); // Dismiss loading
          _showReportDetailsDialog(report);
        }
        return;
      }
      
      if (mounted) {
        Navigator.pop(context); // Dismiss loading
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('No parent, therapist, or report found for ID: $targetId')),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Dismiss loading
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error fetching target: $e')),
        );
      }
    }
  }

  Widget _buildVerificationTab() {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          Container(
            color: Colors.white,
            child: const TabBar(
              labelColor: Color(0xFF1E293B), // slate 800
              unselectedLabelColor: Color(0xFF64748B), // slate 505
              indicatorColor: Color(0xFF38BDF8),
              indicatorSize: TabBarIndicatorSize.tab,
              tabs: [
                Tab(
                  icon: Icon(Icons.person_add_alt_1_rounded, size: 20),
                  text: 'Initial Applications',
                ),
                Tab(
                  icon: Icon(Icons.sync_rounded, size: 20),
                  text: 'Profile Updates',
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildInitialApplicationsList(),
                _buildProfileUpdatesList(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInitialApplicationsList() {
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
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
                border: Border.all(color: const Color(0xFFE2E8F0)), // slate 200
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _showTherapistDetailsDialog(therapist),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        _therapistAvatar(therapist, radius: 24),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                therapist.displayName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: Color(0xFF1E293B),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                therapist.specializations.join(', '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
                              ),
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.amber.shade50,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(color: Colors.amber.shade200),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.hourglass_empty_rounded, size: 11, color: Colors.amber.shade800),
                                    const SizedBox(width: 4),
                                    Text(
                                      'PENDING',
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.amber.shade900,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                'Review',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF475569),
                                ),
                              ),
                            ),
                          ],
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
    );
  }

  Widget _buildProfileUpdatesList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('therapist_profile_updates')
          .where('status', isEqualTo: 'pending_review')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return const Center(
            child: Text('No pending profile update reviews.', style: TextStyle(color: Color(0xFF64748B))),
          );
        }

        // Sort manually by timestamp in memory since we don't have composite index yet
        final sortedDocs = List<QueryDocumentSnapshot>.from(docs)
          ..sort((a, b) {
            final aTime = (a.data() as Map)['timestamp'] as Timestamp?;
            final bTime = (b.data() as Map)['timestamp'] as Timestamp?;
            if (aTime == null || bTime == null) return 0;
            return bTime.compareTo(aTime);
          });

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: sortedDocs.length,
          separatorBuilder: (context, index) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final doc = sortedDocs[index];
            final data = doc.data() as Map<String, dynamic>;
            final therapistId = data['therapistId'] ?? '';
            final displayName = data['displayName'] ?? 'Unknown Therapist';
            final timestamp = data['timestamp'] as Timestamp?;
            final changedFields = List<String>.from(data['changedFields'] ?? []);
            final oldProfileData = data['oldProfile'] as Map<String, dynamic>? ?? {};
            final newProfileData = data['newProfile'] as Map<String, dynamic>? ?? {};

            final oldProfile = TherapistProfile.fromMap(therapistId, oldProfileData);
            final newProfile = TherapistProfile.fromMap(therapistId, newProfileData);

            final date = timestamp?.toDate() ?? DateTime.now();
            final dateStr = '${date.day}/${date.month}/${date.year}';

            return Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
                border: Border.all(color: const Color(0xFFE2E8F0)), // slate 200
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => _showProfileUpdateReviewDialog(doc.id, oldProfile, newProfile, changedFields),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        _therapistAvatar(newProfile, radius: 24),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                displayName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: Color(0xFF1E293B),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Updated: ${changedFields.join(", ")}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Submitted: $dateStr',
                                style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEFF6FF), // blue 50
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                'Review',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF1D4ED8), // blue 700
                                ),
                              ),
                            ),
                          ],
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
    );
  }

  Widget _tableHeader(String text) {
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Text(
        text,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E293B)),
      ),
    );
  }

  TableRow _diffRow(String fieldName, String oldVal, String newVal) {
    return TableRow(
      children: [
        Padding(
          padding: const EdgeInsets.all(10),
          child: Text(fieldName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF475569))),
        ),
        Padding(
          padding: const EdgeInsets.all(10),
          child: Text(oldVal.isEmpty ? 'Not set' : oldVal, style: const TextStyle(fontSize: 12, color: Color(0xFF64748B), decoration: TextDecoration.lineThrough)),
        ),
        Padding(
          padding: const EdgeInsets.all(10),
          child: Container(
            color: const Color(0xFFECFDF5), // light green
            padding: const EdgeInsets.all(4),
            child: Text(newVal.isEmpty ? 'Not set' : newVal, style: const TextStyle(fontSize: 12, color: Color(0xFF047857), fontWeight: FontWeight.w600)),
          ),
        ),
      ],
    );
  }

  TableRow _diffPhotoRow(String fieldName, String oldPhotoBase64, String newPhotoBase64) {
    Widget renderPhoto(String base64Str) {
      if (base64Str.isEmpty) return const Text('No Photo', style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic));
      try {
        final bytes = base64Decode(base64Str.trim());
        return Image.memory(bytes, width: 48, height: 48, fit: BoxFit.cover);
      } catch (_) {
        return const Text('Decoding error', style: TextStyle(fontSize: 11, color: Colors.red));
      }
    }

    return TableRow(
      children: [
        Padding(
          padding: const EdgeInsets.all(10),
          child: Text(fieldName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF475569))),
        ),
        Padding(
          padding: const EdgeInsets.all(10),
          child: renderPhoto(oldPhotoBase64),
        ),
        Padding(
          padding: const EdgeInsets.all(10),
          child: Container(
            color: const Color(0xFFECFDF5),
            padding: const EdgeInsets.all(4),
            child: renderPhoto(newPhotoBase64),
          ),
        ),
      ],
    );
  }

  TableRow _diffCertificateRow(String fieldName, String oldCertBase64, String newCertBase64) {
    Widget renderCertificateButton(String base64Str, String label) {
      if (base64Str.isEmpty) return const Text('No Certificate Uploaded', style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic));
      return TextButton.icon(
        onPressed: () {
          try {
            final pdfBytes = base64Decode(base64Str.trim());
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => CertificateViewerScreen(
                  pdfBytes: pdfBytes,
                  title: label,
                ),
              ),
            );
          } catch (e) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed to open certificate: $e')),
            );
          }
        },
        icon: const Icon(Icons.picture_as_pdf, size: 14, color: Color(0xFF11B5CF)),
        label: const Text('View Cert', style: TextStyle(fontSize: 11, color: Color(0xFF11B5CF))),
      );
    }

    return TableRow(
      children: [
        Padding(
          padding: const EdgeInsets.all(10),
          child: Text(fieldName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF475569))),
        ),
        Padding(
          padding: const EdgeInsets.all(10),
          child: renderCertificateButton(oldCertBase64, 'Previous Certificate'),
        ),
        Padding(
          padding: const EdgeInsets.all(10),
          child: Container(
            color: const Color(0xFFECFDF5),
            padding: const EdgeInsets.all(4),
            child: renderCertificateButton(newCertBase64, 'Updated Certificate'),
          ),
        ),
      ],
    );
  }

  TableRow _diffPackagesRow(String fieldName, List<TherapyPackage> oldPkgs, List<TherapyPackage> newPkgs) {
    Widget renderPackages(List<TherapyPackage> pkgs) {
      if (pkgs.isEmpty) return const Text('No packages', style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic));
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: pkgs.map((pkg) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 4.0),
            child: Text(
              '${pkg.title}: ${formatPrice(pkg.price)} (${pkg.durationMinutes}m, ${pkg.sessionsPerWeek}s/wk)',
              style: const TextStyle(fontSize: 10.5, color: Color(0xFF334155)),
            ),
          );
        }).toList(),
      );
    }

    return TableRow(
      children: [
        Padding(
          padding: const EdgeInsets.all(10),
          child: Text(fieldName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF475569))),
        ),
        Padding(
          padding: const EdgeInsets.all(10),
          child: renderPackages(oldPkgs),
        ),
        Padding(
          padding: const EdgeInsets.all(10),
          child: Container(
            color: const Color(0xFFECFDF5),
            padding: const EdgeInsets.all(4),
            child: renderPackages(newPkgs),
          ),
        ),
      ],
    );
  }

  void _showProfileUpdateReviewDialog(
    String updateDocId,
    TherapistProfile oldProfile,
    TherapistProfile newProfile,
    List<String> changedFields,
  ) {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Row(
            children: [
              _therapistAvatar(newProfile, radius: 20),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Review Profile Changes',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 700, // Make it wider for side-by-side comparison
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Compare the therapist\'s old values with their proposed updates below:',
                    style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                  ),
                  const SizedBox(height: 16),
                  Table(
                    border: TableBorder.all(color: const Color(0xFFE2E8F0), width: 1, borderRadius: BorderRadius.circular(8)),
                    columnWidths: const {
                      0: FlexColumnWidth(1.2),
                      1: FlexColumnWidth(2),
                      2: FlexColumnWidth(2),
                    },
                    children: [
                      TableRow(
                        decoration: const BoxDecoration(color: Color(0xFFF1F5F9)),
                        children: [
                          _tableHeader('Field'),
                          _tableHeader('Previous Value'),
                          _tableHeader('Updated Value'),
                        ],
                      ),
                      if (changedFields.contains('Display Name'))
                        _diffRow('Display Name', oldProfile.displayName, newProfile.displayName),
                      if (changedFields.contains('Bio'))
                        _diffRow('Bio', oldProfile.bio, newProfile.bio),
                      if (changedFields.contains('Credentials'))
                        _diffRow('Credentials', oldProfile.credentials, newProfile.credentials),
                      if (changedFields.contains('Experience'))
                        _diffRow('Experience', oldProfile.formattedExperience, newProfile.formattedExperience),
                      if (changedFields.contains('Specializations'))
                        _diffRow('Specializations', oldProfile.specializations.join(', '), newProfile.specializations.join(', ')),
                      if (changedFields.contains('Languages'))
                        _diffRow('Languages', oldProfile.languages.join(', '), newProfile.languages.join(', ')),
                      if (changedFields.contains('Availability'))
                        _diffRow('Availability', oldProfile.availability, newProfile.availability),
                      if (changedFields.contains('Pricing'))
                        _diffRow('Pricing', oldProfile.pricing, newProfile.pricing),
                      if (changedFields.contains('Profile Photo'))
                        _diffPhotoRow('Profile Photo', oldProfile.photoUrlBase64, newProfile.photoUrlBase64),
                      if (changedFields.contains('Certificate'))
                        _diffCertificateRow('Certificate', oldProfile.certificateBase64, newProfile.certificateBase64),
                      if (changedFields.contains('Packages'))
                        _diffPackagesRow('Packages', oldProfile.servicePackages, newProfile.servicePackages),
                    ],
                  ),
                ],
              ),
            ),
          ),
          actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close', style: TextStyle(color: Color(0xFF64748B))),
            ),
            const SizedBox(width: 4),
            TextButton(
              onPressed: () {
                _showRejectProfileUpdateDialog(updateDocId, oldProfile, newProfile, () {
                  Navigator.pop(ctx);
                });
              },
              style: TextButton.styleFrom(
                foregroundColor: Colors.red,
              ),
              child: const Text('Reject & Revert'),
            ),
            ElevatedButton(
              onPressed: () async {
                await _approveProfileUpdate(updateDocId, newProfile);
                if (ctx.mounted) {
                  Navigator.pop(ctx);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Approve Changes'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _approveProfileUpdate(String updateDocId, TherapistProfile newProfile) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final adminId = FirebaseAuth.instance.currentUser?.uid;
      if (adminId == null) throw StateError('No logged in admin');

      final batch = FirebaseFirestore.instance.batch();

      final logRef = FirebaseFirestore.instance.collection('therapist_profile_updates').doc(updateDocId);
      batch.update(logRef, {
        'status': 'approved',
        'reviewedAt': FieldValue.serverTimestamp(),
      });

      final auditRef = FirebaseFirestore.instance.collection('admin_audit_logs').doc();
      final log = AdminAuditLog(
        id: auditRef.id,
        adminUid: adminId,
        adminEmail: FirebaseAuth.instance.currentUser?.email ?? '',
        targetUid: newProfile.id,
        actionType: 'verify_profile_update_approved',
        details: 'Approved profile updates for therapist ${newProfile.displayName}',
        timestamp: DateTime.now(),
      );
      batch.set(auditRef, {
        ...log.toMap(),
        'timestamp': FieldValue.serverTimestamp(),
      });

      final notificationRef = FirebaseFirestore.instance.collection('notifications').doc();
      batch.set(notificationRef, {
        'userId': newProfile.id,
        'title': 'Profile Updates Approved',
        'message': 'Your recent profile updates have been reviewed and approved by the admin.',
        'category': 'verification',
        'timestamp': FieldValue.serverTimestamp(),
        'isRead': false,
        'navigationTarget': const <String, dynamic>{
          'route': 'ProfileStatus',
        },
      });

      await batch.commit();
      messenger.showSnackBar(
        const SnackBar(content: Text('Profile updates approved successfully!')),
      );
      _loadStats();
      setState(() {});
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Approval error: $e')),
      );
    }
  }

  void _showRejectProfileUpdateDialog(
    String updateDocId,
    TherapistProfile oldProfile,
    TherapistProfile newProfile,
    VoidCallback onSuccess,
  ) {
    final controller = TextEditingController();
    final messenger = ScaffoldMessenger.of(context);
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Reject Updates & Revert Profile'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'Reason for rejection',
              hintText: 'Describe why these changes are rejected and rolled back...',
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
                  final adminId = FirebaseAuth.instance.currentUser?.uid;
                  if (adminId == null) throw StateError('No logged in admin');

                  final batch = FirebaseFirestore.instance.batch();

                  final profileRef = FirebaseFirestore.instance.collection('therapist_profiles').doc(oldProfile.id);
                  final revertData = {
                    'displayName': oldProfile.displayName,
                    'bio': oldProfile.bio,
                    'credentials': oldProfile.credentials,
                    'experience_years': oldProfile.yearsOfExperience,
                    'experience_months': oldProfile.experienceMonths,
                    'specializations': oldProfile.specializations,
                    'languages': oldProfile.languages,
                    'photoUrlBase64': oldProfile.photoUrlBase64,
                    'photoUrl': oldProfile.photoUrl,
                    'certificateBase64': oldProfile.certificateBase64,
                    'pricing': oldProfile.pricing,
                    'availability': oldProfile.availability,
                    'servicePackages': oldProfile.servicePackages.map((item) => item.toMap()).toList(),
                    'hasUnacknowledgedChanges': false,
                    'unacknowledgedChangesFields': <String>[],
                    'updatedAt': FieldValue.serverTimestamp(),
                  };
                  batch.update(profileRef, revertData);

                  final userRef = FirebaseFirestore.instance.collection('users').doc(oldProfile.id);
                  final firstName = oldProfile.displayName.trim().split(' ').first;
                  final lastNameParts = oldProfile.displayName.trim().split(' ')..removeAt(0);
                  final lastName = lastNameParts.join(' ').trim();
                  final fullName = '$firstName $lastName'.trim();
                  batch.update(userRef, {
                    'firstName': firstName,
                    'lastName': lastName,
                    'fullName': fullName,
                    'updatedAt': FieldValue.serverTimestamp(),
                  });

                  final logRef = FirebaseFirestore.instance.collection('therapist_profile_updates').doc(updateDocId);
                  batch.update(logRef, {
                    'status': 'rejected',
                    'adminFeedback': reason,
                    'reviewedAt': FieldValue.serverTimestamp(),
                  });

                  final auditRef = FirebaseFirestore.instance.collection('admin_audit_logs').doc();
                  final log = AdminAuditLog(
                    id: auditRef.id,
                    adminUid: adminId,
                    adminEmail: FirebaseAuth.instance.currentUser?.email ?? '',
                    targetUid: oldProfile.id,
                    actionType: 'verify_profile_update_rejected',
                    details: 'Rejected updates & reverted fields for therapist ${oldProfile.displayName}. Reason: $reason',
                    timestamp: DateTime.now(),
                  );
                  batch.set(auditRef, {
                    ...log.toMap(),
                    'timestamp': FieldValue.serverTimestamp(),
                  });

                  final notificationRef = FirebaseFirestore.instance.collection('notifications').doc();
                  batch.set(notificationRef, {
                    'userId': oldProfile.id,
                    'title': 'Profile Updates Rejected & Reverted',
                    'message': 'Your recent profile updates were rejected by the admin and reverted. Reason: $reason',
                    'category': 'verification',
                    'timestamp': FieldValue.serverTimestamp(),
                    'isRead': false,
                    'navigationTarget': const <String, dynamic>{
                      'route': 'ProfileStatus',
                    },
                  });

                  await batch.commit();

                  if (ctx.mounted) Navigator.pop(ctx);
                  onSuccess();

                  messenger.showSnackBar(
                    const SnackBar(content: Text('Profile updates rejected and reverted successfully.')),
                  );
                  _loadStats();
                  setState(() {});
                } catch (e) {
                  messenger.showSnackBar(
                    SnackBar(content: Text('Rejection error: $e')),
                  );
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
              child: const Text('Reject & Revert'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _approveVerification(String therapistId, {VoidCallback? onSuccess}) async {
    _showApproveVerificationDialog(therapistId, onSuccess: onSuccess);
  }

  void _showApproveVerificationDialog(String therapistId, {VoidCallback? onSuccess}) {
    final sourceController = TextEditingController();
    final urlController = TextEditingController();
    String? imageBase64;
    String? imageName;
    bool isSaving = false;
    final messenger = ScaffoldMessenger.of(context);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Text('Approve Therapist & Upload Evidence'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Please provide official verification details and evidence to approve this therapist.',
                      style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: sourceController,
                      decoration: const InputDecoration(
                        labelText: 'Verification Source / Website *',
                        hintText: 'e.g. PMDC/AHPC Register, Licensing Board',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: urlController,
                      decoration: const InputDecoration(
                        labelText: 'Verification URL (Optional)',
                        hintText: 'e.g. https://website.com/verify/123',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Evidence Screenshot *',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    if (imageBase64 != null) ...[
                      Container(
                        height: 120,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.memory(
                            base64Decode(imageBase64!),
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        imageName ?? 'Screenshot attached',
                        style: const TextStyle(fontSize: 11, color: Colors.green, fontWeight: FontWeight.w500),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ] else
                      Container(
                        width: double.infinity,
                        height: 60,
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          border: Border.all(color: const Color(0xFFCBD5E1), style: BorderStyle.solid),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Center(
                          child: Text(
                            'No evidence screenshot uploaded',
                            style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                          ),
                        ),
                      ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final picker = ImagePicker();
                        final XFile? image = await picker.pickImage(source: ImageSource.gallery);
                        if (image == null) return;
                        final bytes = await image.readAsBytes();
                        setDialogState(() {
                          imageBase64 = base64Encode(bytes);
                          imageName = image.name;
                        });
                      },
                      icon: const Icon(Icons.upload_file_rounded),
                      label: const Text('Select Evidence Screenshot'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(40),
                        side: const BorderSide(color: Color(0xFF10B981)),
                        foregroundColor: const Color(0xFF10B981),
                      ),
                    ),
                    if (isSaving) ...[
                      const SizedBox(height: 16),
                      const Center(
                        child: CircularProgressIndicator(color: Color(0xFF10B981)),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.pop(ctx),
                  child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
                ),
                ElevatedButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          final source = sourceController.text.trim();
                          final url = urlController.text.trim();

                          if (imageBase64 == null || imageBase64!.isEmpty || source.isEmpty) {
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text('Please upload verification evidence and specify the verification source before approving this therapist.'),
                                backgroundColor: Color(0xFFFF4D4D),
                                duration: Duration(seconds: 4),
                              ),
                            );
                            return;
                          }

                          setDialogState(() {
                            isSaving = true;
                          });

                          try {
                            await AppRepositories.admin.verifyTherapist(
                              therapistId: therapistId,
                              status: 'approved',
                              adminFeedback: 'Approved by administrator. Verification source: $source.',
                              verificationImageBase64: imageBase64,
                              verificationSource: source,
                              verificationUrl: url,
                            );
                            if (ctx.mounted) Navigator.pop(ctx);
                            messenger.showSnackBar(
                              const SnackBar(content: Text('Therapist approved successfully.')),
                            );
                            if (onSuccess != null) onSuccess();
                            _loadStats();
                            setState(() {});
                          } catch (e) {
                            setDialogState(() {
                              isSaving = false;
                            });
                            messenger.showSnackBar(
                              SnackBar(content: Text('Verification error: $e'), backgroundColor: const Color(0xFFFF4D4D)),
                            );
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Confirm Approval'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showRejectVerificationDialog(String therapistId, {VoidCallback? onSuccess}) {
    final controller = TextEditingController();
    final messenger = ScaffoldMessenger.of(context);
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                  if (onSuccess != null) onSuccess();
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
                    const Text('Complete Conversation Context:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    Container(
                      padding: const EdgeInsets.all(8),
                      margin: const EdgeInsets.only(top: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: report.chatContext.map((msg) => _buildContextMessage(msg)).toList(),
                      ),
                    ),
                  ],
                  if (pending) ...[
                    const SizedBox(height: 14),
                    ElevatedButton(
                      onPressed: () => _showModerationDialog(report.reportedId, report.id),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                      child: const Text('Moderate / Resolve'),
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

  void _showModerationDialog(String userId, String reportId) {
    // Determine the target's role by looking up in Firestore asynchronously.
    // We start with loading the role before opening the dialog so we can pass
    // it to applyModerationAction.
    _showModerationDialogWithRole(userId, reportId, null);
  }

  Future<void> _showModerationDialogWithRole(String userId, String reportId, String? knownRole) async {
    String targetRole = knownRole ?? 'parent';

    if (knownRole == null) {
      try {
        final tDoc = await FirebaseFirestore.instance
            .collection('therapist_profiles')
            .doc(userId)
            .get();
        if (tDoc.exists) {
          targetRole = 'therapist';
        }
      } catch (_) {}
    }

    if (!mounted) return;

    final reasonController = TextEditingController();
    final descriptionController = TextEditingController();
    final messenger = ScaffoldMessenger.of(context);
    String selectedAction = 'warn';
    String requestFrom = 'reporter';
    int restrictionDays = 4;
    String? otherPartyId;

    // For 'restrict', we need the other party's ID from the report
    if (reportId.isNotEmpty) {
      try {
        final reportDoc = await FirebaseFirestore.instance
            .collection('reports')
            .doc(reportId)
            .get();
        final data = reportDoc.data() ?? {};
        final reporterId = data['reporterId']?.toString() ?? '';
        final reportedId = data['reportedId']?.toString() ?? '';
        // The other party is whoever is NOT the target
        otherPartyId = (reportedId == userId) ? reporterId : reportedId;
      } catch (_) {}
    }

    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final isRestrict = selectedAction == 'restrict';
            final isRequestInfo = selectedAction == 'request_info';
            final isSuspendOrBan = selectedAction == 'suspend' || selectedAction == 'ban';

            Color actionColor = const Color(0xFF0F766E); // teal
            if (isSuspendOrBan) actionColor = const Color(0xFFDC2626);
            if (selectedAction == 'warn') actionColor = const Color(0xFFD97706);
            if (isRestrict) actionColor = const Color(0xFF7C3AED);

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              title: Row(
                children: [
                  Icon(Icons.gavel_rounded, color: actionColor, size: 22),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Apply Moderation Action',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                    ),
                  ),
                ],
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Target: ${targetRole == 'therapist' ? '🩺 Therapist' : '👨‍👩‍👧 Parent'}',
                            style: const TextStyle(fontSize: 12, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                          ),
                          Text(
                            'User ID: ${userId.length > 16 ? '${userId.substring(0, 16)}\u2026' : userId}',
                            style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Action selector
                    const Text('Action', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: selectedAction,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'no_action', child: Text('✅ No Action Required', overflow: TextOverflow.ellipsis)),
                        DropdownMenuItem(value: 'warn', child: Text('⚠️ Issue Warning', overflow: TextOverflow.ellipsis)),
                        DropdownMenuItem(value: 'restrict', child: Text('🔒 Temporary Restriction', overflow: TextOverflow.ellipsis)),
                        DropdownMenuItem(value: 'suspend', child: Text('🔴 Suspend Account', overflow: TextOverflow.ellipsis)),
                        DropdownMenuItem(value: 'ban', child: Text('⛔ Permanent Ban', overflow: TextOverflow.ellipsis)),
                        DropdownMenuItem(value: 'request_info', child: Text('📋 Request Additional Info', overflow: TextOverflow.ellipsis)),
                      ],
                      onChanged: (val) {
                        if (val != null) {
                          setDialogState(() => selectedAction = val);
                        }
                      },
                    ),
                    const SizedBox(height: 14),

                    // Restriction duration picker (only for 'restrict')
                    if (isRestrict) ...[
                      const Text('Restriction Duration (days)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: Slider(
                              value: restrictionDays.toDouble(),
                              min: 1,
                              max: 30,
                              divisions: 29,
                              label: '$restrictionDays days',
                              activeColor: const Color(0xFF7C3AED),
                              onChanged: (val) => setDialogState(() => restrictionDays = val.round()),
                            ),
                          ),
                          Container(
                            width: 50,
                            alignment: Alignment.center,
                            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFEDE9FE),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '$restrictionDays',
                              style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF7C3AED), fontSize: 14),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                    ],

                    // Request info options
                    if (isRequestInfo) ...[
                      const Text('Request Information From', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: requestFrom,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'reporter', child: Text('Reporter only')),
                          DropdownMenuItem(value: 'reported', child: Text('Reported user only')),
                          DropdownMenuItem(value: 'both', child: Text('Both parties')),
                        ],
                        onChanged: (val) {
                          if (val != null) setDialogState(() => requestFrom = val);
                        },
                      ),
                      const SizedBox(height: 10),
                      const Text('What information do you need?', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: descriptionController,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          hintText: 'Describe what additional information is needed...',
                          contentPadding: const EdgeInsets.all(10),
                        ),
                        maxLines: 3,
                      ),
                      const SizedBox(height: 10),
                    ],

                    // Mandatory reason field
                    Row(
                      children: [
                        const Text('Reason', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                        if (selectedAction != 'no_action')
                          const Text(' *', style: TextStyle(color: Color(0xFFDC2626), fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: reasonController,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        hintText: selectedAction == 'no_action'
                            ? 'Optional: reason for no action...'
                            : 'Mandatory: explain the reason for this action...',
                        contentPadding: const EdgeInsets.all(10),
                      ),
                      maxLines: 3,
                    ),

                    // Warning for destructive actions
                    if (isSuspendOrBan) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEF2F2),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFFCA5A5)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626), size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                selectedAction == 'ban'
                                    ? '⛔ PERMANENT BAN: This action is irreversible. All subscriptions will be cancelled and the user will be permanently locked out.'
                                    : '🔴 SUSPENSION: All subscriptions and bookings will be cancelled. The account will be disabled immediately.',
                                style: const TextStyle(fontSize: 11, color: Color(0xFF7F1D1D)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: actionColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () async {
                    final reason = reasonController.text.trim();
                    if (selectedAction != 'no_action' && reason.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Please enter a reason before proceeding.'),
                          backgroundColor: Color(0xFFDC2626),
                        ),
                      );
                      return;
                    }

                    // Double-confirmation for suspend/ban
                    if (isSuspendOrBan) {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (confirmCtx) => AlertDialog(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          title: Text(
                            selectedAction == 'ban' ? '⛔ Confirm Permanent Ban' : '🔴 Confirm Suspension',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          content: Text(
                            selectedAction == 'ban'
                                ? 'This user will be permanently banned from the platform. '
                                  'All subscriptions, bookings, and access will be terminated immediately. '
                                  'This action cannot be undone automatically.\n\nAre you absolutely sure?'
                                : 'This user will be suspended and signed out from all devices immediately. '
                                  'All active subscriptions and bookings will be cancelled.\n\nAre you sure?',
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(confirmCtx, false),
                              child: const Text('Go Back'),
                            ),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFFDC2626),
                                foregroundColor: Colors.white,
                              ),
                              onPressed: () => Navigator.pop(confirmCtx, true),
                              child: Text(selectedAction == 'ban' ? 'Yes, Ban Permanently' : 'Yes, Suspend'),
                            ),
                          ],
                        ),
                      );
                      if (confirm != true) return;
                    }

                    if (ctx.mounted) Navigator.pop(ctx);

                    // Show loading snackbar
                    messenger.showSnackBar(
                      const SnackBar(
                        content: Row(
                          children: [
                            SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)),
                            SizedBox(width: 12),
                            Text('Applying moderation action...'),
                          ],
                        ),
                        duration: Duration(seconds: 30),
                      ),
                    );

                    try {
                      if (isRequestInfo) {
                        await AppRepositories.admin.requestAdditionalInfo(
                          reportId: reportId,
                          requestFrom: requestFrom,
                          reason: reason.isEmpty ? 'Additional information required.' : reason,
                          description: descriptionController.text.trim(),
                        );
                      } else {
                        await AppRepositories.admin.applyModerationAction(
                          targetUserId: userId,
                          targetRole: targetRole,
                          action: selectedAction,
                          reason: reason.isEmpty ? 'No additional reason provided.' : reason,
                          reportId: reportId.isEmpty ? null : reportId,
                          restrictedWithUserId: isRestrict ? otherPartyId : null,
                          restrictionDays: isRestrict ? restrictionDays : null,
                        );
                      }

                      await _loadStats();
                      setState(() {});
                      messenger.hideCurrentSnackBar();
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text('Action applied: "$selectedAction"'),
                          backgroundColor: const Color(0xFF059669),
                        ),
                      );
                    } catch (e) {
                      messenger.hideCurrentSnackBar();
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text('Failed: $e'),
                          backgroundColor: const Color(0xFFDC2626),
                        ),
                      );
                    }
                  },
                  child: const Text('Apply Action'),
                ),
              ],
            );
          },
        );
      },
    );
  }



  void _showParentDetailsDialog(UserProfile parent, List<ChildProfile> children) {
    showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          clipBehavior: Clip.hardEdge,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Gradient header ─────────────────────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF0F172A), Color(0xFF1E3A5F)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _parentAvatar(parent, radius: 32),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            parent.fullName,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'TIER: ${parent.subscriptionTier.toUpperCase()}',
                            style: const TextStyle(fontSize: 13, color: Color(0xFF38BDF8), fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: parent.status == 'active' || parent.status == 'verified'
                                      ? const Color(0xFFD1FAE5)
                                      : const Color(0xFFFEF3C7),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  parent.status.toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    color: parent.status == 'active' || parent.status == 'verified'
                                        ? const Color(0xFF059669)
                                        : const Color(0xFFD97706),
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              _moderationStatusBadge(_resolveModerationStatus(parent.status, parent.moderationStatus, parent.hasActiveRestrictions)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close_rounded, color: Colors.white54, size: 22),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),

              // ── Scrollable body ────────────────────────────────────
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Account Details section ──────────────────
                      _dialogSectionHeader(Icons.account_box_outlined, 'Account Details'),
                      const SizedBox(height: 10),
                      _infoCard([
                        _infoTile(Icons.badge_outlined, 'User ID', parent.uid, mono: true),
                        _infoTile(Icons.email_outlined, 'Email Address', parent.email),
                        _infoTile(Icons.phone_outlined, 'Phone Number', parent.phone.isEmpty ? 'Not set' : parent.phone),
                        _infoTile(Icons.calendar_month_outlined, 'Registered On', parent.createdAt != null ? '${parent.createdAt!.day}/${parent.createdAt!.month}/${parent.createdAt!.year}' : 'N/A'),
                      ]),

                      // ── Children Profile ────────────────────────────
                      const SizedBox(height: 16),
                      _dialogSectionHeader(Icons.child_care_rounded, 'Children Profile'),
                      const SizedBox(height: 10),
                      if (children.isEmpty)
                        const Text(
                          'No children profile setup yet.',
                          style: TextStyle(fontStyle: FontStyle.italic, color: Color(0xFF64748B), fontSize: 12),
                        )
                      else
                        ...children.map((c) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(c.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1E293B))),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    const Text('Support Areas: ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF64748B))),
                                    Expanded(
                                      child: Text(
                                        c.supportAreas.join(", "),
                                        style: const TextStyle(fontSize: 12, color: Color(0xFF475569)),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    const Text('Status: ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF64748B))),
                                    Text(
                                      c.status.toUpperCase(),
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: c.status == 'active' ? const Color(0xFF059669) : const Color(0xFFD97706),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        )),


                      // ── Moderation Management ──────────────────────
                      const SizedBox(height: 20),
                      _dialogSectionHeader(Icons.gavel_rounded, 'Moderation Management'),
                      const SizedBox(height: 10),
                      _ModerationPanel(
                        userId: parent.uid,
                        userRole: 'parent',
                        currentStatus: _resolveModerationStatus(parent.status, parent.moderationStatus, parent.hasActiveRestrictions),
                        onActionTaken: () {
                          Navigator.pop(ctx);
                          _loadStats();
                          setState(() {});
                        },
                        onOpenDialog: (uid, role) {
                          Navigator.pop(ctx);
                          _showModerationDialogWithRole(uid, '', role);
                        },
                      ),

                      // ── Moderation History / Timeline ──────────────
                      const SizedBox(height: 20),
                      _dialogSectionHeader(Icons.history_rounded, 'Moderation Timeline'),
                      const SizedBox(height: 10),
                      _ModerationTimeline(userId: parent.uid),

                      // ── Admin Message ─────────────────────────────
                      const SizedBox(height: 20),
                      _dialogSectionHeader(Icons.send_rounded, 'Send Message'),
                      const SizedBox(height: 10),
                      _AdminMessageSender(recipientId: parent.uid, recipientType: 'Parent'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: Color(0xFF64748B)),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13, color: Color(0xFF1E293B)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildParentsTab() {
    return DefaultTabController(
      length: 5,
      child: Column(
        children: [
          Container(
            color: Colors.white,
            child: const TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelColor: Color(0xFF1E293B),
              unselectedLabelColor: Color(0xFF64748B),
              indicatorColor: Color(0xFF38BDF8),
              indicatorSize: TabBarIndicatorSize.tab,
              tabs: [
                Tab(text: 'All'),
                Tab(text: '⚠️ Warned'),
                Tab(text: '🔒 Restricted'),
                Tab(text: '🔴 Suspended'),
                Tab(text: '⛔ Banned'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildParentList(''),
                _buildParentList('warned'),
                _buildParentList('restricted'),
                _buildParentList('suspended'),
                _buildParentList('banned'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildParentList(String filterStatus) {
    return FutureBuilder<List<UserProfile>>(
      future: filterStatus.isEmpty
          ? AppRepositories.admin.listParents()
          : AppRepositories.admin.listParentsByModerationStatus(filterStatus),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final list = snapshot.data ?? [];
        if (list.isEmpty) {
          return Center(
            child: Text(
              filterStatus.isEmpty ? 'No parent profiles found.' : 'No $filterStatus parents.',
              style: const TextStyle(color: Color(0xFF64748B)),
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: list.length,
          separatorBuilder: (context, index) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final parent = list[index];
            final modStatus = _resolveModerationStatus(parent.status, parent.moderationStatus, parent.hasActiveRestrictions);

            return Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              elevation: 0,
              child: InkWell(
                onTap: () async {
                  final scaffoldMessenger = ScaffoldMessenger.of(context);
                  try {
                    final children = await AppRepositories.users.getChildrenForParent(parent.uid);
                    if (context.mounted) {
                      _showParentDetailsDialog(parent, children);
                    }
                  } catch (e) {
                    scaffoldMessenger.showSnackBar(
                      SnackBar(content: Text('Error loading details: $e')),
                    );
                  }
                },
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Header strip ────────────────────────────────
                      Container(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                        ),
                        child: Row(
                          children: [
                            _parentAvatar(parent, radius: 26),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    parent.fullName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    'Tier: ${parent.subscriptionTier.toUpperCase()}',
                                    style: const TextStyle(fontSize: 11, color: Color(0xFF38BDF8), fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ),
                            _moderationStatusBadge(modStatus),
                          ],
                        ),
                      ),
                      // ── Body ────────────────────────────────────────
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.email_outlined, size: 14, color: Color(0xFF64748B)),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    parent.email,
                                    style: const TextStyle(fontSize: 13.5, color: Color(0xFF475569)),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                const Icon(Icons.phone_outlined, size: 14, color: Color(0xFF64748B)),
                                const SizedBox(width: 6),
                                Text(
                                  parent.phone.isEmpty ? 'Not set' : parent.phone,
                                  style: const TextStyle(fontSize: 13.5, color: Color(0xFF475569)),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      // ── Tap hint ────────────────────────────────────
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: const BoxDecoration(
                          color: Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
                          border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
                        ),
                        child: const Center(
                          child: Text(
                            'Tap to view full profile & moderate',
                            style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
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

  String _getRelativeTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inSeconds < 5) {
      return 'just now';
    } else if (difference.inSeconds < 60) {
      return '${difference.inSeconds}s ago';
    } else if (difference.inMinutes < 60) {
      final min = difference.inMinutes;
      return '$min minute${min == 1 ? "" : "s"} ago';
    } else if (difference.inHours < 24) {
      final hours = difference.inHours;
      return '$hours hour${hours == 1 ? "" : "s"} ago';
    } else if (difference.inDays < 7) {
      final days = difference.inDays;
      return '$days day${days == 1 ? "" : "s"} ago';
    } else {
      return '${dateTime.day.toString().padLeft(2, '0')}/${dateTime.month.toString().padLeft(2, '0')}/${dateTime.year}';
    }
  }

  Widget _buildAuditLogsTab() {
    _auditLogsFuture ??= AppRepositories.admin.listAuditLogs();

    return FutureBuilder<List<AdminAuditLog>>(
      future: _auditLogsFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        
        final list = snapshot.data ?? [];

        // Filter the list in memory
        final filteredList = list.where((log) {
          final query = _auditSearchQuery.trim().toLowerCase();
          final matchesSearch = query.isEmpty ||
              log.details.toLowerCase().contains(query) ||
              log.adminEmail.toLowerCase().contains(query) ||
              log.targetUid.toLowerCase().contains(query) ||
              log.actionType.toLowerCase().contains(query);

          bool matchesFilter = true;
          if (_auditFilterType == 'Verification') {
            matchesFilter = log.actionType.startsWith('verify');
          } else if (_auditFilterType == 'Moderation') {
            matchesFilter = log.actionType.startsWith('moderation');
          } else if (_auditFilterType == 'Reports') {
            matchesFilter = log.actionType.startsWith('update_report_status');
          } else if (_auditFilterType == 'Other') {
            matchesFilter = !log.actionType.startsWith('verify') &&
                !log.actionType.startsWith('moderation') &&
                !log.actionType.startsWith('update_report_status');
          }

          return matchesSearch && matchesFilter;
        }).toList();

        return Column(
          children: [
            // Search and filter headers
            Container(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(
                  bottom: BorderSide(color: Color(0xFFE2E8F0)),
                ),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _auditSearchController,
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF64748B), size: 20),
                            hintText: 'Search by admin email, target ID, details...',
                            hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13.5),
                            fillColor: const Color(0xFFF8FAFC),
                            filled: true,
                            contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Color(0xFF3B82F6), width: 1.5),
                            ),
                            suffixIcon: _auditSearchQuery.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear_rounded, color: Color(0xFF64748B), size: 18),
                                    onPressed: () {
                                      _auditSearchController.clear();
                                    },
                                  )
                                : null,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE2E8F0)),
                        ),
                        child: IconButton(
                          icon: const Icon(Icons.download_rounded, color: Color(0xFF475569), size: 22),
                          onPressed: () => _exportAuditLogs(filteredList),
                          tooltip: 'Export filtered logs to CSV',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: ['All', 'Verification', 'Moderation', 'Reports', 'Other'].map((type) {
                        final isSelected = _auditFilterType == type;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(
                              type,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: isSelected ? Colors.white : const Color(0xFF475569),
                              ),
                            ),
                            selected: isSelected,
                            selectedColor: const Color(0xFF1E293B),
                            backgroundColor: const Color(0xFFF1F5F9),
                            onSelected: (selected) {
                              if (selected) {
                                setState(() {
                                  _auditFilterType = type;
                                });
                              }
                            },
                            checkmarkColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                              side: BorderSide(
                                color: isSelected ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
            // Audit list
            Expanded(
              child: filteredList.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.find_in_page_outlined, size: 48, color: Color(0xFF94A3B8)),
                            const SizedBox(height: 12),
                            Text(
                              list.isEmpty ? 'No audit logs available.' : 'No matching audit logs found.',
                              style: const TextStyle(color: Color(0xFF64748B), fontSize: 14),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: filteredList.length,
                      itemBuilder: (context, index) {
                        final log = filteredList[index];
                        final date = log.timestamp;

                        // Determine visual style based on log properties
                        final isVerification = log.actionType.startsWith('verify');
                        final isModeration = log.actionType.startsWith('moderation');
                        final isReport = log.actionType.startsWith('update_report_status');
                        
                        Color sideColor = const Color(0xFF64748B); // Slate default
                        Color badgeBg = const Color(0xFFF1F5F9);
                        Color badgeText = const Color(0xFF475569);
                        IconData logIcon = Icons.info_outline_rounded;

                        if (isVerification) {
                          final isApproved = log.details.toLowerCase().contains('approved');
                          sideColor = isApproved ? const Color(0xFF10B981) : const Color(0xFF3B82F6); // Green or Blue
                          badgeBg = isApproved ? const Color(0xFFECFDF5) : const Color(0xFFEFF6FF);
                          badgeText = isApproved ? const Color(0xFF047857) : const Color(0xFF1D4ED8);
                          logIcon = isApproved ? Icons.verified_user_rounded : Icons.admin_panel_settings_rounded;
                        } else if (isModeration) {
                          final isWarn = log.actionType.contains('warn');
                          sideColor = isWarn ? const Color(0xFFF59E0B) : const Color(0xFFEF4444); // Amber or Red
                          badgeBg = isWarn ? const Color(0xFFFFFBEB) : const Color(0xFFFEF2F2);
                          badgeText = isWarn ? const Color(0xFFB45309) : const Color(0xFF991B1B);
                          logIcon = isWarn ? Icons.warning_amber_rounded : Icons.gavel_rounded;
                        } else if (isReport) {
                          sideColor = const Color(0xFF8B5CF6); // Purple
                          badgeBg = const Color(0xFFF5F3FF);
                          badgeText = const Color(0xFF6D28D9);
                          logIcon = Icons.flag_rounded;
                        }

                        final dateStr = '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
                        final relativeTime = _getRelativeTime(date);
                        final displayTime = (relativeTime.contains('ago') || relativeTime == 'just now')
                            ? relativeTime
                            : dateStr;

                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.02),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: IntrinsicHeight(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  // Left side color border indicator
                                  Container(
                                    width: 6,
                                    color: sideColor,
                                  ),
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Icon(logIcon, size: 16, color: sideColor),
                                              const SizedBox(width: 6),
                                              Flexible(
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                                  decoration: BoxDecoration(
                                                    color: badgeBg,
                                                    borderRadius: BorderRadius.circular(6),
                                                  ),
                                                  child: Text(
                                                    log.actionType.toUpperCase(),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      fontSize: 9,
                                                      fontWeight: FontWeight.bold,
                                                      color: badgeText,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 6),
                                              Expanded(
                                                child: Text(
                                                  displayTime,
                                                  style: const TextStyle(fontSize: 10, color: Color(0xFF64748B)),
                                                  textAlign: TextAlign.end,
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 10),
                                          Text(
                                            log.details,
                                            style: const TextStyle(
                                              fontSize: 14,
                                              color: Color(0xFF1E293B),
                                              fontWeight: FontWeight.w500,
                                              height: 1.35,
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          const Divider(height: 1, color: Color(0xFFF1F5F9)),
                                          const SizedBox(height: 10),
                                          // Admin Email Row
                                          InkWell(
                                            onTap: () {
                                              final email = log.adminEmail.isNotEmpty
                                                  ? log.adminEmail
                                                  : (log.adminUid.isNotEmpty ? log.adminUid : 'System');
                                              Clipboard.setData(ClipboardData(text: email));
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                SnackBar(
                                                  content: Text('Copied admin info: $email'),
                                                  duration: const Duration(seconds: 1),
                                                ),
                                              );
                                            },
                                            borderRadius: BorderRadius.circular(6),
                                            child: Padding(
                                              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
                                              child: Row(
                                                children: [
                                                  const Icon(Icons.person_outline_rounded, size: 14, color: Color(0xFF64748B)),
                                                  const SizedBox(width: 6),
                                                  Expanded(
                                                    child: Text(
                                                      'Admin: ${log.adminEmail.isNotEmpty ? log.adminEmail : (log.adminUid.isNotEmpty ? log.adminUid : "System")}',
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 4),
                                                  const Icon(Icons.copy_all_rounded, size: 12, color: Color(0xFF94A3B8)),
                                                ],
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          // Target UID Row
                                          InkWell(
                                            onTap: () => _inspectTarget(log.targetUid),
                                            borderRadius: BorderRadius.circular(6),
                                            child: Padding(
                                              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
                                              child: Row(
                                                children: [
                                                  const Icon(Icons.badge_outlined, size: 14, color: Color(0xFF64748B)),
                                                  const SizedBox(width: 6),
                                                  Expanded(
                                                    child: Text(
                                                      'Target: ${log.targetUid}',
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 4),
                                                  const Icon(Icons.manage_search_rounded, size: 14, color: Color(0xFF3B82F6)),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _therapistAvatar(TherapistProfile therapist, {double radius = 24}) {
    if (therapist.photoUrlBase64.isNotEmpty) {
      try {
        final bytes = base64Decode(therapist.photoUrlBase64.trim());
        return CircleAvatar(
          radius: radius,
          backgroundColor: const Color(0xFFE2E8F0),
          backgroundImage: MemoryImage(bytes),
        );
      } catch (e) {
        debugPrint('Error decoding base64 therapist photo: $e');
      }
    }
    // Fallback to name initials
    return CircleAvatar(
      radius: radius,
      backgroundColor: const Color(0xFFE0F2FE), // light blue
      child: Text(
        therapist.displayName.isNotEmpty ? therapist.displayName[0].toUpperCase() : 'T',
        style: TextStyle(
          color: const Color(0xFF0284C7),
          fontWeight: FontWeight.bold,
          fontSize: radius * 0.8,
        ),
      ),
    );
  }

  Widget _parentAvatar(UserProfile parent, {double radius = 24}) {
    if (parent.photoUrl.isNotEmpty) {
      if (parent.photoUrl.startsWith('http://') || parent.photoUrl.startsWith('https://')) {
        return CircleAvatar(
          radius: radius,
          backgroundColor: const Color(0xFFE2E8F0),
          backgroundImage: NetworkImage(parent.photoUrl),
        );
      }
      try {
        final bytes = base64Decode(parent.photoUrl.trim());
        return CircleAvatar(
          radius: radius,
          backgroundColor: const Color(0xFFE2E8F0),
          backgroundImage: MemoryImage(bytes),
        );
      } catch (e) {
        debugPrint('Error decoding base64 parent photo: $e');
      }
    }
    // Fallback to name initials
    return CircleAvatar(
      radius: radius,
      backgroundColor: const Color(0xFFEFF6FF), // light blue
      child: Text(
        parent.firstName.isNotEmpty ? parent.firstName[0].toUpperCase() : 'P',
        style: TextStyle(
          color: const Color(0xFF2563EB),
          fontWeight: FontWeight.bold,
          fontSize: radius * 0.8,
        ),
      ),
    );
  }

  void _showTherapistDetailsDialog(TherapistProfile therapist) {
    showDialog(
      context: context,
      builder: (ctx) {
        Color statusBg;
        Color statusTextColor;
        String statusLabel;
        switch (therapist.verificationStatus) {
          case 'approved':
            statusBg = Colors.green.shade100;
            statusTextColor = Colors.green.shade900;
            statusLabel = 'APPROVED';
            break;
          case 'rejected':
            statusBg = Colors.red.shade100;
            statusTextColor = Colors.red.shade900;
            statusLabel = 'REJECTED';
            break;
          default:
            statusBg = Colors.amber.shade100;
            statusTextColor = Colors.amber.shade900;
            statusLabel = 'PENDING VERIFICATION';
        }

        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              _therapistAvatar(therapist, radius: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      therapist.displayName,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: statusBg,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        statusLabel,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: statusTextColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (therapist.bio.isNotEmpty) ...[
                    const Text(
                      'About / Bio',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1E293B)),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      therapist.bio,
                      style: const TextStyle(fontSize: 13, color: Color(0xFF475569), height: 1.4),
                    ),
                    const SizedBox(height: 12),
                  ],
                  const Text(
                    'Professional Qualifications',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1E293B)),
                  ),
                  const Divider(),
                  _detailRow('Specializations', therapist.specializations.join(', ')),
                  _detailRow('Experience', therapist.formattedExperience),
                  if (therapist.experienceDetails.isNotEmpty)
                    _detailRow('Experience Details', therapist.experienceDetails),
                  if (therapist.credentials.isNotEmpty)
                    _detailRow('Credentials', therapist.credentials),
                  if (therapist.servicePackages.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Text(
                      'Service Packages',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1E293B)),
                    ),
                    const Divider(),
                    ...therapist.servicePackages.map((pkg) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8.0),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Text(
                                      pkg.title,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1E293B)),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    formatPrice(pkg.price),
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF10B981)),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${pkg.durationMinutes} mins | ${pkg.sessionsPerWeek} sessions/week',
                                style: const TextStyle(fontSize: 12, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                              ),
                              if (pkg.description.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(
                                  pkg.description,
                                  style: const TextStyle(fontSize: 12, color: Color(0xFF475569)),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
                  if (therapist.certificateBase64.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Text(
                      'Verification Documents',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1E293B)),
                    ),
                    const Divider(),
                    OutlinedButton.icon(
                      onPressed: () async {
                        try {
                          final pdfBytes = base64Decode(therapist.certificateBase64.trim());
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => CertificateViewerScreen(
                                pdfBytes: pdfBytes,
                                title: '${therapist.displayName} - Certificate',
                              ),
                            ),
                          );
                        } catch (e) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Failed to open certificate: $e')),
                          );
                        }
                      },
                      icon: const Icon(Icons.picture_as_pdf, color: Color(0xFF11B5CF)),
                      label: const Text('View Professional Certificate'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(40),
                        side: const BorderSide(color: Color(0xFF11B5CF)),
                        foregroundColor: const Color(0xFF11B5CF),
                      ),
                    ),
                  ],
                  FutureBuilder<DocumentSnapshot>(
                    future: FirebaseFirestore.instance
                        .collection('therapist_verification_evidence')
                        .doc(therapist.id)
                        .get(),
                    builder: (context, evSnapshot) {
                      if (evSnapshot.connectionState == ConnectionState.waiting) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12.0),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      if (evSnapshot.hasData && evSnapshot.data!.exists) {
                        final data = evSnapshot.data!.data() as Map<String, dynamic>? ?? {};
                        final source = data['source']?.toString() ?? 'N/A';
                        final url = data['url']?.toString() ?? '';
                        final adminEmail = data['adminEmail']?.toString() ?? 'N/A';
                        final ts = data['timestamp'] as Timestamp?;
                        final dateStr = ts != null
                            ? '${ts.toDate().day.toString().padLeft(2, '0')}/${ts.toDate().month.toString().padLeft(2, '0')}/${ts.toDate().year} ${ts.toDate().hour.toString().padLeft(2, '0')}:${ts.toDate().minute.toString().padLeft(2, '0')}'
                            : 'N/A';
                        final imageBase64 = data['imageBase64']?.toString() ?? '';

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 16),
                            const Text(
                              'Verification Evidence',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1E293B)),
                            ),
                            const Divider(),
                            _detailRow('Status', therapist.verificationStatus.toUpperCase()),
                            _detailRow('Verification Date', dateStr),
                            _detailRow('Approved By', adminEmail),
                            _detailRow('Source/Website', source),
                            if (url.isNotEmpty) _detailRow('Verification URL', url),
                            if (imageBase64.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              const Text(
                                'Verification Image/Screenshot:',
                                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Color(0xFF475569)),
                              ),
                              const SizedBox(height: 6),
                              Container(
                                decoration: BoxDecoration(
                                  border: Border.all(color: const Color(0xFFE2E8F0)),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.memory(
                                    base64Decode(imageBase64),
                                    fit: BoxFit.contain,
                                    errorBuilder: (context, err, stack) => const Padding(
                                      padding: EdgeInsets.all(8.0),
                                      child: Text('Error loading verification image'),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                ],
              ),
            ),
          ),
          actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close', style: TextStyle(color: Color(0xFF64748B))),
            ),
            const SizedBox(width: 4),
            TextButton(
              onPressed: () {
                _showRejectVerificationDialog(
                  therapist.id,
                  onSuccess: () {
                    Navigator.pop(ctx); // Close the details dialog
                  },
                );
              },
              style: TextButton.styleFrom(
                foregroundColor: Colors.red,
              ),
              child: const Text('Reject'),
            ),
            ElevatedButton(
              onPressed: () async {
                await _approveVerification(
                  therapist.id,
                  onSuccess: () {
                    if (ctx.mounted) {
                      Navigator.pop(ctx); // Close the details dialog
                    }
                  },
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Approve'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTherapistsTab() {
    return DefaultTabController(
      length: 5,
      child: Column(
        children: [
          Container(
            color: Colors.white,
            child: const TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelColor: Color(0xFF1E293B),
              unselectedLabelColor: Color(0xFF64748B),
              indicatorColor: Color(0xFF38BDF8),
              indicatorSize: TabBarIndicatorSize.tab,
              tabs: [
                Tab(text: 'All'),
                Tab(text: '⚠️ Warned'),
                Tab(text: '🔒 Restricted'),
                Tab(text: '🔴 Suspended'),
                Tab(text: '⛔ Banned'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildTherapistList(''),
                _buildTherapistList('warned'),
                _buildTherapistList('restricted'),
                _buildTherapistList('suspended'),
                _buildTherapistList('banned'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTherapistList(String filterStatus) {
    return FutureBuilder<List<TherapistProfile>>(
      future: filterStatus.isEmpty
          ? AppRepositories.admin.listTherapistsByStatus('')
          : AppRepositories.admin.listTherapistsByModerationStatus(filterStatus),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final list = snapshot.data ?? [];
        if (list.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.person_search_rounded, size: 56, color: Colors.grey.shade300),
                const SizedBox(height: 12),
                Text(
                  filterStatus.isEmpty ? 'No therapist profiles found.' : 'No $filterStatus therapists.',
                  style: const TextStyle(color: Color(0xFF64748B), fontSize: 15),
                ),
              ],
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: list.length,
          separatorBuilder: (context, index) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final therapist = list[index];
            final modStatus = _resolveModerationStatus(therapist.verificationStatus, therapist.moderationStatus, therapist.hasActiveRestrictions);

            // Verification status colour
            Color statusColor;
            Color statusBg;
            switch (therapist.verificationStatus) {
              case 'approved':
                statusColor = const Color(0xFF059669);
                statusBg = const Color(0xFFD1FAE5);
                break;
              case 'rejected':
                statusColor = const Color(0xFFDC2626);
                statusBg = const Color(0xFFFEE2E2);
                break;
              default:
                statusColor = const Color(0xFFD97706);
                statusBg = const Color(0xFFFEF3C7);
            }

            return Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              elevation: 0,
              child: InkWell(
                onTap: () => _showTherapistAdminDialog(therapist),
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Header strip ────────────────────────────────
                      Container(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Color(0xFF0F172A), Color(0xFF1E293B)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                        ),
                        child: Row(
                          children: [
                            _therapistAvatar(therapist, radius: 26),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    therapist.displayName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    therapist.formattedExperience == 'Not set'
                                        ? 'Therapist'
                                        : '${therapist.formattedExperience} experience',
                                    style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                                  ),
                                ],
                              ),
                            ),
                            // Verification badge
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: statusBg,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                therapist.verificationStatus.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: statusColor,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            // Moderation badge
                            _moderationStatusBadge(modStatus),
                          ],
                        ),
                      ),
                      // ── Body ────────────────────────────────────────
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (therapist.specializations.isNotEmpty) ...[
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: therapist.specializations.take(3).map((s) {
                                  return Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFEFF6FF),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(color: const Color(0xFFBFDBFE)),
                                    ),
                                    child: Text(
                                      s,
                                      style: const TextStyle(fontSize: 11, color: Color(0xFF1D4ED8), fontWeight: FontWeight.w500),
                                    ),
                                  );
                                }).toList()
                                  ..addAll(
                                    therapist.specializations.length > 3
                                        ? [
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFF1F5F9),
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: Text(
                                                '+${therapist.specializations.length - 3} more',
                                                style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                                              ),
                                            ),
                                          ]
                                        : [],
                                  ),
                              ),
                              const SizedBox(height: 10),
                            ],
                            Row(
                              children: [
                                _miniStat(Icons.star_rounded, therapist.rating.toStringAsFixed(1), const Color(0xFFF59E0B)),
                                const SizedBox(width: 16),
                                _miniStat(Icons.rate_review_rounded, '${therapist.totalReviews} reviews', const Color(0xFF6366F1)),
                                const SizedBox(width: 16),
                                if (therapist.certificateBase64.isNotEmpty)
                                  _miniStat(Icons.verified_rounded, 'Has cert.', const Color(0xFF10B981)),
                              ],
                            ),
                          ],
                        ),
                      ),
                      // ── Tap hint ────────────────────────────────────
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: const BoxDecoration(
                          color: Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
                          border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
                        ),
                        child: const Center(
                          child: Text(
                            'Tap to view full profile & moderate',
                            style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _miniStat(IconData icon, String label, Color color) {

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600)),
      ],
    );
  }

  void _showTherapistAdminDialog(TherapistProfile therapist) {
    showDialog(
      context: context,
      builder: (ctx) {
        // Status colour
        Color statusColor;
        Color statusBg;
        switch (therapist.verificationStatus) {
          case 'approved':
            statusColor = const Color(0xFF059669);
            statusBg = const Color(0xFFD1FAE5);
            break;
          case 'rejected':
            statusColor = const Color(0xFFDC2626);
            statusBg = const Color(0xFFFEE2E2);
            break;
          default:
            statusColor = const Color(0xFFD97706);
            statusBg = const Color(0xFFFEF3C7);
        }

        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          clipBehavior: Clip.hardEdge,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Gradient header ─────────────────────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF0F172A), Color(0xFF1E3A5F)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _therapistAvatar(therapist, radius: 32),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            therapist.displayName,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            therapist.specializations.isEmpty
                                ? 'General Therapist'
                                : therapist.specializations.first,
                            style: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color: statusBg,
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  therapist.verificationStatus.toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    color: statusColor,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              _moderationStatusBadge(_resolveModerationStatus(therapist.verificationStatus, therapist.moderationStatus, therapist.hasActiveRestrictions)),
                              const SizedBox(width: 8),
                              Icon(Icons.star_rounded, color: const Color(0xFFFBBF24), size: 14),
                              const SizedBox(width: 3),
                              Text(
                                '${therapist.rating.toStringAsFixed(1)} (${therapist.totalReviews})',
                                style: const TextStyle(fontSize: 12, color: Colors.white70),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close_rounded, color: Colors.white54, size: 22),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),

              // ── Scrollable body ────────────────────────────────────
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [

                      // ── Professional Info section ──────────────────
                      _dialogSectionHeader(Icons.work_outline_rounded, 'Professional Info'),
                      const SizedBox(height: 10),
                      _infoCard([
                        _infoTile(Icons.badge_outlined, 'User ID', therapist.id, mono: true),
                        _infoTile(Icons.schedule_rounded, 'Experience', therapist.formattedExperience),
                        _infoTile(Icons.event_available_rounded, 'Availability', therapist.availability.isEmpty ? 'Not set' : therapist.availability),
                        if (therapist.credentials.isNotEmpty)
                          _infoTile(Icons.school_outlined, 'Credentials', therapist.credentials),
                        if (therapist.licenseNumber.isNotEmpty)
                          _infoTile(Icons.credit_card_outlined, 'License #', therapist.licenseNumber),
                        if (therapist.registrationNumber.isNotEmpty)
                          _infoTile(Icons.numbers_rounded, 'Registration #', therapist.registrationNumber),
                      ]),

                      // ── Specializations ────────────────────────────
                      if (therapist.specializations.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        _dialogSectionHeader(Icons.psychology_outlined, 'Specializations'),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: therapist.specializations.map((s) {
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFFEFF6FF),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFFBFDBFE)),
                              ),
                              child: Text(
                                s,
                                style: const TextStyle(fontSize: 12, color: Color(0xFF1D4ED8), fontWeight: FontWeight.w500),
                              ),
                            );
                          }).toList(),
                        ),
                      ],

                      // ── Service Packages ───────────────────────────
                      if (therapist.servicePackages.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        _dialogSectionHeader(Icons.card_membership_rounded, 'Service Packages'),
                        const SizedBox(height: 10),
                        ...therapist.servicePackages.map((pkg) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8.0),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: const Color(0xFFE2E8F0)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          pkg.title,
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1E293B)),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        formatPrice(pkg.price),
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF10B981)),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    '${pkg.durationMinutes} mins | ${pkg.sessionsPerWeek} sessions/week',
                                    style: const TextStyle(fontSize: 12, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                                  ),
                                  if (pkg.description.isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      pkg.description,
                                      style: const TextStyle(fontSize: 12, color: Color(0xFF475569)),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        }),
                      ],

                      // ── Bio ────────────────────────────────────────
                      if (therapist.bio.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        _dialogSectionHeader(Icons.info_outline_rounded, 'About / Bio'),
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Text(
                            therapist.bio,
                            style: const TextStyle(fontSize: 13, color: Color(0xFF475569), height: 1.5),
                          ),
                        ),
                      ],

                      // ── Certificate ────────────────────────────────
                      if (therapist.certificateBase64.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        _dialogSectionHeader(Icons.verified_outlined, 'Documents'),
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: () async {
                            try {
                              final pdfBytes = base64Decode(therapist.certificateBase64.trim());
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => CertificateViewerScreen(
                                    pdfBytes: pdfBytes,
                                    title: '${therapist.displayName} – Certificate',
                                  ),
                                ),
                              );
                            } catch (e) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Failed to open certificate: $e')),
                              );
                            }
                          },
                          icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
                          label: const Text('View Professional Certificate'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(44),
                            side: const BorderSide(color: Color(0xFF0EA5E9)),
                            foregroundColor: const Color(0xFF0EA5E9),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ],

                      // ── Moderation Management ──────────────────────
                      const SizedBox(height: 20),
                      _dialogSectionHeader(Icons.gavel_rounded, 'Moderation Management'),
                      const SizedBox(height: 10),
                      _ModerationPanel(
                        userId: therapist.id,
                        userRole: 'therapist',
                        currentStatus: _resolveModerationStatus(therapist.verificationStatus, therapist.moderationStatus, therapist.hasActiveRestrictions),
                        onActionTaken: () {
                          Navigator.pop(ctx);
                          _loadStats();
                          setState(() {});
                        },
                        onOpenDialog: (uid, role) {
                          Navigator.pop(ctx);
                          _showModerationDialogWithRole(uid, '', role);
                        },
                      ),

                      // ── Moderation History / Timeline ──────────────
                      const SizedBox(height: 20),
                      _dialogSectionHeader(Icons.history_rounded, 'Moderation Timeline'),
                      const SizedBox(height: 10),
                      _ModerationTimeline(userId: therapist.id),

                      // ── Admin Message ─────────────────────────────
                      const SizedBox(height: 20),
                      _dialogSectionHeader(Icons.send_rounded, 'Send Message'),
                      const SizedBox(height: 10),
                      _AdminMessageSender(recipientId: therapist.id, recipientType: 'Therapist'),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _dialogSectionHeader(IconData icon, String title) {
    return Row(
      children: [
        Icon(icon, size: 16, color: const Color(0xFF3B82F6)),
        const SizedBox(width: 6),
        Text(
          title,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
        ),
        const SizedBox(width: 8),
        Expanded(child: Divider(color: Colors.grey.shade200, height: 1)),
      ],
    );
  }

  Widget _infoCard(List<Widget> tiles) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: List.generate(tiles.length, (i) {
          return Column(
            children: [
              tiles[i],
              if (i < tiles.length - 1)
                Divider(height: 1, indent: 40, endIndent: 12, color: Colors.grey.shade200),
            ],
          );
        }),
      ),
    );
  }

  Widget _infoTile(IconData icon, String label, String value, {bool mono = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: const Color(0xFF64748B)),
          const SizedBox(width: 10),
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12,
                color: const Color(0xFF1E293B),
                fontFamily: mono ? 'monospace' : null,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubscriptionsTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection('subscriptions').snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Error loading subscriptions: ${snapshot.error}',
              style: const TextStyle(color: Color(0xFFEF4444)),
            ),
          );
        }

        final docs = snapshot.data?.docs ?? [];
        final allSubs = docs.map((doc) {
          final data = doc.data() as Map<String, dynamic>? ?? {};
          return UserSubscription.fromMap(doc.id, data);
        }).toList();

        // Sort in memory by createdAt descending
        allSubs.sort((a, b) {
          final docA = docs.firstWhere((d) => d.id == a.id);
          final docB = docs.firstWhere((d) => d.id == b.id);
          final dataA = docA.data() as Map<String, dynamic>? ?? {};
          final dataB = docB.data() as Map<String, dynamic>? ?? {};
          final tsA = dataA['createdAt'] as Timestamp?;
          final tsB = dataB['createdAt'] as Timestamp?;
          if (tsA != null && tsB != null) {
            return tsB.compareTo(tsA);
          }
          if (tsA != null) return -1;
          if (tsB != null) return 1;
          return b.id.compareTo(a.id);
        });

        // Filter by search query & status chip
        final filteredSubs = allSubs.where((sub) {
          final status = sub.status.toLowerCase().trim();
          bool matchesStatus = true;
          if (_subFilterStatus == 'Active') {
            matchesStatus = sub.isActive || status == 'active' || status == 'trialing' || status == 'grace_period';
          } else if (_subFilterStatus == 'Canceled') {
            matchesStatus = status == 'canceled' || status == 'cancelled' || status == 'cancels soon' || status == 'cancels_soon' || status.contains('cancel');
          } else if (_subFilterStatus == 'Expired') {
            matchesStatus = status == 'expired' || status == 'inactive';
          }

          if (!matchesStatus) return false;

          final query = _subSearchQuery.trim().toLowerCase();
          if (query.isEmpty) return true;

          final parentName = _userNames[sub.userId]?.toLowerCase() ?? '';
          final parentEmail = _userEmails[sub.userId]?.toLowerCase() ?? '';
          final therapistName = _therapistNames[sub.therapistId]?.toLowerCase() ?? '';
          final plan = sub.productId.toLowerCase();
          final subId = sub.id.toLowerCase();

          return parentName.contains(query) ||
              parentEmail.contains(query) ||
              therapistName.contains(query) ||
              plan.contains(query) ||
              subId.contains(query);
        }).toList();

        return Column(
          children: [
            // Search and Status Filters
            Container(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(
                  bottom: BorderSide(color: Color(0xFFE2E8F0)),
                ),
              ),
              child: Column(
                children: [
                  TextField(
                    controller: _subSearchController,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF64748B), size: 20),
                      hintText: 'Search by parent, email, therapist, or plan...',
                      hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13.5),
                      fillColor: const Color(0xFFF8FAFC),
                      filled: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFF3B82F6), width: 1.5),
                      ),
                      suffixIcon: _subSearchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded, color: Color(0xFF64748B), size: 18),
                              onPressed: () => _subSearchController.clear(),
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: ['All', 'Active', 'Canceled', 'Expired'].map((status) {
                        final isSelected = _subFilterStatus == status;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(
                              status,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: isSelected ? Colors.white : const Color(0xFF475569),
                              ),
                            ),
                            selected: isSelected,
                            selectedColor: const Color(0xFF1E293B),
                            backgroundColor: const Color(0xFFF1F5F9),
                            onSelected: (selected) {
                              if (selected) {
                                setState(() {
                                  _subFilterStatus = status;
                                });
                              }
                            },
                            checkmarkColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                              side: BorderSide(
                                color: isSelected ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
            
            // Subscriptions List
            Expanded(
              child: filteredSubs.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.receipt_long_outlined, size: 48, color: Color(0xFF94A3B8)),
                          const SizedBox(height: 12),
                          Text(
                            allSubs.isEmpty ? 'No subscriptions registered.' : 'No matching subscriptions found.',
                            style: const TextStyle(color: Color(0xFF64748B), fontSize: 14),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: filteredSubs.length,
                      itemBuilder: (context, index) {
                        final sub = filteredSubs[index];
                        final doc = docs.firstWhere((d) => d.id == sub.id);
                        final rawData = doc.data() as Map<String, dynamic>? ?? {};

                        final parentName = _userNames[sub.userId] ?? 'Unknown Parent';
                        final parentEmail = _userEmails[sub.userId] ?? '';
                        final therapistName = _therapistNames[sub.therapistId] ?? 'Unknown Therapist';

                        // Status styling
                        final statusStr = sub.status.toLowerCase().trim();
                        Color sideColor = const Color(0xFF64748B);
                        Color badgeBg = const Color(0xFFF1F5F9);
                        Color badgeText = const Color(0xFF475569);

                        if (sub.isActive || statusStr == 'active' || statusStr == 'trialing' || statusStr == 'grace_period') {
                          sideColor = const Color(0xFF10B981);
                          badgeBg = const Color(0xFFECFDF5);
                          badgeText = const Color(0xFF047857);
                        } else if (statusStr == 'pending') {
                          sideColor = const Color(0xFFF59E0B);
                          badgeBg = const Color(0xFFFFFBEB);
                          badgeText = const Color(0xFFB45309);
                        } else if (statusStr == 'canceled' || statusStr == 'cancelled' || statusStr == 'cancels soon' || statusStr == 'cancels_soon') {
                          sideColor = const Color(0xFFF97316);
                          badgeBg = const Color(0xFFFFF7ED);
                          badgeText = const Color(0xFFC2410C);
                        } else if (statusStr == 'expired') {
                          sideColor = const Color(0xFFEF4444);
                          badgeBg = const Color(0xFFFEF2F2);
                          badgeText = const Color(0xFFB91C1C);
                        } else if (statusStr == 'payment_failed') {
                          sideColor = const Color(0xFF991B1B);
                          badgeBg = const Color(0xFFFFF5F5);
                          badgeText = const Color(0xFF7F1D1D);
                        }

                        final formattedAmount = _getSubscriptionAmount(rawData);
                        final expiry = sub.currentPeriodEnd;
                        final expiryStr = expiry != null
                            ? '${expiry.day}/${expiry.month}/${expiry.year}'
                            : 'N/A';

                        return Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.02),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: IntrinsicHeight(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Container(
                                    width: 6,
                                    color: sideColor,
                                  ),
                                  Expanded(
                                    child: Material(
                                      color: Colors.transparent,
                                      child: InkWell(
                                        onTap: () => _showSubscriptionDetailsDialog(sub, rawData),
                                        child: Padding(
                                          padding: const EdgeInsets.all(16),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                                children: [
                                                  Expanded(
                                                    child: Text(
                                                      parentName,
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: const TextStyle(
                                                        fontWeight: FontWeight.bold,
                                                        fontSize: 15,
                                                        color: Color(0xFF1E293B),
                                                      ),
                                                    ),
                                                  ),
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                    decoration: BoxDecoration(
                                                      color: badgeBg,
                                                      borderRadius: BorderRadius.circular(6),
                                                    ),
                                                    child: Text(
                                                      sub.status.toUpperCase(),
                                                      style: TextStyle(
                                                        fontSize: 9,
                                                        fontWeight: FontWeight.bold,
                                                        color: badgeText,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              if (parentEmail.isNotEmpty) ...[
                                                const SizedBox(height: 2),
                                                Text(
                                                  parentEmail,
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                    color: Color(0xFF64748B),
                                                  ),
                                                ),
                                              ],
                                              const SizedBox(height: 12),
                                              const Divider(height: 1, color: Color(0xFFF1F5F9)),
                                              const SizedBox(height: 12),
                                              Row(
                                                children: [
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      children: [
                                                        const Text(
                                                          'Therapist',
                                                          style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8), fontWeight: FontWeight.bold),
                                                        ),
                                                        const SizedBox(height: 2),
                                                        Text(
                                                          therapistName,
                                                          maxLines: 1,
                                                          overflow: TextOverflow.ellipsis,
                                                          style: const TextStyle(fontSize: 13, color: Color(0xFF334155), fontWeight: FontWeight.w600),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                  Expanded(
                                                    child: Column(
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      children: [
                                                        const Text(
                                                          'Plan / Amount',
                                                          style: TextStyle(fontSize: 10, color: Color(0xFF94A3B8), fontWeight: FontWeight.bold),
                                                        ),
                                                        const SizedBox(height: 2),
                                                        Text(
                                                          '${sub.productId} ($formattedAmount)',
                                                          maxLines: 1,
                                                          overflow: TextOverflow.ellipsis,
                                                          style: const TextStyle(fontSize: 13, color: Color(0xFF334155), fontWeight: FontWeight.w600),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 10),
                                              Row(
                                                children: [
                                                  const Icon(Icons.calendar_today_rounded, size: 12, color: Color(0xFF64748B)),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    'Period End: $expiryStr',
                                                    style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  String _getSubscriptionAmount(Map<String, dynamic> data) {
    final amt = data['amount'];
    if (amt == null) return 'N/A';
    if (amt is num) {
      return formatPrice(amt.toDouble());
    }
    return amt.toString();
  }

  void _showSubscriptionDetailsDialog(UserSubscription sub, Map<String, dynamic> rawData) {
    final parentName = _userNames[sub.userId] ?? 'Unknown Parent';
    final parentEmail = _userEmails[sub.userId] ?? 'N/A';
    final therapistName = _therapistNames[sub.therapistId] ?? 'Unknown Therapist';
    
    final created = rawData['createdAt'];
    final createdDate = dateTimeFromFirestore(created);
    final createdStr = createdDate != null
        ? '${createdDate.day}/${createdDate.month}/${createdDate.year} ${createdDate.hour.toString().padLeft(2, '0')}:${createdDate.minute.toString().padLeft(2, '0')}'
        : 'N/A';
    
    final expiry = sub.currentPeriodEnd;
    final expiryStr = expiry != null
        ? '${expiry.day}/${expiry.month}/${expiry.year} ${expiry.hour.toString().padLeft(2, '0')}:${expiry.minute.toString().padLeft(2, '0')}'
        : 'N/A';

    final amountStr = _getSubscriptionAmount(rawData);
    final statusStr = sub.status.toUpperCase();

    showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          clipBehavior: Clip.hardEdge,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header Banner
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF0F172A), Color(0xFF1E3A5F)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const CircleAvatar(
                      backgroundColor: Color(0xFFEFF6FF),
                      child: Icon(Icons.receipt_long_rounded, color: Color(0xFF2563EB)),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Subscription Info',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'STATUS: $statusStr',
                            style: const TextStyle(fontSize: 13, color: Color(0xFF38BDF8), fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close_rounded, color: Colors.white54, size: 22),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),

              // Content Details
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Sub IDs & General
                      _dialogSectionHeader(Icons.info_outline_rounded, 'Overview & Dates'),
                      const SizedBox(height: 10),
                      _infoCard([
                        _infoTile(Icons.vpn_key_outlined, 'Doc ID', sub.id, mono: true),
                        _infoTile(Icons.calendar_month_outlined, 'Started At', createdStr),
                        _infoTile(Icons.event_busy_rounded, 'Period End', expiryStr),
                        _infoTile(Icons.shopping_bag_outlined, 'Package/Plan', sub.productId),
                        _infoTile(Icons.payments_outlined, 'Amount', amountStr),
                      ]),

                      const SizedBox(height: 16),
                      _dialogSectionHeader(Icons.people_outline_rounded, 'Related Profiles'),
                      const SizedBox(height: 10),
                      _infoCard([
                        _infoTile(Icons.person_outline_rounded, 'Parent Name', parentName),
                        _infoTile(Icons.email_outlined, 'Parent Email', parentEmail),
                        _infoTile(Icons.badge_outlined, 'Parent UID', sub.userId, mono: true),
                        _infoTile(Icons.medical_services_outlined, 'Therapist Name', therapistName),
                        _infoTile(Icons.badge_outlined, 'Therapist UID', sub.therapistId ?? 'N/A', mono: true),
                      ]),

                      const SizedBox(height: 16),
                      _dialogSectionHeader(Icons.payment_rounded, 'Provider Details'),
                      const SizedBox(height: 10),
                      _infoCard([
                        _infoTile(Icons.business_outlined, 'Provider', (rawData['provider'] ?? 'N/A').toString()),
                        _infoTile(Icons.pin_outlined, 'Transaction ID', (rawData['providerTransactionId'] ?? 'N/A').toString(), mono: true),
                        _infoTile(Icons.contact_mail_outlined, 'Customer Ref', (rawData['providerCustomerRef'] ?? 'N/A').toString()),
                        _infoTile(Icons.receipt_outlined, 'Last Payment Ref', (rawData['lastPaymentRef'] ?? 'N/A').toString(), mono: true),
                        _infoTile(Icons.shopping_cart_outlined, 'Basket ID', (rawData['basketId'] ?? 'N/A').toString(), mono: true),
                      ]),

                      const SizedBox(height: 20),
                      _dialogSectionHeader(Icons.message_rounded, 'Contact Support'),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () async {
                                final scaffoldMessenger = ScaffoldMessenger.of(context);
                                try {
                                  final parent = await AppRepositories.users.getUserProfile(sub.userId);
                                  if (parent == null) {
                                    throw Exception('Parent profile not found.');
                                  }
                                  final children = await AppRepositories.users.getChildrenForParent(sub.userId);
                                  if (context.mounted) {
                                    Navigator.pop(ctx);
                                    _showParentDetailsDialog(parent, children);
                                  }
                                } catch (e) {
                                  scaffoldMessenger.showSnackBar(
                                    SnackBar(content: Text('Error loading parent details: $e')),
                                  );
                                }
                              },
                              icon: const Icon(Icons.send_rounded, size: 16),
                              label: const Text('Message Parent', style: TextStyle(fontSize: 12)),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF3B82F6),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (sub.therapistId != null)
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: () async {
                                  Navigator.pop(ctx);
                                  // Fetch therapist details first
                                  try {
                                    final doc = await FirebaseFirestore.instance.collection('therapist_profiles').doc(sub.therapistId).get();
                                    if (doc.exists && doc.data() != null) {
                                      final therapist = TherapistProfile.fromMap(doc.id, doc.data()!);
                                      if (mounted) {
                                        _showTherapistAdminDialog(therapist);
                                      }
                                    }
                                  } catch (_) {}
                                },
                                icon: const Icon(Icons.medical_information_rounded, size: 16),
                                label: const Text('Message Therapist', style: TextStyle(fontSize: 12)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF10B981),
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildWithdrawalsTab() {
    return FutureBuilder<QuerySnapshot>(
      future: FirebaseFirestore.instance
          .collection('withdrawal_requests')
          .orderBy('createdAt', descending: true)
          .limit(100)
          .get(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        final docs = snapshot.data?.docs ?? [];

        // Compute totals for summary cards
        double totalPending = 0;
        double totalPaid = 0;
        for (final doc in docs) {
          final data = doc.data() as Map<String, dynamic>;
          final amt = (data['amount'] as num?)?.toDouble() ?? 0.0;
          final st = (data['status'] ?? '').toString();
          if (st == 'pending') totalPending += amt;
          if (st == 'paid') totalPaid += amt;
        }

        // Fetch platform revenue total
        return FutureBuilder<DocumentSnapshot>(
          future: FirebaseFirestore.instance
              .collection('platform_revenue')
              .doc('summary')
              .get(),
          builder: (context, revenueSnap) {
            final revData = revenueSnap.data?.data() as Map<String, dynamic>? ?? {};
            final totalRevenue = (revData['totalRevenue'] as num?)?.toDouble() ?? 0.0;

            return Column(
              children: [
                // Summary cards
                Container(
                  padding: const EdgeInsets.all(16),
                  color: const Color(0xFFF8FAFC),
                  child: Row(
                    children: [
                      Expanded(
                        child: _buildOverviewCard(
                          'Pending Payouts',
                          'Rs. ${totalPending.toStringAsFixed(0)}',
                          Icons.pending_outlined,
                          const Color(0xFFD97706),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildOverviewCard(
                          'Total Paid Out',
                          'Rs. ${totalPaid.toStringAsFixed(0)}',
                          Icons.check_circle_outline,
                          const Color(0xFF059669),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildOverviewCard(
                          'Platform Revenue (7%)',
                          'Rs. ${totalRevenue.toStringAsFixed(0)}',
                          Icons.account_balance_outlined,
                          const Color(0xFF3B82F6),
                        ),
                      ),
                    ],
                  ),
                ),
                // CSV Export button
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.download_outlined, size: 16),
                      label: const Text('Export CSV'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF1E293B),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onPressed: () => _exportWithdrawalsCsv(docs),
                    ),
                  ),
                ),
                // Withdrawals list
                Expanded(
                  child: docs.isEmpty
                      ? const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.inbox_outlined, size: 48, color: Color(0xFFCBD5E1)),
                              SizedBox(height: 12),
                              Text('No withdrawal requests yet.', style: TextStyle(color: Color(0xFF94A3B8))),
                            ],
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: docs.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final doc = docs[index];
                            final data = doc.data() as Map<String, dynamic>;
                            final status = (data['status'] ?? 'pending').toString();
                            final amount = (data['amount'] as num?)?.toDouble() ?? 0.0;
                            final therapistName = (data['therapistName'] ?? 'Therapist').toString();
                            final rawMethod = (data['paymentMethod'] ?? '').toString();
                            final method = rawMethod.toLowerCase() == 'easypaisa'
                                ? 'EasyPaisa'
                                : (rawMethod.toLowerCase() == 'jazzcash'
                                    ? 'JazzCash'
                                    : (rawMethod.toLowerCase() == 'raast'
                                        ? 'Raast'
                                        : (rawMethod.toLowerCase() == 'bank' || rawMethod.toLowerCase() == 'bank transfer'
                                            ? 'Bank Transfer'
                                            : rawMethod)));
                            final accountDetails = (data['accountDetails'] ?? '').toString();
                            final createdAt = data['createdAt'];
                            String dateStr = '';
                            if (createdAt != null) {
                              final dt = (createdAt as Timestamp).toDate().toLocal();
                              dateStr = '${dt.day}/${dt.month}/${dt.year}';
                            }
                            final statusColor = status == 'paid'
                                ? const Color(0xFF059669)
                                : status == 'rejected'
                                    ? const Color(0xFFDC2626)
                                    : const Color(0xFFD97706);

                            return Card(
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: const BorderSide(color: Color(0xFFF1F5F9)),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (data['isAppeal'] == true) ...[
                                      Container(
                                        margin: const EdgeInsets.only(bottom: 10),
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFFEF2F2),
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: const Color(0xFFFCA5A5)),
                                        ),
                                        child: const Row(
                                          children: [
                                            Icon(Icons.warning_amber_rounded, color: Color(0xFFDC2626), size: 16),
                                            SizedBox(width: 6),
                                            Expanded(
                                              child: Text(
                                                'Appeal Request: Therapist bypassing 3-day cooldown.',
                                                style: TextStyle(
                                                  color: Color(0xFF991B1B),
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            therapistName,
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: statusColor.withValues(alpha: 0.1),
                                            borderRadius: BorderRadius.circular(20),
                                          ),
                                          child: Text(
                                            status.toUpperCase(),
                                            style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Rs. ${amount.toStringAsFixed(0)}  •  $method  •  $dateStr',
                                      style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
                                    ),
                                    if (accountDetails.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        accountDetails,
                                        style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12),
                                      ),
                                    ],
                                    if (status == 'paid') ...[
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          const Icon(Icons.check_circle_outline, color: Color(0xFF059669), size: 14),
                                          const SizedBox(width: 4),
                                          Expanded(
                                            child: Text(
                                              'Ref: ${data["adminNotes"] ?? "N/A"}',
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(color: Color(0xFF059669), fontSize: 12, fontWeight: FontWeight.w600),
                                            ),
                                          ),
                                          if (data['receiptBase64'] != null && data['receiptBase64'].toString().isNotEmpty) ...[
                                            const SizedBox(width: 8),
                                            TextButton.icon(
                                              onPressed: () {
                                                Navigator.push(
                                                  context,
                                                  MaterialPageRoute(
                                                    builder: (context) => ReceiptViewerScreen(
                                                      base64String: data['receiptBase64'].toString(),
                                                      title: 'Payout Receipt',
                                                    ),
                                                  ),
                                                );
                                              },
                                              icon: const Icon(Icons.receipt_long_rounded, size: 14),
                                              label: const Text('Receipt', style: TextStyle(fontSize: 11)),
                                              style: TextButton.styleFrom(
                                                foregroundColor: const Color(0xFF059669),
                                                padding: EdgeInsets.zero,
                                                minimumSize: const Size(0, 24),
                                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ],
                                    if (status == 'pending') ...[
                                      const SizedBox(height: 12),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: OutlinedButton.icon(
                                              icon: const Icon(Icons.close_rounded, size: 16),
                                              label: const Text('Reject'),
                                              style: OutlinedButton.styleFrom(
                                                foregroundColor: const Color(0xFFDC2626),
                                                side: const BorderSide(color: Color(0xFFDC2626)),
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                              ),
                                              onPressed: () => _resolveWithdrawal(doc.id, 'rejected'),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: ElevatedButton.icon(
                                              icon: const Icon(Icons.check_rounded, size: 16),
                                              label: const Text('Mark Paid'),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: const Color(0xFF059669),
                                                foregroundColor: Colors.white,
                                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                              ),
                                              onPressed: () => _resolveWithdrawal(doc.id, 'paid'),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _resolveWithdrawal(String requestId, String status) async {
    String? adminNotes;
    String? receiptBase64;

    if (status == 'rejected') {
      // Mandatory rejection reason dialog
      final reason = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) {
          final ctrl = TextEditingController();
          final formKey = GlobalKey<FormState>();
          return AlertDialog(
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEE2E2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.cancel_rounded, color: Color(0xFFDC2626), size: 24),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Reject Withdrawal',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                  ),
                ),
              ],
            ),
            content: Form(
              key: formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'You must provide a reason for rejection. This reason will be sent to the therapist in their notification.',
                    style: TextStyle(color: Color(0xFF64748B), fontSize: 13, height: 1.4),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: ctrl,
                    autofocus: true,
                    maxLines: 3,
                    maxLength: 300,
                    style: const TextStyle(fontSize: 14, color: Color(0xFF1E293B)),
                    decoration: InputDecoration(
                      labelText: 'Rejection Reason *',
                      labelStyle: const TextStyle(color: Color(0xFFDC2626), fontWeight: FontWeight.bold, fontSize: 13),
                      hintText: 'e.g. Incorrect account details, duplicate request...',
                      hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12.5),
                      filled: true,
                      fillColor: const Color(0xFFFEF2F2),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFFDC2626), width: 2),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFFFCA5A5)),
                      ),
                      errorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFFEF4444)),
                      ),
                      focusedErrorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFFEF4444), width: 2),
                      ),
                    ),
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) return 'Rejection reason is required';
                      if (val.trim().length < 5) return 'Please enter a more descriptive reason';
                      return null;
                    },
                  ),
                ],
              ),
            ),
            actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w600)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFDC2626),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
                onPressed: () {
                  if (formKey.currentState?.validate() == true) {
                    Navigator.pop(ctx, ctrl.text.trim());
                  }
                },
                child: const Text('Confirm Rejection', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              ),
            ],
          );
        },
      );
      if (reason == null) return; // admin cancelled
      adminNotes = reason;
    } else if (status == 'paid') {
      final resMap = await showDialog<Map<String, String?>>(
        context: context,
        builder: (ctx) {
          final ctrl = TextEditingController();
          final formKey = GlobalKey<FormState>();
          String? pickedFileName;
          String? base64String;

          return StatefulBuilder(
            builder: (context, setState) {
              return AlertDialog(
                backgroundColor: Colors.white,
                surfaceTintColor: Colors.transparent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                title: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD1FAE5),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.check_circle_rounded,
                        color: Color(0xFF059669),
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'Mark as Paid',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                  ],
                ),
                content: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Please enter the official payment transaction reference ID. This is mandatory for auditing and record-keeping.',
                          style: TextStyle(
                            color: Color(0xFF64748B),
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 18),
                        TextFormField(
                          controller: ctrl,
                          autofocus: true,
                          style: const TextStyle(
                            fontSize: 15,
                            color: Color(0xFF1E293B),
                            fontWeight: FontWeight.w500,
                          ),
                          decoration: InputDecoration(
                            labelText: 'Transaction Reference ID',
                            labelStyle: const TextStyle(
                              color: Color(0xFF059669),
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                            hintText: 'e.g. TXN987654321',
                            hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
                            prefixIcon: const Icon(
                              Icons.receipt_long_rounded,
                              color: Color(0xFF64748B),
                            ),
                            filled: true,
                            fillColor: const Color(0xFFF8FAFC),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Color(0xFF059669), width: 2),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Color(0xFFE2E8F0), width: 1),
                            ),
                            errorBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1),
                            ),
                            focusedErrorBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: const BorderSide(color: Color(0xFFEF4444), width: 2),
                            ),
                            errorStyle: const TextStyle(
                              color: Color(0xFFEF4444),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          validator: (val) {
                            if (val == null || val.trim().isEmpty) {
                              return 'Transaction reference is required';
                            }
                            if (val.trim().length < 4) {
                              return 'Please enter a valid reference ID';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 20),
                        const Text(
                          'Upload Receipt (Mandatory, max 500KB):',
                          style: TextStyle(
                            color: Color(0xFF1E293B),
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (pickedFileName != null) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.file_present_rounded, color: Color(0xFF64748B), size: 20),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    pickedFileName!,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 13, color: Color(0xFF334155)),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.close_rounded, color: Color(0xFFEF4444), size: 18),
                                  onPressed: () {
                                    setState(() {
                                      pickedFileName = null;
                                      base64String = null;
                                    });
                                  },
                                ),
                              ],
                            ),
                          ),
                        ] else ...[
                          OutlinedButton.icon(
                            onPressed: () async {
                              final result = await FilePicker.platform.pickFiles(
                                type: FileType.custom,
                                allowedExtensions: const ['jpg', 'jpeg', 'png', 'pdf'],
                                withData: true,
                              );
                              if (result != null && result.files.isNotEmpty) {
                                final file = result.files.single;
                                final bytes = file.bytes;
                                if (bytes == null) return;
                                final sizeKB = bytes.length / 1024;
                                if (sizeKB > 500) {
                                  if (ctx.mounted) {
                                    ScaffoldMessenger.of(ctx).showSnackBar(
                                      const SnackBar(
                                        content: Text('File is too large (must be under 500KB)'),
                                        backgroundColor: Color(0xFFEF4444),
                                      ),
                                    );
                                  }
                                  return;
                                }
                                setState(() {
                                  pickedFileName = file.name;
                                  base64String = base64Encode(bytes);
                                });
                              }
                            },
                            icon: const Icon(Icons.upload_file_rounded),
                            label: const Text('Select Receipt File'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF059669),
                              side: const BorderSide(color: Color(0xFF059669)),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text(
                      'Cancel',
                      style: TextStyle(
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF059669),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    ),
                    onPressed: () {
                      if (formKey.currentState?.validate() == true) {
                        if (base64String == null || base64String!.isEmpty) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            const SnackBar(
                              content: Text('Please select and upload the transaction receipt first.'),
                              backgroundColor: Color(0xFFEF4444),
                            ),
                          );
                          return;
                        }
                        Navigator.pop(ctx, {
                          'referenceId': ctrl.text.trim(),
                          'receiptBase64': base64String,
                        });
                      }
                    },
                    child: const Text(
                      'Confirm',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      );
      if (resMap == null) return; // cancelled
      adminNotes = resMap['referenceId'];
      receiptBase64 = resMap['receiptBase64'];
    }

    try {
      await AppRepositories.admin.resolveWithdrawalRequest(
        requestId: requestId,
        status: status,
        adminNotes: adminNotes?.isEmpty == true ? null : adminNotes,
        receiptBase64: receiptBase64,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(status == 'paid' ? 'Withdrawal marked as paid.' : 'Withdrawal rejected.'),
            backgroundColor: status == 'paid' ? const Color(0xFF059669) : const Color(0xFFDC2626),
          ),
        );
        setState(() {}); // rebuild to refresh FutureBuilder
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to resolve withdrawal: $e'), backgroundColor: const Color(0xFFDC2626)),
        );
      }
    }
  }

  void _exportWithdrawalsCsv(List<QueryDocumentSnapshot> docs) {
    final buffer = StringBuffer();
    buffer.writeln('Date,Therapist,Amount,Method,Account Details,Status,Admin Notes');
    for (final doc in docs) {
      final data = doc.data() as Map<String, dynamic>;
      final String dateStr = (() {
        final createdAt = data['createdAt'];
        if (createdAt != null) {
          final dt = (createdAt as Timestamp).toDate().toLocal();
          return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
        }
        return '';
      })();
      String esc(String? s) => '"${(s ?? '').replaceAll('"', '""')}"';
      buffer.writeln([
        esc(dateStr),
        esc(data['therapistName']?.toString()),
        data['amount']?.toString() ?? '0',
        esc(data['paymentMethod']?.toString()),
        esc(data['accountDetails']?.toString()),
        esc(data['status']?.toString()),
        esc(data['adminNotes']?.toString()),
      ].join(','));
    }
    final csv = buffer.toString();
    Clipboard.setData(ClipboardData(text: csv));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('CSV copied to clipboard! Paste into Excel/Sheets.'),
        backgroundColor: Color(0xFF059669),
      ),
    );
  }
}

class _AdminMessageSender extends StatefulWidget {
  const _AdminMessageSender({required this.recipientId, required this.recipientType});

  final String recipientId;
  final String recipientType;

  @override
  State<_AdminMessageSender> createState() => _AdminMessageSenderState();
}

class _AdminMessageSenderState extends State<_AdminMessageSender> {
  final TextEditingController _controller = TextEditingController();
  bool _isSending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    setState(() => _isSending = true);
    try {
      await AppRepositories.support.sendNotification(
        userId: widget.recipientId,
        title: 'Message from Admin',
        message: text,
        category: 'system',
      );

      // Audit manual admin message
      final adminId = FirebaseAuth.instance.currentUser?.uid;
      final adminEmail = FirebaseAuth.instance.currentUser?.email ?? '';
      if (adminId != null) {
        final logRef = FirebaseFirestore.instance.collection('admin_audit_logs').doc();
        await logRef.set({
          'id': logRef.id,
          'adminUid': adminId,
          'adminEmail': adminEmail,
          'targetUid': widget.recipientId,
          'actionType': 'send_message',
          'details': 'Sent admin message: "$text" to ${widget.recipientType}',
          'timestamp': FieldValue.serverTimestamp(),
        });
      }

      _controller.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Message sent successfully!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send message: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Send Message to ${widget.recipientType}',
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E293B)),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                decoration: InputDecoration(
                  hintText: 'Type message to send...',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                style: const TextStyle(fontSize: 13),
              ),
            ),
            const SizedBox(width: 10),
            ElevatedButton(
              onPressed: _isSending ? null : _sendMessage,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF38BDF8),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              child: _isSending
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Send'),
            ),
          ],
        ),
      ],
    );
  }
}

class _AdminVoicePlayer extends StatefulWidget {
  final String payload;
  const _AdminVoicePlayer({required this.payload});

  @override
  State<_AdminVoicePlayer> createState() => _AdminVoicePlayerState();
}

class _AdminVoicePlayerState extends State<_AdminVoicePlayer> {
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlaying = false;
  double _progress = 0.0;
  int _durationSec = 10;
  StreamSubscription? _posSub;
  StreamSubscription? _completeSub;
  String? _tempPath;

  @override
  void initState() {
    super.initState();
    final payloadStr = widget.payload.trim();
    if (payloadStr.startsWith('http://') || payloadStr.startsWith('https://')) {
      _durationSec = 10;
    } else {
      final parts = payloadStr.split(':');
      if (parts.length >= 2) {
        _durationSec = int.tryParse(parts[1]) ?? 10;
      }
    }
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _completeSub?.cancel();
    _audioPlayer.dispose();
    if (_tempPath != null) {
      try {
        File(_tempPath!).delete();
      } catch (_) {}
    }
    super.dispose();
  }

  Future<void> _togglePlay() async {
    if (_isPlaying) {
      await _audioPlayer.stop();
      setState(() {
        _isPlaying = false;
        _progress = 0.0;
      });
      return;
    }

    try {
      final payloadStr = widget.payload.trim();
      if (payloadStr.startsWith('http://') || payloadStr.startsWith('https://')) {
        setState(() {
          _isPlaying = true;
          _progress = 0.0;
        });

        await _audioPlayer.play(UrlSource(payloadStr));

        _posSub = _audioPlayer.onPositionChanged.listen((pos) {
          if (mounted && _isPlaying) {
            setState(() {
              final totalMs = _durationSec * 1000;
              _progress = totalMs > 0 ? (pos.inMilliseconds / totalMs).clamp(0.0, 1.0) : 0.0;
            });
          }
        });

        _completeSub = _audioPlayer.onPlayerComplete.listen((event) {
          if (mounted) {
            setState(() {
              _isPlaying = false;
              _progress = 0.0;
            });
          }
        });
        return;
      }

      final parts = payloadStr.split(':');
      if (parts.length < 3) return;
      final base64Data = parts[2];
      var cleanBase64 = base64Data;
      if (cleanBase64.contains('base64,')) {
        cleanBase64 = cleanBase64.substring(cleanBase64.indexOf('base64,') + 7);
      }
      final bytes = base64Decode(cleanBase64);

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/admin_playing_voice_${identityHashCode(this)}.m4a');
      await file.writeAsBytes(bytes);
      _tempPath = file.path;

      setState(() {
        _isPlaying = true;
        _progress = 0.0;
      });

      await _audioPlayer.play(DeviceFileSource(file.path));

      _posSub = _audioPlayer.onPositionChanged.listen((pos) {
        if (mounted && _isPlaying) {
          setState(() {
            final totalMs = _durationSec * 1000;
            _progress = totalMs > 0 ? (pos.inMilliseconds / totalMs).clamp(0.0, 1.0) : 0.0;
          });
        }
      });

      _completeSub = _audioPlayer.onPlayerComplete.listen((event) {
        if (mounted) {
          setState(() {
            _isPlaying = false;
            _progress = 0.0;
          });
        }
      });
    } catch (e) {
      debugPrint('Error playing admin voice note: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.teal.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.teal.shade100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(_isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled),
            color: Colors.teal,
            iconSize: 28,
            onPressed: _togglePlay,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 120,
                child: LinearProgressIndicator(
                  value: _progress,
                  color: Colors.teal,
                  backgroundColor: Colors.teal.shade100,
                  minHeight: 4,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${_durationSec}s Voice Note',
                style: const TextStyle(fontSize: 10, color: Colors.teal, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Moderation Status Badge Helper ──────────────────────────────────────────

String _resolveModerationStatus(String status, String moderationStatus, bool hasActiveRestrictions) {
  if (status == 'banned' || status == 'ban') return 'banned';
  if (status == 'suspended' || status == 'suspend') return 'suspended';
  if (hasActiveRestrictions) return 'restricted';
  return moderationStatus.isEmpty ? 'verified' : moderationStatus;
}

Widget _moderationStatusBadge(String moderationStatus) {
  final config = _moderationBadgeConfig(moderationStatus);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: config['bg'] as Color,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: config['border'] as Color),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(config['icon'] as String, style: const TextStyle(fontSize: 10)),
        const SizedBox(width: 4),
        Text(
          (config['label'] as String).toUpperCase(),
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.bold,
            color: config['text'] as Color,
            letterSpacing: 0.4,
          ),
        ),
      ],
    ),
  );
}

Map<String, dynamic> _moderationBadgeConfig(String status) {
  switch (status) {
    case 'warned':
      return {
        'icon': '⚠️', 'label': 'Warned',
        'bg': const Color(0xFFFEF3C7), 'border': const Color(0xFFFCD34D),
        'text': const Color(0xFF92400E),
      };
    case 'restricted':
      return {
        'icon': '🔒', 'label': 'Restricted',
        'bg': const Color(0xFFEDE9FE), 'border': const Color(0xFFC4B5FD),
        'text': const Color(0xFF5B21B6),
      };
    case 'suspended':
      return {
        'icon': '🔴', 'label': 'Suspended',
        'bg': const Color(0xFFFEE2E2), 'border': const Color(0xFFFCA5A5),
        'text': const Color(0xFF991B1B),
      };
    case 'banned':
      return {
        'icon': '⛔', 'label': 'Banned',
        'bg': const Color(0xFF1F2937), 'border': const Color(0xFF374151),
        'text': const Color(0xFFF87171),
      };
    default: // verified / active / clean
      return {
        'icon': '✅', 'label': 'Verified',
        'bg': const Color(0xFFD1FAE5), 'border': const Color(0xFF6EE7B7),
        'text': const Color(0xFF065F46),
      };
  }
}

// ─── _ModerationPanel ────────────────────────────────────────────────────────

/// Embedded moderation management panel shown inside Parent/Therapist detail
/// dialogs. Displays current moderation status and provides quick-action
/// buttons that open the full `_showModerationDialogWithRole` dialog.
class _ModerationPanel extends StatelessWidget {
  const _ModerationPanel({
    required this.userId,
    required this.userRole,
    required this.currentStatus,
    required this.onActionTaken,
    required this.onOpenDialog,
  });

  final String userId;
  final String userRole;
  final String currentStatus;
  final VoidCallback onActionTaken;
  final void Function(String uid, String role) onOpenDialog;

  @override
  Widget build(BuildContext context) {
    final isActive = currentStatus == 'active' || currentStatus == 'verified' || currentStatus.isEmpty;
    final isBanned = currentStatus == 'banned';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Current status
          Row(
            children: [
              const Text(
                'Current Status: ',
                style: TextStyle(fontSize: 12, color: Color(0xFF64748B), fontWeight: FontWeight.w600),
              ),
              _moderationStatusBadge(currentStatus.isEmpty ? 'verified' : currentStatus),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Quick Actions',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF475569)),
          ),
          const SizedBox(height: 8),

          // Action buttons in two rows
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              // Warn
              if (currentStatus != 'banned') _actionChip(
                context,
                icon: '⚠️', label: 'Warn',
                color: const Color(0xFFD97706),
                bg: const Color(0xFFFFFBEB),
                onTap: () => onOpenDialog(userId, userRole),
              ),
              // Restrict
              if (!isBanned) _actionChip(
                context,
                icon: '🔒', label: 'Restrict',
                color: const Color(0xFF7C3AED),
                bg: const Color(0xFFF5F3FF),
                onTap: () => onOpenDialog(userId, userRole),
              ),
              // Suspend
              if (!isBanned) _actionChip(
                context,
                icon: '🔴', label: 'Suspend',
                color: const Color(0xFFDC2626),
                bg: const Color(0xFFFFF1F2),
                onTap: () => onOpenDialog(userId, userRole),
              ),
              // Ban
              if (!isBanned) _actionChip(
                context,
                icon: '⛔', label: 'Ban',
                color: const Color(0xFF7F1D1D),
                bg: const Color(0xFFFEE2E2),
                onTap: () => onOpenDialog(userId, userRole),
              ),
              // Restore / Remove restrictions
              if (!isActive) _actionChip(
                context,
                icon: '↩️', label: 'Restore',
                color: const Color(0xFF059669),
                bg: const Color(0xFFF0FDF4),
                onTap: () => _showRestoreDialog(context),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _actionChip(
    BuildContext context, {
    required String icon,
    required String label,
    required Color color,
    required Color bg,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(icon, style: const TextStyle(fontSize: 12)),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showRestoreDialog(BuildContext context) async {
    final reasonController = TextEditingController();
    final messenger = ScaffoldMessenger.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('↩️ Restore Account', style: TextStyle(fontWeight: FontWeight.bold)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('This will remove all moderation actions and restore the account to active status.'),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              decoration: InputDecoration(
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                hintText: 'Reason for restoring (required)...',
                contentPadding: const EdgeInsets.all(10),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF059669), foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    final reason = reasonController.text.trim();
    if (reason.isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('Please enter a reason.')));
      return;
    }

    try {
      await AppRepositories.admin.removeModerationAction(
        targetUserId: userId,
        targetRole: userRole,
        action: 'restore',
        reason: reason,
      );
      onActionTaken();
      messenger.showSnackBar(
        const SnackBar(content: Text('Account restored.'), backgroundColor: Color(0xFF059669)),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Failed: $e'), backgroundColor: const Color(0xFFDC2626)));
    }
  }
}

// ─── Moderation Timeline Widget ──────────────────────────────────────────────

class _ModerationTimeline extends StatelessWidget {
  const _ModerationTimeline({required this.userId});
  final String userId;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ModerationHistoryEntry>>(
      stream: AppRepositories.support.watchModerationHistory(userId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: Padding(
            padding: EdgeInsets.all(8.0),
            child: CircularProgressIndicator(strokeWidth: 2),
          ));
        }

        final entries = snapshot.data ?? [];
        if (entries.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'No moderation history found.',
              style: TextStyle(fontSize: 12.5, fontStyle: FontStyle.italic, color: Color(0xFF64748B)),
            ),
          );
        }

        return ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: entries.length,
          itemBuilder: (context, index) {
            final entry = entries[index];
            final dateStr = '${entry.timestamp.day}/${entry.timestamp.month}/${entry.timestamp.year} ${entry.timestamp.hour.toString().padLeft(2, '0')}:${entry.timestamp.minute.toString().padLeft(2, '0')}';
            
            // Determine action color and icon
            Color actionColor;
            IconData actionIcon;
            switch (entry.action) {
              case 'warn':
                actionColor = const Color(0xFFD97706); // Amber
                actionIcon = Icons.warning_amber_rounded;
                break;
              case 'restrict':
                actionColor = const Color(0xFF7C3AED); // Purple
                actionIcon = Icons.lock_outline;
                break;
              case 'suspend':
                actionColor = const Color(0xFFDC2626); // Red
                actionIcon = Icons.gavel;
                break;
              case 'ban':
                actionColor = const Color(0xFF7F1D1D); // Dark Red
                actionIcon = Icons.block;
                break;
              case 'restore':
                actionColor = const Color(0xFF059669); // Green
                actionIcon = Icons.settings_backup_restore;
                break;
              default:
                actionColor = const Color(0xFF64748B); // Slate/Grey
                actionIcon = Icons.info_outline;
            }

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 6.0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: actionColor.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(actionIcon, size: 16, color: actionColor),
                      ),
                      if (index != entries.length - 1)
                        Container(
                          width: 2,
                          height: 35,
                          color: const Color(0xFFE2E8F0),
                        ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              entry.action.toUpperCase(),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: actionColor,
                              ),
                            ),
                            Text(
                              dateStr,
                              style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          entry.reason,
                          style: const TextStyle(fontSize: 12.5, color: Color(0xFF334155)),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'By: ${entry.adminEmail}',
                          style: const TextStyle(fontSize: 10, color: Color(0xFF64748B), fontStyle: FontStyle.italic),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}


