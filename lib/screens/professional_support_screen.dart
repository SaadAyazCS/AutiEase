import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_runtime_config.dart';
import '../models/app_models.dart';
import '../repositories/app_repositories.dart';
import '../utils/app_colors.dart';
import '../widgets/figma_module_scaffold.dart';
import '../widgets/session_guard.dart';
import 'therapist_chat_screen.dart';

class ProfessionalSupportScreen extends StatefulWidget {
  const ProfessionalSupportScreen({super.key});

  @override
  State<ProfessionalSupportScreen> createState() =>
      _ProfessionalSupportScreenState();
}

class _ProfessionalSupportScreenState extends State<ProfessionalSupportScreen> {
  bool _isLaunchingCheckout = false;
  bool _isManagingSubscription = false;

  Future<void> _launchCheckout(SubscriptionProduct product) async {
    setState(() => _isLaunchingCheckout = true);
    try {
      final url = await AppRepositories.billing.createCheckoutSession(
        productId: product.id,
        successUrl: AppRuntimeConfig.stripeSuccessUrl,
        cancelUrl: AppRuntimeConfig.stripeCancelUrl,
      );
      if (url == null || url.isEmpty) {
        throw Exception('Checkout URL not returned');
      }
      if (url.startsWith('mock://')) {
        if (!mounted) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Mock subscription activated successfully.'),
            backgroundColor: Colors.green,
          ),
        );
        setState(() {});
        return;
      }
      final uri = Uri.parse(url);
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (mounted) {
        setState(() {});
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to start checkout: $error'),
          backgroundColor: AppColors.errorRed,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isLaunchingCheckout = false);
      }
    }
  }

  Future<void> _openTherapistChat(TherapistProfile therapist) async {
    try {
      final child = await AppRepositories.users
          .getActiveChildForCurrentParent();
      final subscription = await AppRepositories.billing
          .getCurrentSubscription();
      if (!mounted) {
        return;
      }
      if (child == null || subscription == null || !subscription.isActive) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'You need an active subscription and child profile before messaging a therapist.',
            ),
            backgroundColor: AppColors.errorRed,
          ),
        );
        return;
      }

      final thread = await AppRepositories.support.ensureThread(
        therapistId: therapist.id,
        childId: child.id,
        subscriptionId: subscription.id,
      );
      if (!mounted) {
        return;
      }
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TherapistChatScreen(
            thread: thread,
            participantName: therapist.displayName,
            senderRole: 'parent',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to open conversation: $error'),
          backgroundColor: AppColors.errorRed,
        ),
      );
    }
  }

  void _openExistingThread(TherapistThread thread, String therapistName) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TherapistChatScreen(
          thread: thread,
          participantName: therapistName,
          senderRole: 'parent',
        ),
      ),
    );
  }

  Future<void> _toggleSubscription(UserSubscription subscription) async {
    setState(() => _isManagingSubscription = true);
    try {
      if (subscription.cancelAtPeriodEnd) {
        await AppRepositories.billing.reactivateSubscription(subscription.id);
      } else {
        await AppRepositories.billing.cancelSubscription(subscription.id);
      }
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            subscription.cancelAtPeriodEnd
                ? 'Subscription reactivated'
                : 'Subscription will cancel at period end',
          ),
          backgroundColor: Colors.green,
        ),
      );
      setState(() {});
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to update subscription: $error'),
          backgroundColor: AppColors.errorRed,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isManagingSubscription = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SessionGuard(
      role: SessionGuardRole.parent,
      child: FigmaModuleScaffold(
        title: 'Professional Support',
        onBack: () => Navigator.pop(context),
        child: FutureBuilder<List<Object?>>(
          future: Future.wait([
            AppRepositories.billing.getCurrentSubscription(),
            AppRepositories.billing.listProducts(),
            AppRepositories.support.listTherapists(),
          ]),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            final subscription = snapshot.data?[0] as UserSubscription?;
            final products =
                snapshot.data?[1] as List<SubscriptionProduct>? ?? const [];
            final therapists =
                snapshot.data?[2] as List<TherapistProfile>? ?? const [];
            final therapistById = {
              for (final therapist in therapists) therapist.id: therapist,
            };
            final stripeBackendConfigured =
                AppRepositories.stripeBackend.isConfigured;

            return ListView(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 170),
              children: [
                _SupportInfoCard(
                  title: subscription?.isActive == true
                      ? 'Professional support unlocked'
                      : 'Subscription required',
                  body: subscription?.isActive == true
                      ? 'Your active subscription allows therapist discovery and in-app chat.'
                      : 'Pick a subscription plan from Firestore-backed products to unlock therapist conversations.',
                ),
                const SizedBox(height: 20),
                if (subscription != null && subscription.isActive)
                  _SubscriptionStatusCard(
                    subscription: subscription,
                    isBusy: _isManagingSubscription,
                    onToggle: () => _toggleSubscription(subscription),
                  ),
                if (subscription != null && subscription.isActive)
                  const SizedBox(height: 20),
                if (subscription == null || !subscription.isActive) ...[
                  if (!stripeBackendConfigured)
                    const _SupportInfoCard(
                      title: 'Payments backend not configured',
                      body:
                          'Set STRIPE_BACKEND_BASE_URL via --dart-define to enable checkout in this build.',
                    ),
                  if (!stripeBackendConfigured) const SizedBox(height: 12),
                  for (final product in products)
                    _ProductCard(
                      product: product,
                      isBusy: _isLaunchingCheckout,
                      onCheckout: stripeBackendConfigured
                          ? () => _launchCheckout(product)
                          : null,
                    ),
                  if (products.isEmpty)
                    const _SupportInfoCard(
                      title: 'No products configured',
                      body:
                          'The subscription_products collection is empty. Seed Firestore to activate billing.',
                    ),
                  const SizedBox(height: 20),
                ],
                if (subscription?.isActive == true) ...[
                  const Text(
                    'Active Conversations',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  StreamBuilder<List<TherapistThread>>(
                    stream: AppRepositories.support.watchThreadsForRole(
                      'parent',
                    ),
                    builder: (context, threadsSnapshot) {
                      final threads = threadsSnapshot.data ?? const [];
                      if (threadsSnapshot.connectionState ==
                              ConnectionState.waiting &&
                          threads.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      if (threads.isEmpty) {
                        return const _SupportInfoCard(
                          title: 'No active conversations',
                          body:
                              'Start by messaging a therapist below. Your conversations will appear here.',
                        );
                      }
                      return Column(
                        children: [
                          for (final thread in threads)
                            _ConversationCard(
                              therapistName:
                                  thread.therapistDisplayName.isNotEmpty
                                  ? thread.therapistDisplayName
                                  : therapistById[thread.therapistId]
                                            ?.displayName ??
                                        'Therapist',
                              lastMessage: thread.lastMessagePreview,
                              status: thread.status,
                              onOpen: () => _openExistingThread(
                                thread,
                                thread.therapistDisplayName.isNotEmpty
                                    ? thread.therapistDisplayName
                                    : therapistById[thread.therapistId]
                                              ?.displayName ??
                                          'Therapist',
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                ],
                const Text(
                  'Therapists',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                if (therapists.isEmpty)
                  const _SupportInfoCard(
                    title: 'No therapists available',
                    body:
                        'Seed therapist_profiles in Firestore to browse therapists here.',
                  ),
                for (final therapist in therapists)
                  _TherapistCard(
                    therapist: therapist,
                    isLocked: subscription?.isActive != true,
                    onMessage: () => _openTherapistChat(therapist),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _SupportInfoCard extends StatelessWidget {
  const _SupportInfoCard({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(body, style: const TextStyle(height: 1.5)),
        ],
      ),
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({
    required this.product,
    required this.onCheckout,
    required this.isBusy,
  });

  final SubscriptionProduct product;
  final VoidCallback? onCheckout;
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            product.title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(product.subtitle),
          const SizedBox(height: 12),
          Text(
            product.priceLabel,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: AppColors.primaryBlue,
            ),
          ),
          const SizedBox(height: 12),
          for (final feature in product.featureList)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, size: 16, color: Colors.green),
                  const SizedBox(width: 8),
                  Expanded(child: Text(feature)),
                ],
              ),
            ),
          const SizedBox(height: 14),
          ElevatedButton(
            onPressed: isBusy ? null : onCheckout,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryBlue,
              foregroundColor: Colors.white,
            ),
            child: isBusy
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Start subscription'),
          ),
        ],
      ),
    );
  }
}

class _ConversationCard extends StatelessWidget {
  const _ConversationCard({
    required this.therapistName,
    required this.lastMessage,
    required this.status,
    required this.onOpen,
  });

  final String therapistName;
  final String lastMessage;
  final String status;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  therapistName,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                status,
                style: const TextStyle(
                  color: AppColors.primaryBlue,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            lastMessage.isEmpty ? 'No messages yet.' : lastMessage,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Colors.grey.shade700),
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: onOpen,
            icon: const Icon(Icons.chat_bubble_outline),
            label: const Text('Open chat'),
          ),
        ],
      ),
    );
  }
}

class _TherapistCard extends StatelessWidget {
  const _TherapistCard({
    required this.therapist,
    required this.isLocked,
    required this.onMessage,
  });

  final TherapistProfile therapist;
  final bool isLocked;
  final VoidCallback onMessage;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            therapist.displayName,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(therapist.bio.isEmpty ? 'No bio added yet.' : therapist.bio),
          const SizedBox(height: 10),
          Text('Specializations: ${therapist.specializations.join(', ')}'),
          const SizedBox(height: 6),
          Text('Pricing: ${therapist.pricing}'),
          const SizedBox(height: 6),
          Text('Availability: ${therapist.availability}'),
          const SizedBox(height: 12),
          ElevatedButton.icon(
            onPressed: isLocked ? null : onMessage,
            icon: Icon(
              isLocked ? Icons.lock_outline : Icons.chat_bubble_outline,
            ),
            label: Text(
              isLocked ? 'Subscription required' : 'Message therapist',
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: isLocked
                  ? Colors.grey.shade400
                  : AppColors.primaryBlue,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _SubscriptionStatusCard extends StatelessWidget {
  const _SubscriptionStatusCard({
    required this.subscription,
    required this.isBusy,
    required this.onToggle,
  });

  final UserSubscription subscription;
  final bool isBusy;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Subscription status',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text('Status: ${subscription.status}'),
          const SizedBox(height: 4),
          Text(
            subscription.currentPeriodEnd == null
                ? 'Billing period end not synced yet'
                : 'Current period ends: ${subscription.currentPeriodEnd}',
          ),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: isBusy ? null : onToggle,
            style: ElevatedButton.styleFrom(
              backgroundColor: subscription.cancelAtPeriodEnd
                  ? Colors.green
                  : AppColors.errorRed,
              foregroundColor: Colors.white,
            ),
            child: isBusy
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    subscription.cancelAtPeriodEnd
                        ? 'Reactivate subscription'
                        : 'Cancel at period end',
                  ),
          ),
        ],
      ),
    );
  }
}
