import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/app_models.dart';
import '../repositories/app_repositories.dart';

class TherapistSchedulerScreen extends StatefulWidget {
  const TherapistSchedulerScreen({
    super.key,
    required this.therapistId,
  });

  final String therapistId;

  @override
  State<TherapistSchedulerScreen> createState() => _TherapistSchedulerScreenState();
}

class _TherapistSchedulerScreenState extends State<TherapistSchedulerScreen> {
  bool _submitting = false;
  List<TherapyPackage> _packages = [];
  bool _loadingPackages = true;

  @override
  void initState() {
    super.initState();
    _loadTherapistPackages();
  }

  Future<void> _loadTherapistPackages() async {
    try {
      final profile = await AppRepositories.support.getTherapistById(widget.therapistId);
      if (mounted) {
        setState(() {
          _packages = profile?.servicePackages.where((p) => p.visible).toList() ?? [];
          _loadingPackages = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loadingPackages = false);
      }
    }
  }

  String _formatTimeRange(DateTime start, int durationMinutes) {
    final end = start.add(Duration(minutes: durationMinutes));
    String formatTime(DateTime dt) {
      final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
      final minute = dt.minute.toString().padLeft(2, '0');
      final ampm = dt.hour >= 12 ? 'PM' : 'AM';
      return '$hour:$minute $ampm';
    }
    return '${formatTime(start)} - ${formatTime(end)}';
  }

  Future<void> _selectAndAddSlot({SlotRequest? prefillRequest}) async {
    if (_loadingPackages) return;

    DateTime initialDate = DateTime.now().add(const Duration(days: 1));
    TimeOfDay initialTime = const TimeOfDay(hour: 9, minute: 0);
    TherapyPackage? selectedPackage;

    if (prefillRequest != null) {
      initialDate = prefillRequest.preferredDateTime;
      initialTime = TimeOfDay(hour: prefillRequest.preferredDateTime.hour, minute: prefillRequest.preferredDateTime.minute);
      // Pre-select package if title matches
      final found = _packages.where((p) => p.title == prefillRequest.packageTitle);
      if (found.isNotEmpty) {
        selectedPackage = found.first;
      }
    }

    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initialDate.isBefore(DateTime.now()) ? DateTime.now() : initialDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 90)),
    );
    if (pickedDate == null) return;

    if (!mounted) return;
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: initialTime,
    );
    if (pickedTime == null) return;

    final dateTime = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );

    if (dateTime.isBefore(DateTime.now())) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cannot add slots in the past.'), backgroundColor: Color(0xFFEF4444)),
        );
      }
      return;
    }

    // Open Dialog for package selection & duration verification
    if (!mounted) return;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) {
        final matchingPkg = prefillRequest != null
            ? _packages.firstWhere(
                (p) => p.title.trim().toLowerCase() == prefillRequest.packageTitle.trim().toLowerCase(),
                orElse: () => TherapyPackage(
                  title: prefillRequest.packageTitle,
                  price: 0,
                  durationMinutes: 60,
                  sessionsPerWeek: 1,
                  description: '',
                ),
              )
            : selectedPackage;
        TherapyPackage? localSelectedPkg = prefillRequest != null ? matchingPkg : selectedPackage;
        final durationController = TextEditingController(text: '${matchingPkg?.durationMinutes ?? 60}');

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Text('Configure Slot Options', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Select Subscribed Package (Optional):', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                  const SizedBox(height: 6),
                  if (prefillRequest != null) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Text(
                        prefillRequest.packageTitle,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF1E293B)),
                      ),
                    ),
                  ] else ...[
                    DropdownButtonFormField<TherapyPackage>(
                      initialValue: localSelectedPkg,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      ),
                      hint: const Text('None (General Slot)'),
                      items: [
                        const DropdownMenuItem<TherapyPackage>(
                          value: null,
                          child: Text('General Slot (No Package)', style: TextStyle(fontSize: 13, color: Color(0xFF64748B))),
                        ),
                        ..._packages.map((pkg) {
                          return DropdownMenuItem<TherapyPackage>(
                            value: pkg,
                            child: Text(pkg.title, style: const TextStyle(fontSize: 13)),
                          );
                        }),
                      ],
                      onChanged: (val) {
                        setDialogState(() {
                          localSelectedPkg = val;
                          if (val != null) {
                            durationController.text = '${val.durationMinutes}';
                          } else {
                            durationController.text = '60';
                          }
                        });
                      },
                    ),
                  ],
                  const SizedBox(height: 14),
                  const Text('Session Duration (Minutes):', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                  const SizedBox(height: 6),
                  TextField(
                    controller: durationController,
                    keyboardType: TextInputType.number,
                    enabled: prefillRequest == null,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      fillColor: prefillRequest != null ? const Color(0xFFF1F5F9) : null,
                      filled: prefillRequest != null,
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
                ),
                ElevatedButton(
                  onPressed: () {
                    final duration = int.tryParse(durationController.text.trim()) ?? 60;
                    if (duration < 15 || duration > 480) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(content: Text('Duration must be between 15 and 480 minutes.')),
                      );
                      return;
                    }
                    Navigator.pop(ctx, {
                      'packageTitle': prefillRequest != null ? prefillRequest.packageTitle : localSelectedPkg?.title,
                      'duration': duration,
                    });
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0D9488), foregroundColor: Colors.white),
                  child: const Text('Confirm & Save'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == null) return;

    final String? packageTitle = result['packageTitle'];
    final int duration = result['duration'];

    setState(() => _submitting = true);
    try {
      await AppRepositories.support.createAppointmentSlot(
        therapistId: widget.therapistId,
        dateTime: dateTime,
        durationMinutes: duration,
        packageTitle: packageTitle,
        assignedToParentId: prefillRequest?.parentId,
      );

      if (prefillRequest != null) {
        await AppRepositories.support.markSlotRequestAsCreated(prefillRequest.id);
        
        final therapistProfile = await AppRepositories.support.getTherapistById(widget.therapistId);
        final therapistName = therapistProfile?.displayName.isNotEmpty == true
            ? therapistProfile!.displayName
            : 'Therapist';

        final msg = 'Your custom slot request for "${prefillRequest.packageTitle}" has been approved by Therapist $therapistName. Please look into the scheduler section where your custom slot is highlighted in teal. You can now tap to book it.';

        // Write notification to Firestore for the requesting parent
        await FirebaseFirestore.instance.collection('notifications').add({
          'userId': prefillRequest.parentId,
          'title': '✅ Custom Slot Request Approved',
          'message': msg,
          'category': 'scheduler',
          'isRead': false,
          'timestamp': FieldValue.serverTimestamp(),
          'navigationTarget': {
            'route': 'ParentScheduler',
            'therapistId': widget.therapistId,
            'therapistName': therapistName,
          },
        });

        // Send active push/system notification
        try {
          await AppRepositories.support.sendNotification(
            userId: prefillRequest.parentId,
            title: 'Custom Slot Request Approved',
            message: msg,
            category: 'messages',
            navigationTarget: {
              'route': 'ParentScheduler',
              'therapistId': widget.therapistId,
              'therapistName': therapistName,
            },
          );
        } catch (e) {
          debugPrint('Error sending push notification for slot approval: $e');
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Slot added successfully.'), backgroundColor: Color(0xFF059669)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to add slot: $e'), backgroundColor: const Color(0xFFEF4444)),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _submitting = false);
      }
    }
  }

  Future<void> _declineRequest(SlotRequest request) async {
    final reasonController = TextEditingController();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Decline Slot Request'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Please provide a reason to help the parent understand:', style: TextStyle(fontSize: 13, color: Color(0xFF64748B))),
            const SizedBox(height: 10),
            TextField(
              controller: reasonController,
              decoration: InputDecoration(
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                hintText: 'e.g., I am not available at this hour...',
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B)))),
          ElevatedButton(
            onPressed: () {
              if (reasonController.text.trim().isEmpty) {
                ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Please enter a reason.')));
                return;
              }
              Navigator.pop(ctx, true);
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444), foregroundColor: Colors.white),
            child: const Text('Decline Request'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final therapistProfile = await AppRepositories.support.getTherapistById(widget.therapistId);
      final therapistName = therapistProfile?.displayName.isNotEmpty == true
          ? therapistProfile!.displayName
          : 'Therapist';

      final reason = reasonController.text.trim();
      await AppRepositories.support.declineSlotRequest(request.id, reason);

      // Write notification to Firestore for the requesting parent
      await FirebaseFirestore.instance.collection('notifications').add({
        'userId': request.parentId,
        'title': '❌ Custom Slot Request Declined',
        'message': 'Therapist $therapistName has declined your request for a custom slot. Reason: $reason',
        'category': 'messages',
        'timestamp': FieldValue.serverTimestamp(),
        'isRead': false,
      });

      await AppRepositories.support.sendNotification(
        userId: request.parentId,
        title: 'Custom Slot Request Declined',
        message: 'Therapist $therapistName has declined your request for a custom slot. Reason: $reason',
        category: 'messages',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Request declined successfully.'), backgroundColor: Color(0xFFEF4444)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          title: const Text('Manage Appointments'),
          backgroundColor: const Color(0xFF0D9488),
          foregroundColor: Colors.white,
          bottom: TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: const Color(0xFFB2DFDB),
            indicatorColor: Colors.white,
            tabs: [
              const Tab(icon: Icon(Icons.schedule_rounded), text: 'Availability Slots'),
              Tab(
                child: StreamBuilder<List<SlotRequest>>(
                  stream: AppRepositories.support.watchSlotRequestsForTherapist(widget.therapistId),
                  builder: (context, snapshot) {
                    final requests = snapshot.data ?? [];
                    final pendingCount = requests.where((r) => r.status == 'pending').length;
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.mail_outline_rounded),
                        const SizedBox(width: 8),
                        const Text('Slot Requests'),
                        if (pendingCount > 0) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.red,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            constraints: const BoxConstraints(
                              minWidth: 16,
                              minHeight: 16,
                            ),
                            child: Text(
                              '$pendingCount',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        floatingActionButton: Builder(
          builder: (context) {
            return FloatingActionButton.extended(
              onPressed: _submitting ? null : () => _selectAndAddSlot(),
              backgroundColor: const Color(0xFF0D9488),
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: const Text('Add Time Slot'),
            );
          },
        ),
        body: TabBarView(
          children: [
            _buildSlotsTab(),
            _buildRequestsTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildSlotsTab() {
    return StreamBuilder<List<AppointmentSlot>>(
      stream: AppRepositories.support.watchSlotsForTherapist(widget.therapistId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        }

        final slots = snapshot.data ?? [];
        if (slots.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.calendar_today_outlined, size: 64, color: Color(0xFFCBD5E1)),
                SizedBox(height: 16),
                Text('No slots configured yet.', style: TextStyle(color: Color(0xFF64748B), fontSize: 16)),
                SizedBox(height: 8),
                Text('Tap the + button to define your available hours.', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
              ],
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
          itemCount: slots.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final slot = slots[index];
            final dt = slot.dateTime;
            final dateStr = '${dt.day}/${dt.month}/${dt.year}';
            final isBooked = slot.status == 'booked';

            return Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: isBooked ? const Color(0xFFE2E8F0) : const Color(0xFFD1FAE5),
                  width: isBooked ? 1 : 1.5,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: isBooked ? const Color(0xFFEFF6FF) : const Color(0xFFECFDF5),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            isBooked ? Icons.event_available_rounded : Icons.schedule_rounded,
                            color: isBooked ? const Color(0xFF3B82F6) : const Color(0xFF10B981),
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                dateStr,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF1E293B)),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                _formatTimeRange(dt, slot.durationMinutes),
                                style: const TextStyle(fontSize: 13, color: Color(0xFF475569), fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 4),
                              if (slot.assignedToParentId != null) ...[
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFCCFBF1),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    '✨ Requested: ${slot.packageTitle ?? "General Slot"}',
                                    style: const TextStyle(fontSize: 10.5, color: Color(0xFF0F766E), fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ] else ...[
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: slot.packageTitle != null ? const Color(0xFFF1F5F9) : const Color(0xFFFEF3C7),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    slot.packageTitle != null
                                        ? 'Package: ${slot.packageTitle}'
                                        : 'General Slot',
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      color: slot.packageTitle != null ? const Color(0xFF475569) : const Color(0xFFB45309),
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: isBooked ? const Color(0xFFDBEAFE) : const Color(0xFFD1FAE5),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            slot.status.toUpperCase(),
                            style: TextStyle(
                              color: isBooked ? const Color(0xFF1E40AF) : const Color(0xFF065F46),
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (isBooked) ...[
                      const SizedBox(height: 12),
                      const Divider(),
                      const SizedBox(height: 8),
                      Text(
                        'Client: ${slot.bookedForChildName ?? 'Child Profile'}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF334155)),
                      ),
                      if (slot.notes != null && slot.notes!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Notes: ${slot.notes}',
                          style: const TextStyle(fontSize: 12.5, color: Color(0xFF475569)),
                        ),
                      ],
                    ],
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (isBooked) ...[
                          OutlinedButton.icon(
                            onPressed: () async {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: const Text('Cancel Appointment?'),
                                  content: const Text('Are you sure you want to cancel this booked appointment slot?'),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('No')),
                                    TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Yes')),
                                  ],
                                ),
                              );
                              if (confirm == true) {
                                await AppRepositories.support.cancelAppointmentSlot(
                                  slot.id,
                                  therapistId: widget.therapistId,
                                  parentId: slot.bookedByParentId,
                                );
                              }
                            },
                            icon: const Icon(Icons.cancel_outlined, size: 16),
                            label: const Text('Cancel Session'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFFEF4444),
                              side: const BorderSide(color: Color(0xFFEF4444)),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                        ] else ...[
                          IconButton(
                            icon: const Icon(Icons.delete_outline, color: Color(0xFFEF4444)),
                            onPressed: () async {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: const Text('Delete Slot?'),
                                  content: const Text('Are you sure you want to delete this available slot?'),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                                    TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
                                  ],
                                ),
                              );
                              if (confirm == true) {
                                  await AppRepositories.support.deleteAppointmentSlot(slot.id);
                              }
                            },
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildRequestsTab() {
    return StreamBuilder<List<SlotRequest>>(
      stream: AppRepositories.support.watchSlotRequestsForTherapist(widget.therapistId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Error loading requests: ${snapshot.error}'));
        }

        final requests = (snapshot.data ?? []).where((r) => r.status == 'pending').toList();
        if (requests.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.mark_email_read_outlined, size: 64, color: Color(0xFFCBD5E1)),
                SizedBox(height: 16),
                Text('No pending slot requests.', style: TextStyle(color: Color(0xFF64748B), fontSize: 16)),
              ],
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: requests.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final req = requests[index];
            final dt = req.preferredDateTime;
            final dateStr = '${dt.day}/${dt.month}/${dt.year}';
            final timeStr = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

            return Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const CircleAvatar(
                          backgroundColor: Color(0xFFE0F2F1),
                          child: Icon(Icons.person_outline, color: Color(0xFF00796B)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                req.parentName,
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF1E293B)),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Package: ${req.packageTitle}',
                                style: const TextStyle(fontSize: 12, color: Color(0xFF64748B), fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    const Divider(),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const Icon(Icons.event_note_rounded, size: 16, color: Color(0xFF64748B)),
                        const SizedBox(width: 8),
                        Text(
                          'Preferred: $dateStr at $timeStr',
                          style: const TextStyle(fontSize: 13, color: Color(0xFF334155), fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        OutlinedButton(
                          onPressed: () => _declineRequest(req),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFEF4444),
                            side: const BorderSide(color: Color(0xFFEF4444)),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          child: const Text('Decline'),
                        ),
                        const SizedBox(width: 10),
                        ElevatedButton(
                          onPressed: () => _selectAndAddSlot(prefillRequest: req),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0D9488),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          child: const Text('Approve & Create'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
