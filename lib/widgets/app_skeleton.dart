import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

/// A shimmer skeleton that mimics a list of conversation/therapist cards.
/// Used in the Professional Support screen while data loads.
class AppSkeletonLoader extends StatelessWidget {
  const AppSkeletonLoader({super.key, this.itemCount = 4});

  final int itemCount;

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: const Color(0xFFE8F5E9),
      highlightColor: const Color(0xFFF1FFF4),
      period: const Duration(milliseconds: 1200),
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 20),
        itemCount: itemCount,
        physics: const NeverScrollableScrollPhysics(),
        itemBuilder: (_, __) => const _ConversationCardSkeleton(),
      ),
    );
  }
}

class _ConversationCardSkeleton extends StatelessWidget {
  const _ConversationCardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(
              color: Color(0xFFD1D5DB),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 13,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD1D5DB),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  height: 11,
                  width: 160,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD1D5DB),
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            children: [
              Container(
                height: 10,
                width: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFFD1D5DB),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(height: 10),
              Container(
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  color: Color(0xFFD1D5DB),
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A shimmer skeleton that mimics a chat message list.
/// Used in the Therapist Chat screen while messages load.
class ChatSkeletonLoader extends StatelessWidget {
  const ChatSkeletonLoader({super.key, this.itemCount = 6});

  final int itemCount;

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: const Color(0xFFE8F5E9),
      highlightColor: const Color(0xFFF1FFF4),
      period: const Duration(milliseconds: 1200),
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        itemCount: itemCount,
        reverse: true,
        physics: const NeverScrollableScrollPhysics(),
        itemBuilder: (_, index) {
          final isSender = index.isEven;
          return _ChatBubbleSkeleton(isSender: isSender);
        },
      ),
    );
  }
}

class _ChatBubbleSkeleton extends StatelessWidget {
  const _ChatBubbleSkeleton({required this.isSender});

  final bool isSender;

  @override
  Widget build(BuildContext context) {
    final bubbleWidth = isSender ? 200.0 : 240.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment:
            isSender ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isSender) ...[
            Container(
              width: 30,
              height: 30,
              decoration: const BoxDecoration(
                color: Color(0xFFD1D5DB),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Container(
            width: bubbleWidth,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFFD1D5DB),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: isSender
                    ? const Radius.circular(16)
                    : const Radius.circular(4),
                bottomRight: isSender
                    ? const Radius.circular(4)
                    : const Radius.circular(16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A generic card-shaped shimmer block for reuse in any screen.
class CardSkeleton extends StatelessWidget {
  const CardSkeleton({
    super.key,
    this.height = 80,
    this.borderRadius = 14,
  });

  final double height;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: const Color(0xFFE8F5E9),
      highlightColor: const Color(0xFFF1FFF4),
      child: Container(
        height: height,
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(borderRadius),
        ),
      ),
    );
  }
}
