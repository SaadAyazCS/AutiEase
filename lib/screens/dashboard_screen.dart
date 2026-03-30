import 'package:flutter/material.dart';

import '../models/app_models.dart';
import '../repositories/app_repositories.dart';
import '../widgets/session_guard.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SessionGuard(
      role: SessionGuardRole.parent,
      child: FutureBuilder<ChildProfile?>(
        future: AppRepositories.users.getActiveChildForCurrentParent(),
        builder: (context, childSnapshot) {
          if (childSnapshot.connectionState == ConnectionState.waiting &&
              !childSnapshot.hasData) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }

          final child = childSnapshot.data;
          if (child == null) {
            return Scaffold(
              backgroundColor: const Color(0xFFF1EFF0),
              body: SafeArea(
                child: Center(
                  child: Container(
                    margin: const EdgeInsets.all(20),
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 12,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: const Text(
                      'No child profile found. Please create a child profile first.',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            );
          }

          return StreamBuilder<DashboardSnapshot?>(
            stream: AppRepositories.planner.watchDashboard(child.id),
            builder: (context, snapshot) {
              final dashboard = snapshot.data;
              return _DashboardHomeBody(
                childProfile: child,
                dashboard: dashboard,
              );
            },
          );
        },
      ),
    );
  }
}

class _DashboardHomeBody extends StatelessWidget {
  const _DashboardHomeBody({
    required this.childProfile,
    required this.dashboard,
  });

  final ChildProfile childProfile;
  final DashboardSnapshot? dashboard;

  @override
  Widget build(BuildContext context) {
    final completedActivities = dashboard == null
        ? 45
        : dashboard!.completedTasks;
    final weeklyHours = dashboard == null
        ? 8.5
        : (dashboard!.weeklyMinutes / 60.0);

    return Scaffold(
      backgroundColor: const Color(0xFFF1EFF0),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 20),
          children: [
            _DashboardHeaderCard(onBack: () => Navigator.pop(context)),
            const SizedBox(height: 14),
            _PanelCard(
              title: 'Health Overview',
              titleIcon: const Icon(
                Icons.favorite_border_rounded,
                color: Color(0xFFFF3B3B),
                size: 22,
              ),
              child: const Row(
                children: [
                  Expanded(
                    child: _HealthPill(label: 'Activity Level', value: 'High'),
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: _HealthPill(label: 'Mood', value: 'Happy'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _PanelCard(
              title: 'Learning Progress',
              titleIcon: const Icon(
                Icons.trending_up_rounded,
                color: Color(0xFF2F6FFF),
                size: 20,
              ),
              child: const Column(
                children: [
                  _LearningProgressRow(
                    label: 'Move & Play',
                    value: 0.85,
                    percentText: '85%',
                    barColor: Color(0xFF2F6FFF),
                  ),
                  SizedBox(height: 10),
                  _LearningProgressRow(
                    label: 'Talk & Express',
                    value: 0.72,
                    percentText: '72%',
                    barColor: Color(0xFF0FB247),
                  ),
                  SizedBox(height: 10),
                  _LearningProgressRow(
                    label: 'Focus Games',
                    value: 0.90,
                    percentText: '90%',
                    barColor: Color(0xFF8C3DE0),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _PanelCard(
              title: 'Recent Reports',
              titleIcon: const Icon(
                Icons.description_outlined,
                color: Color(0xFF9A4DFF),
                size: 20,
              ),
              child: Column(
                children: [
                  _RecentReportTile(
                    title: 'Weekly Progress Report',
                    date: 'Jan 1, 2026',
                    chipLabel: 'Progress',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              _ReportDetailScreen(report: _ReportData.weekly()),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 10),
                  _RecentReportTile(
                    title: 'Monthly Assessment',
                    date: 'Dec 15, 2025',
                    chipLabel: 'Assessment',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => _ReportDetailScreen(
                            report: _ReportData.monthly(),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _PanelCard(
              title: 'Weekly Activity',
              titleIcon: const Icon(
                Icons.show_chart_rounded,
                color: Color(0xFFFF6B1E),
                size: 20,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _WeekStatCard(
                      value: '$completedActivities',
                      label: 'Activities Completed',
                      valueColor: const Color(0xFF2967FF),
                      background: const Color(0xFFE4EBF5),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _WeekStatCard(
                      value: weeklyHours.toStringAsFixed(1),
                      label: 'Hours of Learning',
                      valueColor: const Color(0xFF0DA54D),
                      background: const Color(0xFFE2EFE8),
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
}

class _DashboardHeaderCard extends StatelessWidget {
  const _DashboardHeaderCard({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 14, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF0C5DF),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: onBack,
            child: Container(
              width: 32,
              height: 32,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.arrow_back_rounded,
                size: 20,
                color: Color(0xFF4C596E),
              ),
            ),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Dashboard',
                  style: TextStyle(
                    fontSize: 34 / 1.5,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF253246),
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'Track progress & health',
                  style: TextStyle(fontSize: 13, color: Color(0xFF667286)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PanelCard extends StatelessWidget {
  const _PanelCard({
    required this.title,
    required this.titleIcon,
    required this.child,
  });

  final String title;
  final Widget titleIcon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
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
            children: [
              titleIcon,
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 21 / 1.2,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF29384E),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _HealthPill extends StatelessWidget {
  const _HealthPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFE5F1EA),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 12, color: Color(0xFF5C6A79)),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: Color(0xFF263144),
            ),
          ),
        ],
      ),
    );
  }
}

class _LearningProgressRow extends StatelessWidget {
  const _LearningProgressRow({
    required this.label,
    required this.value,
    required this.percentText,
    required this.barColor,
  });

  final String label;
  final double value;
  final String percentText;
  final Color barColor;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 13, color: Color(0xFF364457)),
            ),
            const Spacer(),
            Text(
              percentText,
              style: const TextStyle(fontSize: 12.5, color: Color(0xFF5D6A7A)),
            ),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: value,
            minHeight: 6,
            color: barColor,
            backgroundColor: const Color(0xFFDEE2E8),
          ),
        ),
      ],
    );
  }
}

class _RecentReportTile extends StatelessWidget {
  const _RecentReportTile({
    required this.title,
    required this.date,
    required this.chipLabel,
    required this.onTap,
  });

  final String title;
  final String date;
  final String chipLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF5F5F8),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16 / 1.2,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF2D3B4F),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      date,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: Color(0xFF6E7A8A),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFFEADCF7),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  chipLabel,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: Color(0xFFA033FF),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WeekStatCard extends StatelessWidget {
  const _WeekStatCard({
    required this.value,
    required this.label,
    required this.valueColor,
    required this.background,
  });

  final String value;
  final String label;
  final Color valueColor;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              color: valueColor,
              fontSize: 39 / 1.5,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: Color(0xFF5F6E7F)),
          ),
        ],
      ),
    );
  }
}

class _ReportDetailScreen extends StatefulWidget {
  const _ReportDetailScreen({required this.report});

  final _ReportData report;

  @override
  State<_ReportDetailScreen> createState() => _ReportDetailScreenState();
}

class _ReportDetailScreenState extends State<_ReportDetailScreen> {
  List<TherapistProfile> _therapists = const <TherapistProfile>[];
  bool _loadingTherapists = true;

  @override
  void initState() {
    super.initState();
    _loadTherapists();
  }

  Future<void> _loadTherapists() async {
    try {
      final therapists = await AppRepositories.support.listTherapists();
      if (!mounted) {
        return;
      }
      setState(() {
        _therapists = therapists;
        _loadingTherapists = false;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _therapists = const <TherapistProfile>[];
        _loadingTherapists = false;
      });
    }
  }

  void _openShareSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return _ShareReportSheet(
          reportTitle: widget.report.title,
          isLoadingTherapists: _loadingTherapists,
          therapists: _therapists,
        );
      },
    );
  }

  void _downloadReport() {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Preparing PDF download...')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1EFF0),
      body: SafeArea(
        child: Column(
          children: [
            _ReportHeader(
              title: widget.report.title,
              dateLabel: widget.report.dateLabel,
              onBack: () => Navigator.pop(context),
              onShare: _openShareSheet,
              onDownload: _downloadReport,
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 88),
                children: [
                  _SummaryCard(
                    title: 'Summary',
                    subtitle: widget.report.summarySubtitle,
                    body: widget.report.summaryText,
                  ),
                  const SizedBox(height: 10),
                  for (final section in widget.report.sections) ...[
                    _ProgressSectionCard(section: section),
                    const SizedBox(height: 10),
                  ],
                  _RecommendationsCard(items: widget.report.recommendations),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          color: const Color(0xFFF1EFF0),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
          child: Row(
            children: [
              Expanded(
                child: _ReportActionButton(
                  label: 'Share Report',
                  icon: Icons.share_outlined,
                  color: const Color(0xFFEF2F98),
                  onTap: _openShareSheet,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ReportActionButton(
                  label: 'Download PDF',
                  icon: Icons.download_rounded,
                  color: const Color(0xFF344560),
                  onTap: _downloadReport,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReportHeader extends StatelessWidget {
  const _ReportHeader({
    required this.title,
    required this.dateLabel,
    required this.onBack,
    required this.onShare,
    required this.onDownload,
  });

  final String title;
  final String dateLabel;
  final VoidCallback onBack;
  final VoidCallback onShare;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF0C5DF),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          InkWell(
            onTap: onBack,
            borderRadius: BorderRadius.circular(999),
            child: Container(
              width: 34,
              height: 34,
              decoration: const BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.arrow_back_rounded,
                size: 20,
                color: Color(0xFF4C596E),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18 / 1.2,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF273349),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  dateLabel,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF6B7687),
                  ),
                ),
              ],
            ),
          ),
          _CircleIconButton(icon: Icons.share_outlined, onTap: onShare),
          const SizedBox(width: 8),
          _CircleIconButton(icon: Icons.download_rounded, onTap: onDownload),
        ],
      ),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.16),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(icon, size: 18, color: const Color(0xFF596578)),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.title,
    required this.subtitle,
    required this.body,
  });

  final String title;
  final String subtitle;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F6F8),
        borderRadius: BorderRadius.circular(12),
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
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: const Color(0xFFF8D8EC),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Icon(
                  Icons.trending_up_rounded,
                  size: 16,
                  color: Color(0xFFF04EA7),
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 19 / 1.2,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFF2E3C50),
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF9AA3B1),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            body,
            style: const TextStyle(
              fontSize: 14,
              height: 1.5,
              color: Color(0xFF38475B),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProgressSectionCard extends StatelessWidget {
  const _ProgressSectionCard({required this.section});

  final _ReportSectionData section;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F6F8),
        borderRadius: BorderRadius.circular(12),
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
            children: [
              Icon(section.icon, size: 18, color: section.iconColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  section.title,
                  style: const TextStyle(
                    fontSize: 20 / 1.2,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF2E3C50),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: section.percentBgColor,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  section.percentLabel,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: section.percentTextColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            section.body,
            style: const TextStyle(
              fontSize: 14,
              height: 1.5,
              color: Color(0xFF38475B),
            ),
          ),
          const SizedBox(height: 10),
          Container(height: 1, color: Colors.black.withValues(alpha: 0.08)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: section.statusChipBgColor,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              section.statusLabel,
              style: TextStyle(
                fontSize: 11,
                color: section.statusChipTextColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecommendationsCard extends StatelessWidget {
  const _RecommendationsCard({required this.items});

  final List<String> items;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F2FE),
        borderRadius: BorderRadius.circular(12),
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
          const Text(
            'Therapist Recommendations',
            style: TextStyle(
              fontSize: 20 / 1.2,
              fontWeight: FontWeight.w500,
              color: Color(0xFF2E3C50),
            ),
          ),
          const SizedBox(height: 8),
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '• $item',
                style: const TextStyle(
                  color: Color(0xFF35507A),
                  height: 1.45,
                  fontSize: 14,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ReportActionButton extends StatelessWidget {
  const _ReportActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(vertical: 12),
      ),
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }
}

enum _ShareSheetPhase { loading, noTherapists, selecting, sharing, success }

class _ShareReportSheet extends StatefulWidget {
  const _ShareReportSheet({
    required this.reportTitle,
    required this.isLoadingTherapists,
    required this.therapists,
  });

  final String reportTitle;
  final bool isLoadingTherapists;
  final List<TherapistProfile> therapists;

  @override
  State<_ShareReportSheet> createState() => _ShareReportSheetState();
}

class _ShareReportSheetState extends State<_ShareReportSheet> {
  _ShareSheetPhase _phase = _ShareSheetPhase.loading;
  String? _selectedTherapistId;

  @override
  void initState() {
    super.initState();
    if (widget.isLoadingTherapists) {
      _phase = _ShareSheetPhase.loading;
    } else if (widget.therapists.isEmpty) {
      _phase = _ShareSheetPhase.noTherapists;
    } else {
      _phase = _ShareSheetPhase.selecting;
    }
  }

  Future<void> _share() async {
    if (_selectedTherapistId == null) {
      return;
    }
    setState(() => _phase = _ShareSheetPhase.sharing);
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    if (!mounted) {
      return;
    }
    setState(() => _phase = _ShareSheetPhase.success);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 6),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'Share Report',
                  style: TextStyle(
                    fontSize: 22 / 1.2,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF2E3C50),
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                  color: const Color(0xFF677386),
                ),
              ],
            ),
            Text(
              widget.reportTitle,
              style: const TextStyle(fontSize: 11.5, color: Color(0xFF8A94A3)),
            ),
            const SizedBox(height: 14),
            if (_phase == _ShareSheetPhase.loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 18),
                child: Center(child: CircularProgressIndicator()),
              ),
            if (_phase == _ShareSheetPhase.noTherapists)
              SizedBox(
                width: double.infinity,
                child: Column(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: const BoxDecoration(
                        color: Color(0xFFF1F2F5),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.person_outline_rounded,
                        color: Color(0xFF75829A),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'No Therapists Found',
                      style: TextStyle(
                        fontSize: 20 / 1.2,
                        color: Color(0xFF2E3C50),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Subscribe to a therapist to share reports',
                      style: TextStyle(color: Color(0xFF6D798A)),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            if (_phase == _ShareSheetPhase.selecting ||
                _phase == _ShareSheetPhase.sharing) ...[
              const Text(
                'Select therapists to share this report with:',
                style: TextStyle(fontSize: 12.5, color: Color(0xFF6B7689)),
              ),
              const SizedBox(height: 10),
              for (final therapist in widget.therapists)
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8E5F1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: const BoxDecoration(
                          color: Color(0xFFEAF3DF),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.emoji_objects_outlined,
                          size: 18,
                          color: Color(0xFFE2B500),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              therapist.displayName,
                              style: const TextStyle(
                                fontSize: 18 / 1.2,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF2D3950),
                              ),
                            ),
                            Text(
                              therapist.specializations.isEmpty
                                  ? 'Behavioral Therapy'
                                  : therapist.specializations.first,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF7B8798),
                              ),
                            ),
                          ],
                        ),
                      ),
                      InkWell(
                        onTap: _phase == _ShareSheetPhase.sharing
                            ? null
                            : () {
                                setState(() {
                                  _selectedTherapistId =
                                      _selectedTherapistId == therapist.id
                                      ? null
                                      : therapist.id;
                                });
                              },
                        borderRadius: BorderRadius.circular(999),
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _selectedTherapistId == therapist.id
                                ? const Color(0xFFEF2F98)
                                : const Color(0xFFD3D8E0),
                          ),
                          child: _selectedTherapistId == therapist.id
                              ? const Icon(
                                  Icons.check,
                                  color: Colors.white,
                                  size: 14,
                                )
                              : null,
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 2),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed:
                      (_selectedTherapistId != null &&
                          _phase == _ShareSheetPhase.selecting)
                      ? _share
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFEF2F98),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(0xFFF2A4D1),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: _phase == _ShareSheetPhase.sharing
                      ? const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            ),
                            SizedBox(width: 8),
                            Text('Sharing...'),
                          ],
                        )
                      : Text(
                          _selectedTherapistId == null
                              ? 'Select at least one therapist'
                              : 'Share with 1 therapist',
                        ),
                ),
              ),
            ],
            if (_phase == _ShareSheetPhase.success)
              const SizedBox(
                width: double.infinity,
                child: Column(
                  children: [
                    SizedBox(height: 8),
                    Icon(
                      Icons.check_circle_rounded,
                      size: 56,
                      color: Color(0xFFBEF0D0),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Report Shared!',
                      style: TextStyle(
                        fontSize: 30 / 1.5,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF2E3C50),
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Successfully shared with 1 therapist',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFF6B7688)),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ReportData {
  const _ReportData({
    required this.title,
    required this.dateLabel,
    required this.summarySubtitle,
    required this.summaryText,
    required this.sections,
    required this.recommendations,
  });

  final String title;
  final String dateLabel;
  final String summarySubtitle;
  final String summaryText;
  final List<_ReportSectionData> sections;
  final List<String> recommendations;

  factory _ReportData.weekly() {
    return _ReportData(
      title: 'Weekly Progress Report',
      dateLabel: 'Jan 1, 2026',
      summarySubtitle: 'Progress',
      summaryText:
          'This week has shown remarkable improvements across multiple developmental areas. Your child has demonstrated increased engagement in social activities and improved communication skills during therapy sessions.',
      sections: const [
        _ReportSectionData(
          title: 'Move & Play',
          icon: Icons.check_circle_outline_rounded,
          iconColor: Color(0xFF1EA955),
          percentLabel: '85%',
          percentBgColor: Color(0xFFCBEFD5),
          percentTextColor: Color(0xFF198C45),
          body:
              'Significant progress observed in verbal expression and vocabulary usage. Your child has been using more complex sentences and showing better understanding of context. They initiated conversations 12 times this week, up from 8 last week.',
          statusLabel: 'Excellent Progress',
          statusChipBgColor: Color(0xFFCFEFD2),
          statusChipTextColor: Color(0xFF198C45),
        ),
        _ReportSectionData(
          title: 'Talk & Express',
          icon: Icons.trending_up_rounded,
          iconColor: Color(0xFF2C64F5),
          percentLabel: '72%',
          percentBgColor: Color(0xFFD8E4FB),
          percentTextColor: Color(0xFF2C64F5),
          body:
              'Good improvement in peer interactions during group activities. Your child participated in 4 out of 5 group sessions and showed willingness to share toys with others. Some hesitation remains in larger groups.',
          statusLabel: 'Good Progress',
          statusChipBgColor: Color(0xFFD8E4FB),
          statusChipTextColor: Color(0xFF2C64F5),
        ),
        _ReportSectionData(
          title: 'Focus Games',
          icon: Icons.check_circle_outline_rounded,
          iconColor: Color(0xFF1EA955),
          percentLabel: '90%',
          percentBgColor: Color(0xFFCBEFD5),
          percentTextColor: Color(0xFF198C45),
          body:
              'Excellent progress in fine motor skills development. Successfully completed all hand-eye coordination exercises. Drawing and writing activities show marked improvement with better grip and control.',
          statusLabel: 'Excellent Progress',
          statusChipBgColor: Color(0xFFCFEFD2),
          statusChipTextColor: Color(0xFF198C45),
        ),
      ],
      recommendations: const [
        'Continue with daily communication exercises for 15-20 minutes',
        'Practice social scenarios through role-play activities',
        'Maintain consistent sleep schedule to support cognitive development',
        'Schedule follow-up assessment in 2 weeks',
      ],
    );
  }

  factory _ReportData.monthly() {
    return _ReportData(
      title: 'Monthly Assessment',
      dateLabel: 'Dec 15, 2025',
      summarySubtitle: 'Assessment',
      summaryText:
          'Comprehensive monthly evaluation showing overall positive developmental trajectory. Your child has met 75% of the monthly goals and is progressing well towards the quarterly objectives.',
      sections: const [
        _ReportSectionData(
          title: 'Overall Development',
          icon: Icons.check_circle_outline_rounded,
          iconColor: Color(0xFF1EA955),
          percentLabel: '82%',
          percentBgColor: Color(0xFFCBEFD5),
          percentTextColor: Color(0xFF198C45),
          body:
              'Your child has made consistent progress across all developmental domains. Particularly strong performance in motor skills and communication. Social skills are developing steadily with increased confidence in group settings.',
          statusLabel: 'Excellent Progress',
          statusChipBgColor: Color(0xFFCFEFD2),
          statusChipTextColor: Color(0xFF198C45),
        ),
        _ReportSectionData(
          title: 'Goal Achievement',
          icon: Icons.trending_up_rounded,
          iconColor: Color(0xFF2C64F5),
          percentLabel: '75%',
          percentBgColor: Color(0xFFD8E4FB),
          percentTextColor: Color(0xFF2C64F5),
          body:
              'Achieved 9 out of 12 monthly goals. Excellent progress in self-help skills and following routines. Communication goals are on track. Social interaction goals need continued focus and practice.',
          statusLabel: 'Good Progress',
          statusChipBgColor: Color(0xFFD8E4FB),
          statusChipTextColor: Color(0xFF2C64F5),
        ),
        _ReportSectionData(
          title: 'Areas for Growth',
          icon: Icons.error_outline_rounded,
          iconColor: Color(0xFFFF8D2D),
          percentLabel: '65%',
          percentBgColor: Color(0xFFF9E2CF),
          percentTextColor: Color(0xFFCF7020),
          body:
              'Continue working on emotional regulation during transitions. Practice sharing and turn-taking in various settings. Increase exposure to diverse social situations gradually.',
          statusLabel: 'Needs Improvement',
          statusChipBgColor: Color(0xFFF9E2CF),
          statusChipTextColor: Color(0xFFCF7020),
        ),
      ],
      recommendations: const [
        'Continue with daily communication exercises for 15-20 minutes',
        'Practice social scenarios through role-play activities',
        'Maintain consistent sleep schedule to support cognitive development',
        'Schedule follow-up assessment in 2 weeks',
      ],
    );
  }
}

class _ReportSectionData {
  const _ReportSectionData({
    required this.title,
    required this.icon,
    required this.iconColor,
    required this.percentLabel,
    required this.percentBgColor,
    required this.percentTextColor,
    required this.body,
    required this.statusLabel,
    required this.statusChipBgColor,
    required this.statusChipTextColor,
  });

  final String title;
  final IconData icon;
  final Color iconColor;
  final String percentLabel;
  final Color percentBgColor;
  final Color percentTextColor;
  final String body;
  final String statusLabel;
  final Color statusChipBgColor;
  final Color statusChipTextColor;
}
