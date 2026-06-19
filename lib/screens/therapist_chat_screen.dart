import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:printing/printing.dart';

import '../models/app_models.dart';
import '../repositories/app_repositories.dart';
import '../utils/app_colors.dart';
import '../widgets/session_guard.dart';
import 'professional_support_screen.dart';

class _TherapistPlaceholderAvatar extends StatelessWidget {
  const _TherapistPlaceholderAvatar({
    required this.size,
    this.photoUrlBase64,
  });

  final double size;
  final String? photoUrlBase64;

  @override
  Widget build(BuildContext context) {
    Widget imageWidget;
    final cleanPhoto = photoUrlBase64?.trim() ?? '';
    if (cleanPhoto.isNotEmpty) {
      if (cleanPhoto.startsWith('http://') || cleanPhoto.startsWith('https://')) {
        imageWidget = Image.network(
          cleanPhoto,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return Image.asset('assets/images/autiease.png', fit: BoxFit.contain);
          },
        );
      } else {
        try {
          final imageBytes = base64Decode(cleanPhoto);
          imageWidget = Image.memory(
            imageBytes,
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) {
              return Image.asset('assets/images/autiease.png', fit: BoxFit.contain);
            },
          );
        } catch (e) {
          imageWidget = Image.asset('assets/images/autiease.png', fit: BoxFit.contain);
        }
      }
    } else {
      imageWidget = Image.asset('assets/images/autiease.png', fit: BoxFit.contain);
    }

    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: Color(0xFFDDF7E5),
        shape: BoxShape.circle,
      ),
      padding: const EdgeInsets.all(2),
      child: ClipOval(
        child: imageWidget,
      ),
    );
  }
}

class TherapistChatScreen extends StatefulWidget {
  const TherapistChatScreen({
    super.key,
    required this.thread,
    required this.participantName,
    required this.senderRole,
    this.readOnly = false,
    this.therapistProfile,
  });

  final TherapistThread thread;
  final String participantName;
  final String senderRole;
  final bool readOnly;
  final TherapistProfile? therapistProfile;

  @override
  State<TherapistChatScreen> createState() => _TherapistChatScreenState();
}

enum _MessageSendState { idle, sending, sent, error }

class _TherapistChatScreenState extends State<TherapistChatScreen> with WidgetsBindingObserver {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  _MessageSendState _sendState = _MessageSendState.idle;
  Timer? _resolvedBannerTimer;
  DateTime? _lastResolvedAtSeen;
  bool _showResolvedBanner = false;

  // Rate Limiting (max 5 messages per 10 seconds)
  final List<DateTime> _messageTimestamps = [];

  // Blocking status
  bool _isBlocked = false;

  // Emojis panel state
  bool _showEmojiPicker = false;
  static const List<String> _commonEmojis = [
    '😀', '😂', '😍', '👍', '🙏', '❤️', '🎉', '🌟', '👏', '😭', '😡', '😱', '🤔', '🔥', '👀', '✨'
  ];

  // Attachment state
  String? _attachmentBase64;
  String? _attachmentFileName;
  String? _attachmentType; // 'image', 'file'

  // Loaded peer profiles for visual headers
  UserProfile? _peerUserProfile;
  TherapistProfile? _peerTherapistProfile;
  TherapistThread? _lastSeenThread;

  String? _activeCheckoutTherapistId;
  bool _isCheckoutCancelled = false;
  bool _isPaymentFailed = false;
  bool _isCheckoutUrlLaunched = false;
  bool _isProgrammaticPop = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _peerTherapistProfile = widget.therapistProfile;
    _checkBlockedStatus();
    _loadPeerProfile();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    _scrollController.dispose();
    _resolvedBannerTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _activeCheckoutTherapistId != null && _isCheckoutUrlLaunched) {
      final therapistId = _activeCheckoutTherapistId!;
      Future.delayed(const Duration(milliseconds: 800), () async {
        if (_activeCheckoutTherapistId == therapistId && !_isCheckoutCancelled) {
          try {
            await AppRepositories.billing.syncSubscriptionStatus(therapistId);
          } catch (e) {
            debugPrint('Error syncing checkout status on resume: $e');
          }
          // After user returns from browser, check the current subscription status.
          // 'payment_failed' means SafePay redirected to failure URL — treat as terminal
          // so the polling loop exits immediately and shows the error snackbar fast.
          // 'pending' is NOT terminal — user may still be in the browser.
          final sub = await AppRepositories.billing.getSubscriptionForTherapist(therapistId);
          final status = sub?.status.trim().toLowerCase() ?? '';
          final isPaymentFailed = status == 'payment_failed';
          final isTerminalFailure = const ['canceled', 'expired', 'payment_failed'].contains(status);
          if (isTerminalFailure) {
            if (mounted) {
              setState(() {
                _isPaymentFailed = isPaymentFailed;
                _isCheckoutCancelled = true;
              });
            }
          }
        }
      });
    }
  }


  Future<void> _checkBlockedStatus() async {
    final peerId = widget.senderRole == 'parent' ? widget.thread.therapistId : widget.thread.parentId;
    final blocked = await AppRepositories.support.isUserBlocked(peerId);
    if (mounted) {
      setState(() {
        _isBlocked = blocked;
      });
    }
  }

  Future<void> _loadPeerProfile() async {
    final peerId = widget.senderRole == 'parent' ? widget.thread.therapistId : widget.thread.parentId;
    try {
      final userDoc = await FirebaseFirestore.instance.collection(FirestoreCollections.users).doc(peerId).get();
      if (userDoc.exists && userDoc.data() != null) {
        if (mounted) {
          setState(() {
            _peerUserProfile = UserProfile.fromMap(userDoc.id, userDoc.data()!);
          });
        }
      }
      if (widget.senderRole == 'parent') {
        final tProfile = await AppRepositories.support.getTherapistById(peerId);
        if (tProfile != null && mounted) {
          setState(() {
            _peerTherapistProfile = tProfile;
          });
        }
      }
    } catch (_) {}
  }

  void _syncResolvedBanner(TherapistThread thread) {
    final respondedAt = thread.emergencyRespondedAt;
    if (!thread.emergencyResponded || respondedAt == null) {
      _resolvedBannerTimer?.cancel();
      _resolvedBannerTimer = null;
      _lastResolvedAtSeen = null;
      if (_showResolvedBanner) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            setState(() => _showResolvedBanner = false);
          }
        });
      }
      return;
    }

    final isSameEvent = _lastResolvedAtSeen == respondedAt;
    if (isSameEvent) {
      return;
    }

    _lastResolvedAtSeen = respondedAt;
    _resolvedBannerTimer?.cancel();

    if (!_showResolvedBanner) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _showResolvedBanner = true);
        }
      });
    }

    _resolvedBannerTimer = Timer(const Duration(minutes: 1), () {
      if (mounted) {
        setState(() => _showResolvedBanner = false);
      }
    });
  }

  bool _canSendMessage(TherapistThread thread) {
    if (widget.readOnly || _isBlocked) {
      return false;
    }
    if (widget.senderRole == 'parent') {
      return thread.status == 'active' && thread.postCancelVisible;
    }
    return true;
  }

  bool _checkRateLimit() {
    final now = DateTime.now();
    _messageTimestamps.removeWhere((t) => now.difference(t).inSeconds > 10);
    if (_messageTimestamps.length >= 5) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Rate limit reached. Please wait a few seconds.'),
          backgroundColor: AppColors.errorRed,
        ),
      );
      return false;
    }
    _messageTimestamps.add(now);
    return true;
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty && _attachmentBase64 == null) {
      return;
    }
    if (_sendState == _MessageSendState.sending) {
      return;
    }
    if (!_checkRateLimit()) {
      return;
    }

    setState(() {
      _sendState = _MessageSendState.sending;
    });

    try {
      final bodyToSend = text.isNotEmpty 
          ? text 
          : (_attachmentType == 'image' ? 'Sent an image' : 'Sent a file');
      final attachmentPayload = _attachmentBase64 != null ? [_attachmentBase64!] : const <String>[];
      final messageType = _attachmentType ?? 'text';

      _controller.clear();
      final tempAttachmentType = _attachmentType;

      setState(() {
        _attachmentBase64 = null;
        _attachmentFileName = null;
        _attachmentType = null;
        _showEmojiPicker = false;
      });

      await AppRepositories.support.sendMessage(
        threadId: widget.thread.id,
        senderRole: widget.senderRole,
        body: bodyToSend,
        attachments: attachmentPayload,
        messageType: messageType,
      );

      // Trigger standard push mirror logic
      final peerId = widget.senderRole == 'parent' ? widget.thread.therapistId : widget.thread.parentId;
      final senderName = widget.senderRole == 'parent' 
          ? (_peerUserProfile?.fullName ?? 'Parent') 
          : (widget.therapistProfile?.displayName ?? 'Therapist');
      
      await AppRepositories.support.sendNotification(
        userId: peerId,
        title: 'New message from $senderName',
        message: tempAttachmentType != null ? 'Attachment shared' : bodyToSend,
        category: 'messages',
        navigationTarget: {
          'route': 'chat',
          'threadId': widget.thread.id,
        },
      );

      if (!mounted) return;
      setState(() => _sendState = _MessageSendState.sent);
      _scrollToBottom();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _sendState = _MessageSendState.error;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to send message: $error'),
          backgroundColor: AppColors.errorRed,
        ),
      );
    } finally {
      if (mounted) {
        if (_sendState == _MessageSendState.sent) {
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted) {
              setState(() => _sendState = _MessageSendState.idle);
            }
          });
        }
      }
    }
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent + 80,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _pickImage() async {
    try {
      final picker = ImagePicker();
      final image = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
      if (image != null) {
        final bytes = await image.readAsBytes();
        setState(() {
          _attachmentBase64 = base64Encode(bytes);
          _attachmentFileName = image.name;
          _attachmentType = 'image';
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to pick image: $e')),
      );
    }
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'doc', 'docx', 'txt'],
        withData: true,
      );
      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        if (file.bytes != null) {
          setState(() {
            _attachmentBase64 = base64Encode(file.bytes!);
            _attachmentFileName = file.name;
            _attachmentType = 'file';
          });
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to pick file: $e')),
      );
    }
  }

  void _insertEmoji(String emoji) {
    final text = _controller.text;
    final selection = _controller.selection;
    if (selection.start >= 0) {
      final newText = text.replaceRange(selection.start, selection.end, emoji);
      _controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: selection.start + emoji.length),
      );
    } else {
      _controller.text = text + emoji;
    }
  }

  Future<void> _toggleBlockStatus() async {
    final peerId = widget.senderRole == 'parent' ? widget.thread.therapistId : widget.thread.parentId;
    try {
      if (_isBlocked) {
        await AppRepositories.support.unblockUser(blockedId: peerId);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('User unblocked.')),
        );
      } else {
        await AppRepositories.support.blockUser(blockedId: peerId);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('User blocked.')),
        );
      }
      await _checkBlockedStatus();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Action failed: $e')),
      );
    }
  }

  Future<void> _openReportFlow() async {
    final reasons = ['Harassment', 'Inappropriate Behavior', 'Spam', 'Fake Information', 'Other'];
    String selectedReason = reasons.first;
    final commentsController = TextEditingController();
    bool showExplanation = false;

    final shouldReport = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Report User', style: TextStyle(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Help us understand what happened. Select a reason below:', style: TextStyle(fontSize: 14)),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: selectedReason,
                  items: reasons.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() {
                        selectedReason = value;
                        showExplanation = value == 'Other';
                      });
                    }
                  },
                  decoration: const InputDecoration(border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 10)),
                ),
                if (showExplanation) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: commentsController,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Explanation',
                      hintText: 'Please detail the violation...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.errorRed, foregroundColor: Colors.white),
              child: const Text('Report'),
            ),
          ],
        ),
      ),
    );

    if (shouldReport == true) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Confirm Report'),
          content: const Text('Are you sure you want to submit this report? Admin team will review the conversation logs.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text('Confirm')),
          ],
        ),
      );

      if (confirm == true) {
        try {
          final peerId = widget.senderRole == 'parent' ? widget.thread.therapistId : widget.thread.parentId;
          final messagesSnapshot = await FirebaseFirestore.instance
              .collection(FirestoreCollections.therapistThreads)
              .doc(widget.thread.id)
              .collection('messages')
              .orderBy('sentAt', descending: true)
              .limit(15)
              .get();
          
          final contextList = messagesSnapshot.docs
              .map((d) => {
                    'senderId': d.data()['senderId'] ?? '',
                    'senderRole': d.data()['senderRole'] ?? '',
                    'body': d.data()['body'] ?? '',
                    'sentAt': d.data()['sentAt']?.toString() ?? '',
                  })
              .toList();

          await AppRepositories.support.submitReport(
            reportedId: peerId,
            reason: selectedReason,
            comments: selectedReason == 'Other' ? commentsController.text : 'Selected reason: $selectedReason',
            chatContext: contextList,
          );

          if (!mounted) return;
          showDialog<void>(
            // ignore: use_build_context_synchronously
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Report Submitted'),
              content: const Text('Thank you. We have received your report and will take action if any violations are found.'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
              ],
            ),
          );
        } catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to submit report: $e')),
          );
        }
      }
    }
  }

  void _openPeerProfileDetails() {
    final isTherapist = widget.senderRole == 'parent';
    final photoUrlBase64 = isTherapist
        ? (_peerTherapistProfile?.photoUrlBase64.isNotEmpty == true 
            ? _peerTherapistProfile?.photoUrlBase64 
            : (_peerTherapistProfile?.photoUrl.isNotEmpty == true
                ? _peerTherapistProfile?.photoUrl
                : _peerUserProfile?.photoUrl))
        : _peerUserProfile?.photoUrl;

    if (isTherapist) {
      if (_peerTherapistProfile == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Loading therapist details... Please try again.')),
        );
        return;
      }
      final initiallySubscribed = (_lastSeenThread?.status == 'active') || (widget.thread.status == 'active');
      Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (routeContext) => SupportTherapistDetailsScreen(
            therapist: _peerTherapistProfile!,
            initiallySubscribed: initiallySubscribed,
            chatEnabled: true,
            paymentsEnabled: true,
            onSubscribe: (packageIndex) => AppRepositories.billing.purchaseTherapistSubscription(
              _peerTherapistProfile!.id,
              packageIndex: packageIndex,
            ),
            onCancelSubscription: () async {
              final result = await _showCancelSubscriptionFlow(routeContext);
              return result;
            },
            onOpenMessages: () async {
              Navigator.pop(routeContext);
            },
          ),
        ),
      );
    } else {
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) {
          return Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 34),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                const SizedBox(height: 20),
                _TherapistPlaceholderAvatar(size: 88, photoUrlBase64: photoUrlBase64),
                const SizedBox(height: 14),
                Text(
                  widget.participantName,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                ),
                const Text(
                  'Verified Parent Member',
                  style: TextStyle(fontSize: 14, color: Color(0xFF00A63E), fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 10),
                _buildProfileDetailRow('Role', 'Parent'),
                _buildProfileDetailRow('Verification Status', 'Verified account'),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryBlue,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(double.infinity, 44),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Close Profile'),
                ),
              ],
            ),
          );
        },
      );
    }
  }

  Future<bool> _showCancelSubscriptionFlow(BuildContext dialogContext) async {
    final confirm = await showDialog<bool>(
      context: dialogContext,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return CancelSubscriptionDialog(
          therapistName: widget.participantName,
          onConfirmCancel: () {
            Navigator.pop(dialogCtx, true);
          },
        );
      },
    );

    if (confirm == true) {
      if (!dialogContext.mounted) return false;
      final choice = await _showChatHistoryChoicesDialog(dialogContext);
      if (choice != null) {
        if (dialogContext.mounted) {
          Navigator.pop(dialogContext); // Close details screen
        }
        if (context.mounted) {
          final messenger = ScaffoldMessenger.of(context);
          if (choice == 'delete') {
            Navigator.pop(context); // Close chat screen itself
            messenger.showSnackBar(
              const SnackBar(
                content: Text('Subscription cancelled and chat history deleted.'),
                backgroundColor: Color(0xFFEF4444),
              ),
            );
          } else {
            messenger.showSnackBar(
              const SnackBar(
                content: Text('Subscription cancelled. Chat locked to read-only.'),
                backgroundColor: Color(0xFF3B82F6),
              ),
            );
          }
        }
        return true;
      }
    }
    return false;
  }

  Future<String?> _showChatHistoryChoicesDialog(BuildContext parentCtx) async {
    return showDialog<String>(
      context: parentCtx,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return ChatHistoryChoicesDialog(
          threadId: widget.thread.id,
          therapistId: widget.thread.therapistId,
          onComplete: (choice) {
            // Handled inside choices dialog State
          },
        );
      },
    );
  }

  Widget _buildProfileDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(label, style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF64748B))),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(color: Color(0xFF1E293B))),
          ),
        ],
      ),
    );
  }

  Future<void> _requestEmergency() async {
    try {
      await AppRepositories.support.requestEmergency(
        threadId: widget.thread.id,
        requestedByRole: widget.senderRole,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Emergency request sent to therapist.'),
          backgroundColor: AppColors.errorRed,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to request emergency support: $error'),
          backgroundColor: AppColors.errorRed,
        ),
      );
    }
  }

  Future<void> _resolveEmergency() async {
    try {
      await AppRepositories.support.resolveEmergency(
        threadId: widget.thread.id,
        resolvedByRole: widget.senderRole,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Emergency response sent.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to respond to emergency: $error'),
          backgroundColor: AppColors.errorRed,
        ),
      );
    }
  }

  Future<void> _endEmergency() async {
    await _resolveEmergency();
  }






  String _formatTime(DateTime? value) {
    if (value == null) {
      return '';
    }
    final local = value.toLocal();
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final suffix = local.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $suffix';
  }

  @override
  Widget build(BuildContext context) {
    final peerRole = widget.senderRole == 'parent' ? 'Therapist' : 'Parent';
    final photoUrlBase64 = widget.senderRole == 'parent' 
        ? (_peerTherapistProfile?.photoUrlBase64.isNotEmpty == true 
            ? _peerTherapistProfile?.photoUrlBase64 
            : (_peerTherapistProfile?.photoUrl.isNotEmpty == true
                ? _peerTherapistProfile?.photoUrl
                : _peerUserProfile?.photoUrl))
        : _peerUserProfile?.photoUrl;

    return SessionGuard(
      role: SessionGuardRole.authenticated,
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          backgroundColor: AppColors.primaryBlue,
          foregroundColor: Colors.white,
          leadingWidth: 40,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context),
          ),
          titleSpacing: 0,
          title: InkWell(
            onTap: _openPeerProfileDetails,
            child: Row(
              children: [
                _TherapistPlaceholderAvatar(size: 38, photoUrlBase64: photoUrlBase64),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.participantName,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        peerRole,
                        style: const TextStyle(fontSize: 11, color: Colors.white70),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: Colors.white),
              onSelected: (value) {
                if (value == 'profile') {
                  _openPeerProfileDetails();
                } else if (value == 'report') {
                  _openReportFlow();
                } else if (value == 'block') {
                  _toggleBlockStatus();
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'profile',
                  child: Row(
                    children: [
                      Icon(Icons.person_outline, size: 20, color: Colors.black87),
                      SizedBox(width: 8),
                      Text('View Profile'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'report',
                  child: Row(
                    children: [
                      Icon(Icons.report_outlined, size: 20, color: AppColors.errorRed),
                      SizedBox(width: 8),
                      Text('Report User', style: TextStyle(color: AppColors.errorRed)),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'block',
                  child: Row(
                    children: [
                      Icon(_isBlocked ? Icons.lock_open : Icons.block, size: 20, color: Colors.black87),
                      SizedBox(width: 8),
                      Text(_isBlocked ? 'Unblock User' : 'Block User'),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
        body: StreamBuilder<TherapistThread?>(
          stream: AppRepositories.support.watchThread(widget.thread.id),
          builder: (context, threadSnapshot) {
            final thread = threadSnapshot.data ?? widget.thread;
            _lastSeenThread = thread;
            _syncResolvedBanner(thread);
            final canSendMessage = _canSendMessage(thread);
            return LayoutBuilder(
              builder: (context, constraints) {
                final composerMaxHeight = (constraints.maxHeight * 0.45)
                    .clamp(120.0, 260.0)
                    .toDouble();
                return Column(
                  children: [
                    if (widget.readOnly)
                      const _ChatStateBanner(
                        text: 'Read-only mode: this conversation remains visible, but new parent messages require an active subscription.',
                        color: Color(0xFFF2E8C6),
                      ),
                    if (thread.hasOpenEmergency)
                      _ChatStateBanner(
                        text: thread.emergencyRequestedBy == 'parent'
                            ? 'Emergency requested by parent.'
                            : 'Emergency requested by therapist.',
                        color: const Color(0xFFFFD9D9),
                      )
                    else if (_showResolvedBanner)
                      const _ChatStateBanner(
                        text: 'Emergency response has been recorded.',
                        color: Color(0xFFD8F4DD),
                      ),
                    if (_isBlocked)
                      const _ChatStateBanner(
                        text: 'This conversation is disabled because a user is blocked.',
                        color: Color(0xFFFEE2E2),
                      ),
                    Expanded(
                      child: StreamBuilder<List<TherapistMessage>>(
                        stream: AppRepositories.support.watchMessages(
                          widget.thread.id,
                        ),
                        builder: (context, snapshot) {
                          final messages = snapshot.data ?? const [];
                          if (snapshot.connectionState ==
                                  ConnectionState.waiting &&
                              messages.isEmpty) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }
                          if (messages.isEmpty) {
                            return const Center(
                              child: Padding(
                                padding: EdgeInsets.all(24),
                                child: Text(
                                  'No messages yet. Start the conversation to get professional support.',
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            );
                          }

                          // Trigger scroll to bottom on new messages
                          WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

                          return ListView.builder(
                            controller: _scrollController,
                            keyboardDismissBehavior:
                                ScrollViewKeyboardDismissBehavior.onDrag,
                            padding: const EdgeInsets.all(16),
                            itemCount: messages.length,
                            itemBuilder: (context, index) {
                              final message = messages[index];
                              if (message.messageType == 'system') {
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: Center(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFE9EEF6),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        message.body,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Color(0xFF334A6E),
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              }
                              final isMine =
                                  message.senderRole == widget.senderRole;
                                  
                              Widget contentWidget;
                              if (message.messageType == 'image' && message.attachments.isNotEmpty) {
                                Widget img;
                                try {
                                  final bytes = base64Decode(message.attachments.first);
                                  img = Image.memory(
                                    bytes,
                                    fit: BoxFit.cover,
                                    width: 200,
                                    height: 200,
                                    errorBuilder: (context, e, s) => const Icon(Icons.broken_image, size: 50),
                                  );
                                } catch (_) {
                                  img = const Icon(Icons.broken_image, size: 50);
                                }
                                contentWidget = Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: img,
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      message.body,
                                      style: TextStyle(
                                        color: isMine ? Colors.white : Colors.black87,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                );
                              } else if (message.messageType == 'file' && message.attachments.isNotEmpty) {
                                contentWidget = InkWell(
                                  onTap: () {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Opening file...')),
                                    );
                                  },
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.insert_drive_file, color: isMine ? Colors.white : AppColors.primaryBlue),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          message.body,
                                          style: TextStyle(
                                            color: isMine ? Colors.white : Colors.black87,
                                            fontWeight: FontWeight.w600,
                                            decoration: TextDecoration.underline,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              } else if (message.messageType == 'report' && message.attachments.isNotEmpty) {
                                contentWidget = Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      message.body,
                                      style: TextStyle(
                                        color: isMine ? Colors.white : Colors.black87,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 15,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    ElevatedButton.icon(
                                      onPressed: () {
                                        try {
                                          final bytes = base64Decode(message.attachments.first);
                                          Printing.sharePdf(bytes: bytes, filename: 'AutiEase_Report.pdf');
                                        } catch (e) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(content: Text('Could not open PDF: $e')),
                                          );
                                        }
                                      },
                                      icon: const Icon(Icons.picture_as_pdf, color: Colors.white),
                                      label: const Text('Open PDF Report', style: TextStyle(color: Colors.white)),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: isMine ? Colors.white.withValues(alpha: 0.25) : AppColors.primaryBlue,
                                        elevation: 0,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              } else {
                                contentWidget = Text(
                                  message.body,
                                  style: TextStyle(
                                    color: isMine ? Colors.white : Colors.black87,
                                    fontSize: 15,
                                  ),
                                );
                              }
                                  
                              return Align(
                                alignment: isMine
                                    ? Alignment.centerRight
                                    : Alignment.centerLeft,
                                child: Column(
                                  crossAxisAlignment: isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      margin: const EdgeInsets.only(bottom: 2),
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                      constraints: BoxConstraints(
                                        maxWidth:
                                            MediaQuery.of(context).size.width *
                                            0.75,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isMine
                                            ? AppColors.primaryBlue
                                            : const Color(0xFFF1F5F9),
                                        borderRadius: BorderRadius.only(
                                          topLeft: const Radius.circular(16),
                                          topRight: const Radius.circular(16),
                                          bottomLeft: Radius.circular(isMine ? 16 : 0),
                                          bottomRight: Radius.circular(isMine ? 0 : 16),
                                        ),
                                      ),
                                      child: contentWidget,
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.fromLTRB(6, 0, 6, 12),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            _formatTime(message.sentAt),
                                            style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8)),
                                          ),
                                          if (isMine) ...[
                                            const SizedBox(width: 4),
                                            const Icon(Icons.done_all, size: 12, color: Colors.blueAccent),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                    if (_attachmentFileName != null)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        color: const Color(0xFFF8FAFC),
                        child: Row(
                          children: [
                            Icon(
                              _attachmentType == 'image' ? Icons.image : Icons.insert_drive_file,
                              color: AppColors.primaryBlue,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _attachmentFileName!,
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF334155)),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.cancel, color: Colors.red),
                              onPressed: () {
                                setState(() {
                                  _attachmentBase64 = null;
                                  _attachmentFileName = null;
                                  _attachmentType = null;
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                    if (_showEmojiPicker)
                      Container(
                        height: 50,
                        color: const Color(0xFFF1F5F9),
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          itemCount: _commonEmojis.length,
                          itemBuilder: (context, index) {
                            return IconButton(
                              icon: Text(_commonEmojis[index], style: const TextStyle(fontSize: 20)),
                              onPressed: () => _insertEmoji(_commonEmojis[index]),
                            );
                          },
                        ),
                      ),
                    SafeArea(
                      top: false,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: composerMaxHeight,
                        ),
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (widget.senderRole == 'parent' &&
                                  !thread.hasOpenEmergency &&
                                  canSendMessage)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: OutlinedButton.icon(
                                    onPressed: _requestEmergency,
                                    icon: const Icon(
                                      Icons.warning_amber_rounded,
                                      color: AppColors.errorRed,
                                    ),
                                    label: const Text(
                                      'Request emergency support',
                                    ),
                                  ),
                                ),
                              if (thread.hasOpenEmergency)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: ElevatedButton.icon(
                                    onPressed: _endEmergency,
                                    icon: const Icon(
                                      Icons.health_and_safety_outlined,
                                    ),
                                    label: const Text('End emergency'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.green,
                                      foregroundColor: Colors.white,
                                    ),
                                  ),
                                ),
                              if (!canSendMessage)
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFFFBEB),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: const Color(0xFFFDE68A), width: 1.5),
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        _isBlocked 
                                            ? 'This conversation is disabled because a user is blocked.'
                                            : 'This chat is read-only because the subscription was cancelled.',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: _isBlocked ? const Color(0xFF991B1B) : const Color(0xFF92400E),
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                      if (!_isBlocked && widget.senderRole == 'parent') ...[
                                        const SizedBox(height: 12),
                                        ElevatedButton(
                                          onPressed: () async {
                                            _activeCheckoutTherapistId = widget.thread.therapistId;
                                            _isCheckoutCancelled = false;
                                            _isPaymentFailed = false;
                                            _isCheckoutUrlLaunched = false;
                                            _isProgrammaticPop = false;
                                            bool isDialogOpen = false;
                                            BuildContext? dialogContext;

                                            if (mounted) {
                                              isDialogOpen = true;
                                              showDialog<void>(
                                                context: context,
                                                barrierDismissible: true,
                                                builder: (BuildContext dialogCtx) {
                                                  dialogContext = dialogCtx;
                                                  return PopScope(
                                                    canPop: true,
                                                    onPopInvokedWithResult: (didPop, _) {
                                                      if (didPop && !_isProgrammaticPop) {
                                                        isDialogOpen = false;
                                                        setState(() {
                                                          _isCheckoutCancelled = true;
                                                        });
                                                      }
                                                    },
                                                    child: AlertDialog(
                                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                                      contentPadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
                                                      content: const Column(
                                                        mainAxisSize: MainAxisSize.min,
                                                        children: [
                                                          CircularProgressIndicator(color: Color(0xFF00C853)),
                                                          SizedBox(height: 16),
                                                          Text(
                                                            'Checkout opened in browser',
                                                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                                            textAlign: TextAlign.center,
                                                          ),
                                                          SizedBox(height: 6),
                                                          Text(
                                                            'Complete your payment in the browser. This screen will update automatically when payment is confirmed.',
                                                            style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                                                            textAlign: TextAlign.center,
                                                          ),
                                                        ],
                                                      ),
                                                      actions: [
                                                        TextButton(
                                                          onPressed: () {
                                                            isDialogOpen = false;
                                                            setState(() {
                                                              _isCheckoutCancelled = true;
                                                            });
                                                            if (dialogContext != null) {
                                                              Navigator.pop(dialogContext!);
                                                            }
                                                          },
                                                          style: TextButton.styleFrom(foregroundColor: AppColors.errorRed),
                                                          child: const Text('Cancel Payment'),
                                                        ),
                                                      ],
                                                    ),
                                                  );
                                                },
                                              );
                                            }
                                            try {
                                              final success = await AppRepositories.billing
                                                  .purchaseTherapistSubscription(
                                                    widget.thread.therapistId,
                                                    isCancelledCheck: () => _isCheckoutCancelled,
                                                    onUrlLaunched: () {
                                                      if (mounted) {
                                                        setState(() {
                                                          _isCheckoutUrlLaunched = true;
                                                        });
                                                      }
                                                    },
                                                  );
                                              if (isDialogOpen && dialogContext != null) {
                                                isDialogOpen = false;
                                                setState(() {
                                                  _isProgrammaticPop = true;
                                                });
                                                Navigator.pop(dialogContext!);
                                              }
                                              if (_isCheckoutCancelled) {
                                                AppRepositories.billing.deletePendingSubscription(widget.thread.therapistId);
                                                if (context.mounted) {
                                                  if (_isPaymentFailed) {
                                                    ScaffoldMessenger.of(context).showSnackBar(
                                                      const SnackBar(
                                                        content: Text('Payment failed. Please check your card details and try again.'),
                                                        backgroundColor: AppColors.errorRed,
                                                        duration: Duration(seconds: 5),
                                                      ),
                                                    );
                                                  } else {
                                                    ScaffoldMessenger.of(context).showSnackBar(
                                                      const SnackBar(
                                                        content: Text('Payment cancelled. You can renew anytime.'),
                                                        backgroundColor: Color(0xFF64748B),
                                                        duration: Duration(seconds: 4),
                                                      ),
                                                    );
                                                  }
                                                }
                                              } else if (success) {
                                                if (context.mounted) {
                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                    const SnackBar(
                                                      content: Text('Subscription renewed successfully!'),
                                                      backgroundColor: Color(0xFF00C853),
                                                    ),
                                                  );
                                                }
                                              } else {
                                                AppRepositories.billing.deletePendingSubscription(widget.thread.therapistId);
                                                if (context.mounted) {
                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                    const SnackBar(
                                                      content: Text('Payment timed out. Please try again.'),
                                                      backgroundColor: AppColors.errorRed,
                                                      duration: Duration(seconds: 5),
                                                    ),
                                                  );
                                                }
                                              }
                                            } catch (e) {
                                              setState(() {
                                                _isCheckoutCancelled = true;
                                                _isProgrammaticPop = true;
                                              });
                                              if (isDialogOpen && dialogContext != null) {
                                                isDialogOpen = false;
                                                Navigator.pop(dialogContext!);
                                              }
                                              AppRepositories.billing.deletePendingSubscription(widget.thread.therapistId);
                                              if (context.mounted) {
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  SnackBar(
                                                    content: Text('Error: $e'),
                                                    backgroundColor: AppColors.errorRed,
                                                  ),
                                                );
                                              }
                                            } finally {
                                              _activeCheckoutTherapistId = null;
                                            }
                                          },
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: const Color(0xFF00C853),
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                            shape: RoundedRectangleBorder(
                                              borderRadius: BorderRadius.circular(10),
                                            ),
                                          ),
                                          child: const Text(
                                            'Renew Subscription to Chat',
                                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                )
                              else
                                Row(
                                  children: [
                                    IconButton(
                                      icon: Icon(
                                        Icons.sentiment_satisfied_alt_outlined,
                                        color: _showEmojiPicker ? AppColors.primaryBlue : Colors.grey[600],
                                      ),
                                      onPressed: () {
                                        setState(() {
                                          _showEmojiPicker = !_showEmojiPicker;
                                        });
                                      },
                                    ),
                                    IconButton(
                                      icon: Icon(Icons.attach_file, color: Colors.grey[600]),
                                      onPressed: () {
                                        showModalBottomSheet<void>(
                                          context: context,
                                          builder: (context) {
                                            return SafeArea(
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  ListTile(
                                                    leading: const Icon(Icons.image, color: Colors.green),
                                                    title: const Text('Send Image'),
                                                    onTap: () {
                                                      Navigator.pop(context);
                                                      _pickImage();
                                                    },
                                                  ),
                                                  ListTile(
                                                    leading: const Icon(Icons.insert_drive_file, color: Colors.blue),
                                                    title: const Text('Send PDF / Document'),
                                                    onTap: () {
                                                      Navigator.pop(context);
                                                      _pickFile();
                                                    },
                                                  ),
                                                ],
                                              ),
                                            );
                                          },
                                        );
                                      },
                                    ),
                                    Expanded(
                                      child: TextField(
                                        controller: _controller,
                                        minLines: 1,
                                        maxLines: 4,
                                        decoration: InputDecoration(
                                          hintText: 'Send a message',
                                          filled: true,
                                          fillColor: const Color(0xFFF1F5F9),
                                          border: OutlineInputBorder(
                                            borderRadius: BorderRadius.circular(18),
                                            borderSide: BorderSide.none,
                                          ),
                                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    FloatingActionButton(
                                      onPressed:
                                          _sendState ==
                                                  _MessageSendState.sending
                                              ? null
                                              : _sendMessage,
                                      backgroundColor: AppColors.primaryBlue,
                                      foregroundColor: Colors.white,
                                      mini: true,
                                      child: _sendState ==
                                              _MessageSendState.sending
                                          ? const SizedBox(
                                              width: 18,
                                              height: 18,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.white,
                                              ),
                                            )
                                          : const Icon(Icons.send, size: 20),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _ChatStateBanner extends StatelessWidget {
  const _ChatStateBanner({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: color,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Text(
        text,
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          color: Color(0xFF223651),
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}

class _TherapistProfileDialog extends StatelessWidget {
  const _TherapistProfileDialog({
    required this.therapist,
    this.photoUrlBase64,
    required this.onCancelSubscription,
  });

  final TherapistProfile? therapist;
  final String? photoUrlBase64;
  final VoidCallback onCancelSubscription;

  String _specialization(TherapistProfile? profile) {
    if (profile == null || profile.specializations.isEmpty) {
      return 'Speech & Language Therapy';
    }
    return profile.specializations.first;
  }

  @override
  Widget build(BuildContext context) {
    final displayName = therapist?.displayName ?? 'Dr. Sarah Johnson';
    final specialization = _specialization(therapist);
    final rating = therapist?.rating ?? 4.9;
    final totalReviews = therapist?.totalReviews ?? 127;
    final formattedExperience = therapist?.formattedExperience ?? '12 years of practice';
    final credentials = therapist?.credentials != null && therapist!.credentials.isNotEmpty
        ? therapist!.credentials
        : 'Board Certified, Licensed Therapist';
    final bio = therapist?.bio != null && therapist!.bio.isNotEmpty
        ? therapist!.bio
        : 'Specialized in autism spectrum disorders and speech development. Passionate about helping children communicate effectively.';

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Green Header Card
          Stack(
            children: [
              Container(
                color: const Color(0xFF22C55E), // Vibrant Green
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                child: Column(
                  children: [
                    // Avatar with Gradient Ring
                    Container(
                      width: 82,
                      height: 82,
                      decoration: const BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: SweepGradient(
                          colors: [Color(0xFF22C55E), Color(0xFFFFB800), Color(0xFF22C55E)],
                        ),
                      ),
                      padding: const EdgeInsets.all(3),
                      child: Container(
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: ClipOval(
                          child: _TherapistPlaceholderAvatar(
                            size: 76,
                            photoUrlBase64: photoUrlBase64,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      displayName,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      specialization,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13.5,
                      ),
                    ),
                  ],
                ),
              ),
              // Close button
              Positioned(
                top: 12,
                right: 12,
                child: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    padding: const EdgeInsets.all(6),
                    child: const Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                ),
              ),
            ],
          ),
          
          // Body Content
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Star rating row
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.star, color: Colors.amber, size: 18),
                    const SizedBox(width: 4),
                    Text(
                      '${rating.toStringAsFixed(1)} ($totalReviews reviews)',
                      style: const TextStyle(
                        color: Color(0xFF475569),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 10),
                
                // Experience Row
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.access_time_rounded, color: Color(0xFF22C55E), size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Experience',
                            style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            formattedExperience,
                            style: const TextStyle(
                              color: Color(0xFF1E293B),
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                
                // Certifications Row
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.verified_user_outlined, color: Color(0xFF22C55E), size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Certifications',
                            style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            credentials,
                            style: const TextStyle(
                              color: Color(0xFF1E293B),
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 10),
                
                // About
                const Text(
                  'About',
                  style: TextStyle(
                    color: Color(0xFF1E293B),
                    fontWeight: FontWeight.bold,
                    fontSize: 14.5,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  bio,
                  style: const TextStyle(
                    color: Color(0xFF475569),
                    fontSize: 13,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 10),
                
                // Status dot row
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: Color(0xFF22C55E),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text(
                      'Active now',
                      style: TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                
                // Cancel Subscription button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: onCancelSubscription,
                    icon: const Icon(Icons.cancel_outlined, size: 18),
                    label: const Text(
                      'Cancel Subscription',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFEF4444),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
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
}

class CancelSubscriptionDialog extends StatelessWidget {
  const CancelSubscriptionDialog({
    super.key,
    required this.therapistName,
    required this.onConfirmCancel,
  });

  final String therapistName;
  final VoidCallback onConfirmCancel;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Red Alert Header Card
          Container(
            color: const Color(0xFFEF4444),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: const Column(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.white,
                  size: 48,
                ),
                SizedBox(height: 12),
                Text(
                  'Cancel Subscription?',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          // Content
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const Text(
                  'Are you sure you want to cancel your subscription?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF1E293B),
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 16),
                // Warning note box
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFFBEB), // Amber 50
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFFDE68A)), // Amber 200
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Please note: You will lose access to:',
                        style: TextStyle(
                          color: Color(0xFF78350F), // Amber 900
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        '• Direct messaging with the therapist\n'
                        '• 24-hour response time\n'
                        '• Progress tracking & reports\n'
                        '• Future session scheduling',
                        style: TextStyle(
                          color: Color(0xFF92400E), // Amber 800
                          fontSize: 12.5,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                // Buttons row
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFE2E8F0),
                          foregroundColor: const Color(0xFF475569),
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: const Text(
                          'Keep Subscription',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: onConfirmCancel,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFEF4444),
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: const Text(
                          'Yes, Cancel',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ChatHistoryChoicesDialog extends StatefulWidget {
  const ChatHistoryChoicesDialog({
    super.key,
    this.threadId,
    required this.therapistId,
    required this.onComplete,
  });

  final String? threadId;
  final String therapistId;
  final Function(String choice) onComplete;

  @override
  State<ChatHistoryChoicesDialog> createState() => _ChatHistoryChoicesDialogState();
}

class _ChatHistoryChoicesDialogState extends State<ChatHistoryChoicesDialog> {
  bool _isLoading = false;

  Future<void> _handleChoice(String choice) async {
    setState(() {
      _isLoading = true;
    });

    final parentId = FirebaseAuth.instance.currentUser?.uid;
    if (parentId == null) return;

    try {
      // 1. Call Billing Repository to cancel on the gateway and update database subscriptions & threads
      await AppRepositories.billing.cancelSubscriptionInStore(
        widget.therapistId,
        keepAndLockChats: choice == 'keep',
      );

      // 2. Remove from subscribed list and add to hidden list (if deleting)
      final userDoc = await FirebaseFirestore.instance
          .collection(FirestoreCollections.users)
          .doc(parentId)
          .get();
      
      List<dynamic> subscribed = [];
      List<dynamic> hidden = [];
      if (userDoc.exists && userDoc.data() != null) {
        subscribed = List.from(userDoc.data()?['proSupportSubscribedTherapistIds'] ?? []);
        hidden = List.from(userDoc.data()?['proSupportHiddenTherapistIds'] ?? []);
      }
      
      subscribed.remove(widget.therapistId);
      if (choice == 'delete') {
        if (!hidden.contains(widget.therapistId)) {
          hidden.add(widget.therapistId);
        }
      }

      await FirebaseFirestore.instance
          .collection(FirestoreCollections.users)
          .doc(parentId)
          .set({
            'proSupportSubscribedTherapistIds': subscribed,
            'proSupportHiddenTherapistIds': hidden,
            'proSupportUpdatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

      // Smooth transition delay
      await Future.delayed(const Duration(seconds: 1));
      
      if (mounted) {
        Navigator.pop(context, choice); // Close the dialog
        widget.onComplete(choice);
      }
    } catch (e) {
      debugPrint('Error cancelling subscription: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to cancel subscription: $e'),
            backgroundColor: const Color(0xFFEF4444),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Purple/Blue Gradient Banner
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF8B5CF6), Color(0xFF3B82F6)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Expanded(
                  child: Text(
                    'What about your chat history?',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (!_isLoading)
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white, size: 20),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
              ],
            ),
          ),
          
          if (_isLoading)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: const Column(
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text(
                    'Processing...',
                    style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Choose what you'd like to do with your conversation history and shared content",
                    style: TextStyle(
                      color: Color(0xFF475569),
                      fontSize: 13.5,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 20),
                  
                  // Option 1: Delete everything card
                  InkWell(
                    onTap: () => _handleChoice('delete'),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF2F2), // Red 50
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFFCA5A5)), // Red 200
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: const BoxDecoration(
                              color: Color(0xFFFEE2E2),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.delete_outline_rounded,
                              color: Color(0xFFEF4444),
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Delete Everything',
                                  style: TextStyle(
                                    color: Color(0xFF991B1B), // Red 800
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'Remove all messages, images, videos, and documents. The therapist will be completely removed from your messages list.',
                                  style: TextStyle(
                                    color: Color(0xFF7F1D1D),
                                    fontSize: 11.5,
                                    height: 1.35,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  
                  // Option 2: Keep & Lock Chats card
                  InkWell(
                    onTap: () => _handleChoice('keep'),
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF), // Blue 50
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFBFDBFE)), // Blue 200
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: const BoxDecoration(
                              color: Color(0xFFDBEAFE),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.lock_outline_rounded,
                              color: Color(0xFF3B82F6),
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Keep & Lock Chats',
                                  style: TextStyle(
                                    color: Color(0xFF1E3A8A), // Blue 800
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  "Save all conversation history. You can view messages but won't be able to send new ones. The therapist remains in your messages list (read-only).",
                                  style: TextStyle(
                                    color: Color(0xFF1E40AF),
                                    fontSize: 11.5,
                                    height: 1.35,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
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
}
