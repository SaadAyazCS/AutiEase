import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:printing/printing.dart';

import '../models/app_models.dart';
import '../repositories/app_repositories.dart';
import '../utils/app_colors.dart';
import '../widgets/session_guard.dart';

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
    if (photoUrlBase64 != null && photoUrlBase64!.isNotEmpty) {
      try {
        final imageBytes = base64Decode(photoUrlBase64!);
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

class _TherapistChatScreenState extends State<TherapistChatScreen> {
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

  @override
  void initState() {
    super.initState();
    _checkBlockedStatus();
    _loadPeerProfile();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _resolvedBannerTimer?.cancel();
    super.dispose();
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
                  value: selectedReason,
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
            context: this.context,
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
        ? _peerTherapistProfile?.photoUrlBase64
        : _peerUserProfile?.photoUrl;

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
              Text(
                isTherapist ? 'Therapist Specialist' : 'Verified Parent Member',
                style: const TextStyle(fontSize: 14, color: Color(0xFF00A63E), fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 10),
              if (isTherapist && _peerTherapistProfile != null) ...[
                _buildProfileDetailRow('Experience', _peerTherapistProfile!.formattedExperience),
                _buildProfileDetailRow('Bio', _peerTherapistProfile!.bio.isNotEmpty ? _peerTherapistProfile!.bio : 'No bio available yet.'),
                _buildProfileDetailRow('Availability', _peerTherapistProfile!.availability),
                _buildProfileDetailRow('Pricing', _peerTherapistProfile!.pricing),
              ] else ...[
                _buildProfileDetailRow('Role', 'Parent'),
                _buildProfileDetailRow('Verification Status', 'Verified account'),
              ],
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
        ? _peerTherapistProfile?.photoUrlBase64 
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
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF7F7F7),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    _isBlocked 
                                        ? 'This conversation is disabled because a user is blocked.'
                                        : 'Messaging is currently disabled for this conversation state.',
                                    style: const TextStyle(color: Colors.black54),
                                    textAlign: TextAlign.center,
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
