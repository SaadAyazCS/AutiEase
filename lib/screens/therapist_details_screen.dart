import 'package:flutter/material.dart';

import '../models/app_models.dart';
import '../utils/app_colors.dart';

class TherapistDetailsScreen extends StatelessWidget {
  const TherapistDetailsScreen({
    super.key,
    required this.therapist,
    this.onStartConversation,
  });

  final TherapistProfile therapist;
  final VoidCallback? onStartConversation;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Therapist Details'),
        backgroundColor: AppColors.primaryBlue,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  therapist.displayName,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1A2D4B),
                  ),
                ),
                const SizedBox(height: 10),
                if (therapist.bio.isNotEmpty) Text(therapist.bio),
                if (therapist.bio.isEmpty)
                  const Text('No bio available yet for this therapist.'),
                const SizedBox(height: 14),
                Text(
                  'Rating: ${therapist.rating.toStringAsFixed(1)}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 6),
                Text('Availability: ${therapist.availability}'),
                const SizedBox(height: 6),
                Text('Pricing: ${therapist.pricing}'),
                const SizedBox(height: 14),
                const Text(
                  'Specializations',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                if (therapist.specializations.isEmpty)
                  const Text('No specializations listed.')
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final specialization in therapist.specializations)
                        Chip(label: Text(specialization)),
                    ],
                  ),
                const SizedBox(height: 14),
                const Text(
                  'Languages',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  therapist.languages.isEmpty
                      ? 'Not specified'
                      : therapist.languages.join(', '),
                ),
              ],
            ),
          ),
          if (onStartConversation != null) ...[
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: onStartConversation,
              icon: const Icon(Icons.chat_bubble_outline),
              label: const Text('Start Conversation'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primaryBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

