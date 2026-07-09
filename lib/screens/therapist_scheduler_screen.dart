import 'package:flutter/material.dart';
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

  Future<void> _selectAndAddSlot() async {
    final now = DateTime.now();
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 90)),
    );
    if (pickedDate == null) return;

    if (!mounted) return;
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 9, minute: 0),
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

    setState(() => _submitting = true);
    try {
      await AppRepositories.support.createAppointmentSlot(
        therapistId: widget.therapistId,
        dateTime: dateTime,
        durationMinutes: 60, // default 1 hour
      );
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Manage Appointments'),
        backgroundColor: const Color(0xFF0D9488),
        foregroundColor: Colors.white,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _submitting ? null : _selectAndAddSlot,
        backgroundColor: const Color(0xFF0D9488),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Add Time Slot'),
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
              final timeStr = '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
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
                                  '$dateStr at $timeStr',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF1E293B)),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'Duration: ${slot.durationMinutes} minutes',
                                  style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                                ),
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
      ),
    );
  }
}
