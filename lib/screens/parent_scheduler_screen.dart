import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/app_models.dart';
import '../repositories/app_repositories.dart';
import '../services/notification_service.dart';

class ParentSchedulerScreen extends StatefulWidget {
  const ParentSchedulerScreen({
    super.key,
    required this.therapistId,
    required this.therapistName,
    required this.parentId,
    required this.childId,
    required this.childName,
  });

  final String therapistId;
  final String therapistName;
  final String parentId;
  final String childId;
  final String childName;

  @override
  State<ParentSchedulerScreen> createState() => _ParentSchedulerScreenState();
}

class _ParentSchedulerScreenState extends State<ParentSchedulerScreen> {
  final _notesCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  AppointmentSlot? _selectedSlot;
  bool _submitting = false;

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text('Book Session - ${widget.therapistName}'),
        backgroundColor: const Color(0xFF0D9488),
        foregroundColor: Colors.white,
      ),
      body: StreamBuilder<List<AppointmentSlot>>(
        stream: AppRepositories.support.watchSlotsForTherapist(widget.therapistId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }

          final allSlots = snapshot.data ?? [];
          
          // Check if parent already has a booked session with this therapist
          AppointmentSlot? parentBookedSlot;
          for (final s in allSlots) {
            if (s.status == 'booked' && s.bookedByParentId == widget.parentId) {
              parentBookedSlot = s;
              break;
            }
          }

          // Render booked slot UI if exists
          if (parentBookedSlot != null) {
            final dt = parentBookedSlot.dateTime;
            final dateStr = '${dt.day}/${dt.month}/${dt.year}';
            final timeStr = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
            
            return SingleChildScrollView(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFECFDF5),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFA7F3D0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.check_circle_rounded, color: Color(0xFF059669), size: 24),
                            SizedBox(width: 10),
                            Text(
                              'Your Booked Session',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF065F46),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'Date & Time: $dateStr at $timeStr',
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF065F46),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Duration: ${parentBookedSlot.durationMinutes} minutes',
                          style: const TextStyle(
                            fontSize: 13,
                            color: Color(0xFF047857),
                          ),
                        ),
                        if (parentBookedSlot.notes != null && parentBookedSlot.notes!.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          const Text(
                            'Your Session Notes:',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF065F46),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: const Color(0xFFD1FAE5)),
                            ),
                            child: Text(
                              parentBookedSlot.notes!,
                              style: const TextStyle(
                                fontSize: 13,
                                color: Color(0xFF065F46),
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _submitting
                                ? null
                                : () async {
                                    final confirm = await showDialog<bool>(
                                      context: context,
                                      builder: (ctx) => AlertDialog(
                                        title: const Text('Cancel Session?'),
                                        content: const Text(
                                          'Are you sure you want to cancel your scheduled session? This will notify your therapist.',
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.pop(ctx, false),
                                            child: const Text('No'),
                                          ),
                                          TextButton(
                                            onPressed: () => Navigator.pop(ctx, true),
                                            child: const Text('Yes, Cancel'),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (confirm == true) {
                                      setState(() => _submitting = true);
                                      try {
                                        await AppRepositories.support.cancelAppointmentSlot(
                                          parentBookedSlot!.id,
                                          therapistId: widget.therapistId,
                                          parentId: widget.parentId,
                                          parentName: FirebaseAuth.instance.currentUser?.displayName ?? '',
                                        );
                                        try {
                                          await NotificationService.instance.cancelSessionReminder(
                                            parentBookedSlot.id.hashCode.abs(),
                                          );
                                        } catch (_) {}
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(
                                              content: Text('Session cancelled successfully.'),
                                              backgroundColor: Color(0xFF10B981),
                                            ),
                                          );
                                        }
                                      } catch (e) {
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Text('Failed to cancel session: $e'),
                                              backgroundColor: const Color(0xFFEF4444),
                                            ),
                                          );
                                        }
                                      } finally {
                                        if (mounted) {
                                          setState(() => _submitting = false);
                                        }
                                      }
                                    }
                                  },
                            icon: const Icon(Icons.cancel_outlined, size: 18),
                            label: const Text('Cancel Scheduled Session'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFEF4444),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFFBEB),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFFDE68A)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.info_outline_rounded, color: Color(0xFFD97706), size: 20),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'You cannot book another slot while you already have an active session booked with this therapist. To change your slot, please cancel your existing session first.',
                            style: TextStyle(
                              fontSize: 13,
                              color: Color(0xFF92400E),
                              fontWeight: FontWeight.w500,
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

          final slots = allSlots
              .where((slot) => slot.status == 'available' && slot.dateTime.isAfter(DateTime.now()))
              .toList();

          if (slots.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.calendar_today_outlined, size: 64, color: Color(0xFFCBD5E1)),
                    SizedBox(height: 16),
                    Text(
                      'No available time slots.',
                      style: TextStyle(color: Color(0xFF64748B), fontSize: 16, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Please contact the therapist directly to request them to open bookable slots.',
                      style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }

          return Form(
            key: _formKey,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '1. Choose an Available Slot:',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                  ),
                  const SizedBox(height: 10),
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: slots.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final slot = slots[index];
                      final isSelected = _selectedSlot?.id == slot.id;
                      final dt = slot.dateTime;
                      final dateStr = '${dt.day}/${dt.month}/${dt.year}';
                      final timeStr = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

                      return InkWell(
                        onTap: () {
                          setState(() {
                            _selectedSlot = (_selectedSlot?.id == slot.id) ? null : slot;
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          decoration: BoxDecoration(
                            color: isSelected ? const Color(0xFFE0F2FE) : Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected ? const Color(0xFF0284C7) : const Color(0xFFE2E8F0),
                              width: isSelected ? 2 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                isSelected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                                color: isSelected ? const Color(0xFF0284C7) : const Color(0xFF94A3B8),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '$dateStr at $timeStr',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14.5,
                                        color: isSelected ? const Color(0xFF0369A1) : const Color(0xFF1E293B),
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Duration: ${slot.durationMinutes} minutes',
                                      style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    '2. Session Notes (Optional):',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _notesCtrl,
                    maxLines: 4,
                    style: const TextStyle(fontSize: 14, color: Color(0xFF1E293B)),
                    decoration: InputDecoration(
                      hintText: 'e.g. Focus on verbal vocabulary exercises, child was hyperactive yesterday...',
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.all(14),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFF0D9488), width: 2),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0), width: 1),
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0D9488),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      onPressed: _selectedSlot == null || _submitting
                          ? null
                          : () async {
                              setState(() => _submitting = true);
                              try {
                                await AppRepositories.support.bookAppointmentSlot(
                                  slotId: _selectedSlot!.id,
                                  parentId: widget.parentId,
                                  childId: widget.childId,
                                  childName: widget.childName,
                                  notes: _notesCtrl.text.trim(),
                                  therapistId: widget.therapistId,
                                  parentName: FirebaseAuth.instance.currentUser?.displayName ?? '',
                                );
                                // Schedule a 30-minutes-before reminder notification
                                await NotificationService.instance.scheduleSessionReminder(
                                  notificationId: _selectedSlot!.id.hashCode.abs(),
                                  sessionTime: _selectedSlot!.dateTime,
                                  therapistName: widget.therapistName,
                                );
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text("Session booked! You'll get a reminder 30 minutes before."),
                                      backgroundColor: Color(0xFF059669),
                                    ),
                                  );
                                  Navigator.pop(context);
                                }
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Failed to book session: $e'),
                                      backgroundColor: const Color(0xFFEF4444),
                                    ),
                                  );
                                }
                              } finally {
                                if (mounted) {
                                  setState(() => _submitting = false);
                                }
                              }
                            },
                      child: _submitting
                          ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                          : const Text(
                              'Confirm Booking',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
