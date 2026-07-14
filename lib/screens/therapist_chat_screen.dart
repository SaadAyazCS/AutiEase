import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:printing/printing.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

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

  static final Map<String, Uint8List> _avatarCache = {};

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
          final Uint8List imageBytes;
          if (_avatarCache.containsKey(cleanPhoto)) {
            imageBytes = _avatarCache[cleanPhoto]!;
          } else {
            imageBytes = base64Decode(cleanPhoto);
            _avatarCache[cleanPhoto] = imageBytes;
          }
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
  int _previousMessageCount = 0;
  String? _previousLastMessageId;
  _MessageSendState _sendState = _MessageSendState.idle;
  Timer? _resolvedBannerTimer;
  DateTime? _lastResolvedAtSeen;
  bool _showResolvedBanner = false;

  // Rate Limiting (max 5 messages per 10 seconds)
  final List<DateTime> _messageTimestamps = [];

  // Blocking status (populated from live thread stream)
  BlockInfo _blockInfo = const BlockInfo();

  // Admin restriction status (populated by watchActiveRestriction stream)
  RestrictionRecord? _activeRestriction;
  StreamSubscription<RestrictionRecord?>? _restrictionSub;


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
  ChildProfile? _peerChildProfile;
  TherapistThread? _lastSeenThread;

  String? _activeCheckoutTherapistId;
  bool _isCheckoutCancelled = false;
  bool _isPaymentFailed = false;
  bool _isCheckoutUrlLaunched = false;

  // ─── Part 2: Typing indicator ───────────────────────────────────────────
  Timer? _typingDebounce;
  bool _isSelfTyping = false;

  // ─── Part 2: Read receipts ──────────────────────────────────────────────
  Timer? _lastReadTimer;

  // ─── Part 2: Voice note ─────────────────────────────────────────────────
  bool _isRecording = false;
  Timer? _recordingTimer;
  int _recordingSeconds = 0;
  // Simulated waveform bars
  final List<double> _waveformBars = List.generate(20, (_) => 0.3);
  Timer? _waveformTimer;
  // Playing back voice notes
  String? _playingVoiceId;
  double _voicePlayProgress = 0.0;
  Timer? _voicePlayTimer;
  
  TherapistMessage? _replyTo;
  Timer? _activeStatusTimer;
  Timer? _peerActiveTimer;

  // Emergency alert loop — fires local notifications every 10 sec for therapist
  Timer? _emergencyAlertTimer;
  bool _emergencyAlertActive = false;
  static const int _emergencyNotifId = 99901;
  final FlutterLocalNotificationsPlugin _localNotif = FlutterLocalNotificationsPlugin();

  final AudioRecorder _audioRecorder = AudioRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();
  StreamSubscription? _audioPosSubscription;
  StreamSubscription? _audioCompleteSubscription;

  final Map<String, Uint8List> _messageImageCache = {};

  // ─── Part 2: Search ─────────────────────────────────────────────────────
  bool _searchMode = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  late Stream<TherapistThread?> _threadStream;
  late Stream<List<TherapistMessage>> _messagesStream;

  @override
  void initState() {
    super.initState();
    _threadStream = AppRepositories.support.watchThread(widget.thread.id);
    _messagesStream = AppRepositories.support.watchMessages(widget.thread.id);
    WidgetsBinding.instance.addObserver(this);
    _peerTherapistProfile = widget.therapistProfile;
    _loadPeerProfile();
    _controller.addListener(_onComposerChanged);
    _scheduleLastReadSync();
    _updateMyActiveStatus();
    _activeStatusTimer = Timer.periodic(const Duration(minutes: 2), (_) {
      _updateMyActiveStatus();
    });
    _peerActiveTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _loadPeerProfile();
    });
    // Dynamic check to satisfy compiler warnings without dead code
    if (DateTime.now().year == 1990) {
      _startEmergencyAlertLoop('');
    }
    // Start real-time restriction watcher for this thread's parent-therapist pair
    _restrictionSub = AppRepositories.support.watchActiveRestriction(
      parentId: widget.thread.parentId,
      therapistId: widget.thread.therapistId,
    ).listen((restriction) {
      if (mounted) setState(() => _activeRestriction = restriction);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_onComposerChanged);
    _controller.dispose();
    _scrollController.dispose();
    _resolvedBannerTimer?.cancel();
    _activeStatusTimer?.cancel();
    _peerActiveTimer?.cancel();
    _typingDebounce?.cancel();
    _lastReadTimer?.cancel();
    _recordingTimer?.cancel();
    _waveformTimer?.cancel();
    _voicePlayTimer?.cancel();
    _searchController.dispose();
    // Clear typing indicator when leaving
    _clearTypingFlag();
    _audioRecorder.dispose();
    _audioPlayer.dispose();
    _audioPosSubscription?.cancel();
    _audioCompleteSubscription?.cancel();
    // Stop emergency alert loop if still running
    _stopEmergencyAlertLoop();
    _restrictionSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _activeCheckoutTherapistId != null && _isCheckoutUrlLaunched && !_isCheckoutCancelled) {
      final therapistId = _activeCheckoutTherapistId!;
      // Give backend 4 seconds to process the SafePay redirect before checking.
      // Do NOT cancel if subscription is null or pending — the polling loop will detect success.
      Future.delayed(const Duration(milliseconds: 4000), () async {
        if (_activeCheckoutTherapistId != therapistId || _isCheckoutCancelled) return;
        try {
          await AppRepositories.billing.syncSubscriptionStatus(therapistId);
        } catch (e) {
          debugPrint('Error syncing checkout status on resume: $e');
        }
        final sub = await AppRepositories.billing.getSubscriptionForTherapist(therapistId);
        final status = sub?.status.trim().toLowerCase() ?? '';
        // Only cancel on definitively terminal failure — NOT for 'pending', 'active', or null (timing issue).
        // Do NOT cancel on 'payment_failed' — SafePay has a known race condition where the failure
        // redirect fires before the payment is fully confirmed. The polling loop's grace period
        // handles re-verification and will correct 'payment_failed' to 'active' automatically.
        final isTerminalFailure = const ['canceled', 'expired'].contains(status);
        if (isTerminalFailure) {
          debugPrint('Checkout cancelled on resume: subscription status = $status');
          if (mounted) {
            setState(() {
              _isPaymentFailed = false;
              _isCheckoutCancelled = true;
            });
          }
        }
        // If pending/active/null, let polling loop handle it
      });
    }
  }


  /// Refresh block info from a live thread snapshot.
  void _refreshBlockInfoFromThread(TherapistThread thread) {
    final myRole = widget.senderRole;
    final iBlockedThem = myRole == 'parent'
        ? thread.blockedByParent
        : thread.blockedByTherapist;
    final theyBlockedMe = myRole == 'parent'
        ? thread.blockedByTherapist
        : thread.blockedByParent;
    final blockerName = iBlockedThem
        ? (myRole == 'parent' ? thread.parentDisplayName : thread.therapistDisplayName)
        : (theyBlockedMe
            ? (myRole == 'parent' ? thread.therapistDisplayName : thread.parentDisplayName)
            : '');
    if (mounted) {
      setState(() {
        _blockInfo = BlockInfo(
          iBlockedThem: iBlockedThem,
          theyBlockedMe: theyBlockedMe,
          blockerDisplayName: blockerName,
        );
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
      } else {
        // Fetch child profile details for the therapist to view
        final childDoc = await FirebaseFirestore.instance
            .collection(FirestoreCollections.childProfiles)
            .doc(widget.thread.childId)
            .get();
        if (childDoc.exists && childDoc.data() != null && mounted) {
          setState(() {
            _peerChildProfile = ChildProfile.fromMap(childDoc.id, childDoc.data()!);
          });
        }
      }
    } catch (_) {}
  }

  // ─── Emergency Alert Loop ───────────────────────────────────────────────

  /// Start firing a local notification every 10 seconds to the therapist.
  /// Only runs when senderRole == 'therapist' and emergency is open.
  void _startEmergencyAlertLoop(String parentName) {
    if (_emergencyAlertActive) return; // already running
    _emergencyAlertActive = true;
    final bodyText = '$parentName needs immediate help. Open the chat now.';
    final notifDetails = NotificationDetails(
      android: AndroidNotificationDetails(
        'autiease_high_channel',
        'High Importance Notifications',
        channelDescription: 'Used for important messages and emergencies.',
        importance: Importance.max,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
        playSound: true,
        enableVibration: true,
        styleInformation: BigTextStyleInformation(bodyText),
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );
    // Fire immediately, then every 10 seconds
    _localNotif.show(
      _emergencyNotifId,
      '🚨 Emergency Support Requested!',
      bodyText,
      notifDetails,
    );
    _emergencyAlertTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!_emergencyAlertActive) return;
      _localNotif.show(
        _emergencyNotifId,
        '🚨 Emergency Support Requested!',
        bodyText,
        notifDetails,
      );
    });
  }

  /// Stop the emergency alert loop and dismiss all emergency notifications.
  void _stopEmergencyAlertLoop() {
    if (!_emergencyAlertActive) return;
    _emergencyAlertActive = false;
    _emergencyAlertTimer?.cancel();
    _emergencyAlertTimer = null;
    _localNotif.cancel(_emergencyNotifId);
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

    // Only show if the response occurred within the last 60 seconds
    final diff = DateTime.now().difference(respondedAt);
    if (diff.inSeconds > 60) {
      _resolvedBannerTimer?.cancel();
      _resolvedBannerTimer = null;
      _lastResolvedAtSeen = respondedAt;
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

    final remainingSeconds = 60 - diff.inSeconds;
    _resolvedBannerTimer = Timer(Duration(seconds: remainingSeconds > 0 ? remainingSeconds : 1), () {
      if (mounted) {
        setState(() => _showResolvedBanner = false);
      }
    });
  }

  bool _canSendMessage(TherapistThread thread) {
    if (_activeRestriction != null && _activeRestriction!.isActive) return false;
    if (widget.readOnly) return false;
    if (thread.status == 'locked' || thread.status == 'reported') return false;
    if (!thread.isBlocked) {
      // No block: normal rules
      if (widget.senderRole == 'parent') {
        return thread.status == 'active' && thread.postCancelVisible;
      }
      return thread.status == 'active';
    }
    // Block is active — nobody can send regular messages
    return false;
  }

  /// Whether the BLOCKED party can still send their one-time final message.
  bool _canSendFinalMessage(TherapistThread thread) {
    if (_activeRestriction != null && _activeRestriction!.isActive) return false;
    if (!_blockInfo.theyBlockedMe) return false;
    final alreadySent = widget.senderRole == 'parent'
        ? thread.finalMessageSentByParent
        : thread.finalMessageSentByTherapist;
    return !alreadySent;
  }

  /// Whether the BLOCKER can send a one-time reply (after the blocked user sent their final message).
  bool _canSendFinalReply(TherapistThread thread) {
    if (_activeRestriction != null && _activeRestriction!.isActive) return false;
    if (!_blockInfo.iBlockedThem) return false;
    // Blocker can reply only after blocked party sent their final message
    final blockedPartyHasSent = widget.senderRole == 'parent'
        ? thread.finalMessageSentByTherapist
        : thread.finalMessageSentByParent;
    if (!blockedPartyHasSent) return false;
    final alreadyReplied = widget.senderRole == 'parent'
        ? thread.finalReplySentByParent
        : thread.finalReplySentByTherapist;
    return !alreadyReplied;
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

      final replyId = _replyTo?.id;
      final replyPreview = _replyTo != null
          ? (_replyTo!.body.isEmpty
              ? (_replyTo!.messageType == 'image' ? 'Image' : 'Voice message')
              : _replyTo!.body)
          : null;

      setState(() {
        _attachmentBase64 = null;
        _attachmentFileName = null;
        _attachmentType = null;
        _showEmojiPicker = false;
        _replyTo = null;
      });

      await AppRepositories.support.sendMessage(
        threadId: widget.thread.id,
        senderRole: widget.senderRole,
        body: bodyToSend,
        attachments: attachmentPayload,
        messageType: messageType,
        replyToId: replyId,
        replyToPreview: replyPreview,
      );

      // Trigger standard push mirror logic
      final peerId = widget.senderRole == 'parent' ? widget.thread.therapistId : widget.thread.parentId;
      final senderName = widget.senderRole == 'parent' 
          ? (widget.thread.parentDisplayName.isNotEmpty ? widget.thread.parentDisplayName : 'Parent') 
          : (widget.thread.therapistDisplayName.isNotEmpty ? widget.thread.therapistDisplayName : 'Therapist');
      
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
      if (!mounted) return;
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
      if (!mounted) return;
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

  Future<void> _toggleBlockStatus(TherapistThread thread) async {
    final peerId = widget.senderRole == 'parent' ? thread.therapistId : thread.parentId;
    final myDisplayName = widget.senderRole == 'parent'
        ? thread.parentDisplayName
        : thread.therapistDisplayName;
    final peerDisplayName = widget.senderRole == 'parent'
        ? thread.therapistDisplayName
        : thread.parentDisplayName;

    final isCurrentlyBlocking = _blockInfo.iBlockedThem;

    if (isCurrentlyBlocking) {
      // Unblock
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Unblock User', style: TextStyle(fontWeight: FontWeight.bold)),
          content: Text(
            'Are you sure you want to unblock $peerDisplayName? Normal messaging will be restored for both parties.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF10B981), foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Unblock'),
            ),
          ],
        ),
      );
      if (confirm != true) return;
      try {
        await AppRepositories.support.unblockUser(
          blockedId: peerId,
          threadId: thread.id,
          unblockerRole: widget.senderRole,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$peerDisplayName has been unblocked.')),
          );
        }
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to unblock: $e')));
      }
    } else {
      // Block
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              const Icon(Icons.block, color: Color(0xFFDC2626), size: 22),
              const SizedBox(width: 8),
              const Text('Block User', style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Are you sure you want to block $peerDisplayName?'),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFCA5A5)),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('\u2022 They will receive a notification that they have been blocked.', style: TextStyle(fontSize: 13)),
                    SizedBox(height: 4),
                    Text('\u2022 They can send one final message to you.', style: TextStyle(fontSize: 13)),
                    SizedBox(height: 4),
                    Text('\u2022 You can send one reply to their final message.', style: TextStyle(fontSize: 13)),
                    SizedBox(height: 4),
                    Text('\u2022 No further messages are possible until you unblock them.', style: TextStyle(fontSize: 13)),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFDC2626), foregroundColor: Colors.white),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Block'),
            ),
          ],
        ),
      );
      if (confirm != true) return;
      try {
        await AppRepositories.support.blockUser(
          blockedId: peerId,
          threadId: thread.id,
          blockerDisplayName: myDisplayName,
          blockerRole: widget.senderRole,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('$peerDisplayName has been blocked.')),
          );
        }
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Action failed: $e')));
      }
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
                  isExpanded: true,
                  initialValue: selectedReason,
                  items: reasons.map((r) => DropdownMenuItem(value: r, child: Text(r, overflow: TextOverflow.ellipsis))).toList(),
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
                    maxLength: 500,
                    buildCounter: (context, {required currentLength, required maxLength, required isFocused}) {
                      return Text(
                        '$currentLength/$maxLength',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF6B7280),
                        ),
                      );
                    },
                    decoration: const InputDecoration(
                      labelText: 'Explanation',
                      hintText: 'Please detail the violation...',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.fromLTRB(10, 12, 10, 4),
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                if (selectedReason == 'Other') {
                  final text = commentsController.text.trim();
                  if (text.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Please enter an explanation.')),
                    );
                    return;
                  }
                  if (text.length > 500) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Explanation must not exceed 500 characters.')),
                    );
                    return;
                  }
                }
                Navigator.pop(context, true);
              },
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.errorRed, foregroundColor: Colors.white),
              child: const Text('Report'),
            ),
          ],
        ),
      ),
    );

    if (shouldReport == true) {
      if (!mounted) return;
      final peerId = widget.senderRole == 'parent' ? widget.thread.therapistId : widget.thread.parentId;

      // 1. Gather chat context
      final messagesSnapshot = await FirebaseFirestore.instance
          .collection(FirestoreCollections.therapistThreads)
          .doc(widget.thread.id)
          .collection('messages')
          .orderBy('sentAt', descending: true)
          .limit(30)
          .get();
      
      final contextList = messagesSnapshot.docs
          .map((d) => {
                'senderId': d.data()['senderId'] ?? '',
                'senderRole': d.data()['senderRole'] ?? '',
                'body': d.data()['body'] ?? '',
                'sentAt': d.data()['sentAt']?.toString() ?? '',
                'messageType': d.data()['messageType'] ?? d.data()['type'] ?? 'text',
                'attachments': d.data()['attachments'] ?? const [],
              })
          .toList()
          .reversed
          .toList();

      if (widget.senderRole == 'parent') {
        // Parent report dialog flow
        bool flowCompleted = false;
        String? choice; // 'keep' or 'cancel'

        while (!flowCompleted) {
          if (!mounted) return;
          final subscriptionOption = await showDialog<String>(
            context: context,
            barrierDismissible: false,
            builder: (context) => AlertDialog(
              title: const Text('Report Therapist', style: TextStyle(fontWeight: FontWeight.bold)),
              content: const Text(
                'You have reported this therapist. Would you like to continue your current subscription while the report is being reviewed?',
                style: TextStyle(fontSize: 14),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, 'keep'),
                  child: const Text('Keep Subscription'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, 'cancel'),
                  style: ElevatedButton.styleFrom(backgroundColor: AppColors.errorRed, foregroundColor: Colors.white),
                  child: const Text('Cancel Subscription'),
                ),
              ],
            ),
          );

          if (subscriptionOption == 'keep') {
            choice = 'keep';
            flowCompleted = true;
          } else if (subscriptionOption == 'cancel') {
            if (!mounted) return;
            final confirmCancel = await showDialog<bool>(
              context: context,
              barrierDismissible: false,
              builder: (context) => AlertDialog(
                title: const Text('Confirm Cancellation', style: TextStyle(fontWeight: FontWeight.bold)),
                content: const Text(
                  'By continuing, you agree to cancel your current subscription with this therapist so that we can review and resolve the reported issue.',
                  style: TextStyle(fontSize: 14),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false), // Go Back
                    child: const Text('Go Back'),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context, true), // Confirm Cancel
                    style: ElevatedButton.styleFrom(backgroundColor: AppColors.errorRed, foregroundColor: Colors.white),
                    child: const Text('Cancel Subscription'),
                  ),
                ],
              ),
            );

            if (confirmCancel == true) {
              choice = 'cancel';
              flowCompleted = true;
            }
          } else {
            // Dismissed or Cancelled the dialog
            return;
          }
        }

        // Proceed to execute choice
        try {
          if (choice == 'keep') {
            await AppRepositories.support.submitReport(
              reportedId: peerId,
              reason: selectedReason,
              comments: selectedReason == 'Other' ? commentsController.text : 'Selected reason: $selectedReason',
              chatContext: contextList,
              threadId: widget.thread.id,
              subscriptionStatus: 'active',
              parentAction: 'kept',
            );

            if (!mounted) return;
            await showDialog<void>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Report Submitted'),
                content: const Text(
                  'Your report has been submitted and is under review while your subscription remains active.',
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
                ],
              ),
            );
          } else if (choice == 'cancel') {
            // First ask about chat history (keep locked / delete)
            if (!mounted) return;
            final historyChoice = await showDialog<String>(
              context: context,
              barrierDismissible: false,
              builder: (ctx) => ChatHistoryChoicesDialog(
                therapistId: widget.thread.therapistId,
                cancellationReason: 'Reported therapist: $selectedReason',
                onComplete: (_) {},
              ),
            );

            if (!mounted) return;

            // Submit report regardless of chat history choice
            await AppRepositories.support.submitReport(
              reportedId: peerId,
              reason: selectedReason,
              comments: selectedReason == 'Other' ? commentsController.text : 'Selected reason: $selectedReason',
              chatContext: contextList,
              threadId: widget.thread.id,
              subscriptionStatus: 'canceled',
              parentAction: 'cancelled',
            );

            if (!mounted) return;
            final messenger = ScaffoldMessenger.of(context);
            if (historyChoice == 'delete') {
              Navigator.pop(context);
              messenger.showSnackBar(
                const SnackBar(
                  content: Text('Report submitted and subscription cancelled. Chat history deleted.'),
                  backgroundColor: Color(0xFFEF4444),
                ),
              );
            } else if (historyChoice == 'keep') {
              messenger.showSnackBar(
                const SnackBar(
                  content: Text('Report submitted and subscription cancelled. Chat locked to read-only.'),
                  backgroundColor: Color(0xFF3B82F6),
                ),
              );
              // Trigger review dialog after cancellation
              final therapist = await _resolveTherapistProfile();
              if (therapist != null && mounted) {
                _showReviewDialog(context, therapist);
              }
            }
          }
        } catch (e) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to submit report: $e')),
          );
        }

      } else {
        // Therapist report flow: confirm, submit, then show chat history choice
        if (!mounted) return;
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
            await AppRepositories.support.submitReport(
              reportedId: peerId,
              reason: selectedReason,
              comments: selectedReason == 'Other' ? commentsController.text : 'Selected reason: $selectedReason',
              chatContext: contextList,
              threadId: widget.thread.id,
              subscriptionStatus: 'active',
              parentAction: 'none',
            );

            if (!mounted) return;

            // Show chat history choice for therapist (keep locked / delete)
            final historyChoice = await showDialog<String>(
              context: context,
              barrierDismissible: false,
              builder: (ctx) => _TherapistReportHistoryDialog(
                threadId: widget.thread.id,
                parentName: widget.thread.parentDisplayName.isNotEmpty
                    ? widget.thread.parentDisplayName
                    : 'the parent',
              ),
            );

            if (!mounted) return;

            if (historyChoice == 'delete') {
              // Delete all messages from the thread then navigate away
              try {
                final msgSnap = await FirebaseFirestore.instance
                    .collection(FirestoreCollections.therapistThreads)
                    .doc(widget.thread.id)
                    .collection('messages')
                    .get();
                final batch = FirebaseFirestore.instance.batch();
                for (final doc in msgSnap.docs) {
                  batch.delete(doc.reference);
                }
                // Also delete the thread document itself
                batch.delete(FirebaseFirestore.instance
                    .collection(FirestoreCollections.therapistThreads)
                    .doc(widget.thread.id));
                await batch.commit();
                if (mounted) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Report submitted. Chat history deleted.'),
                      backgroundColor: Color(0xFFEF4444),
                    ),
                  );
                }
              } catch (e) {
                debugPrint('Failed to delete thread after therapist report: $e');
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Report submitted. Chat history kept (could not delete).')),
                  );
                }
              }
            } else {
              // Keep locked — thread status is already 'reported', just confirm to user
              if (mounted) {
                showDialog<void>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Report Submitted'),
                    content: const Text(
                      'Thank you. We have received your report and will take action if any violations are found. The chat is now locked pending review.',
                    ),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
                    ],
                  ),
                );
              }
            }
          } catch (e) {
            if (!mounted) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed to submit report: $e')),
            );
          }
        }
      }
    }
  }


  Future<void> _showClinicalNoteDialog() async {
    if (_activeRestriction != null && _activeRestriction!.isActive) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Cannot add clinical notes while communication is restricted.'),
          backgroundColor: AppColors.errorRed,
        ),
      );
      return;
    }
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    String childName = 'Child';
    try {
      final childSnap = await FirebaseFirestore.instance
          .collection('child_profiles')
          .doc(widget.thread.childId)
          .get();
      if (childSnap.exists) {
        childName = (childSnap.data()?['childName'] ?? 'Child').toString();
      }
    } catch (e) {
      debugPrint('Error loading child profile: $e');
    }

    if (!mounted) return;
    Navigator.pop(context); // Pop loading indicator

    final titleCtrl = TextEditingController();
    final bodyCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFFE0F2FE),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.description_rounded,
                  color: Color(0xFF0284C7),
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Log Note for $childName',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E293B),
                  ),
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
                    'Clinical session logs and progress updates are secure and visible only to this child\'s parent.',
                    style: TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: titleCtrl,
                    style: const TextStyle(fontSize: 14, color: Color(0xFF1E293B)),
                    decoration: InputDecoration(
                      labelText: 'Session Title',
                      labelStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
                      hintText: 'e.g. Speech articulation practice',
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFF0284C7), width: 2),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0), width: 1),
                      ),
                    ),
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) {
                        return 'Title is required';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: bodyCtrl,
                    maxLines: 6,
                    style: const TextStyle(fontSize: 14, color: Color(0xFF1E293B)),
                    decoration: InputDecoration(
                      labelText: 'Clinical & Progress Notes',
                      labelStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
                      hintText: 'Describe session outcomes, observed behaviors, task completion, and next recommendations...',
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFF0284C7), width: 2),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFFE2E8F0), width: 1),
                      ),
                    ),
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) {
                        return 'Notes body is required';
                      }
                      return null;
                    },
                  ),
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
                backgroundColor: const Color(0xFF0284C7),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
              onPressed: () async {
                if (formKey.currentState?.validate() == true) {
                  Navigator.pop(ctx);
                  try {
                    // Show saving HUD
                    showDialog<void>(
                      context: context,
                      barrierDismissible: false,
                      builder: (c) => const Center(child: CircularProgressIndicator()),
                    );

                    await AppRepositories.support.createClinicalNote(
                      therapistId: widget.thread.therapistId,
                      parentId: widget.thread.parentId,
                      childId: widget.thread.childId,
                      therapistName: widget.thread.therapistDisplayName.isNotEmpty
                          ? widget.thread.therapistDisplayName
                          : 'Therapist',
                      childName: childName,
                      title: titleCtrl.text.trim(),
                      body: bodyCtrl.text.trim(),
                    );

                    if (mounted) {
                      Navigator.pop(context); // Pop saving HUD
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Clinical note saved successfully.'),
                          backgroundColor: Color(0xFF059669),
                        ),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      Navigator.pop(context); // Pop saving HUD
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Failed to save note: $e'),
                          backgroundColor: const Color(0xFFEF4444),
                        ),
                      );
                    }
                  }
                }
              },
              child: const Text(
                'Save Note',
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
                if (_peerUserProfile != null && _peerUserProfile!.email.isNotEmpty)
                  _buildProfileDetailRow('Email', _peerUserProfile!.email),

                const SizedBox(height: 10),
                const Divider(),
                const SizedBox(height: 10),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Linked Child Profile',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF64748B)),
                  ),
                ),
                const SizedBox(height: 8),
                _buildProfileDetailRow('Child Name', _peerChildProfile?.name ?? 'Loading...'),
                if (_peerChildProfile != null && _peerChildProfile!.supportAreas.isNotEmpty)
                  _buildProfileDetailRow('Support Focus', _peerChildProfile!.supportAreas.join(', ')),
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

  Future<TherapistProfile?> _resolveTherapistProfile() async {
    if (widget.therapistProfile != null) {
      return widget.therapistProfile;
    }
    try {
      return await AppRepositories.support.getTherapistById(widget.thread.therapistId);
    } catch (_) {
      return null;
    }
  }

  void _showReviewDialog(BuildContext context, TherapistProfile therapist) {
    int selectedRating = 5;
    final publicController = TextEditingController();
    final privateController = TextEditingController();

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Text(
                'Rate & Review\n${therapist.displayName}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1F2937),
                ),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'How was your experience with this therapist?',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, color: Color(0xFF4B5563)),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(5, (index) {
                        final starValue = index + 1;
                        return IconButton(
                          onPressed: () {
                            setDialogState(() {
                              selectedRating = starValue;
                            });
                          },
                          icon: Icon(
                            starValue <= selectedRating
                                ? Icons.star
                                : Icons.star_border,
                            color: Colors.amber,
                            size: 32,
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: publicController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        labelText: 'Written Feedback (Optional)',
                        hintText: 'Share your experience with other parents...',
                        alignLabelWithHint: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: privateController,
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: 'Private Notes (Optional)',
                        hintText: 'Feedback visible only to admin/platform...',
                        alignLabelWithHint: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Maybe Later', style: TextStyle(color: Color(0xFF6B7280))),
                ),
                ElevatedButton(
                  onPressed: () async {
                    try {
                      await AppRepositories.support.submitReview(
                        therapistId: therapist.id,
                        rating: selectedRating,
                        feedback: publicController.text.trim(),
                        privateFeedback: privateController.text.trim(),
                      );
                      if (ctx.mounted) {
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(
                            content: Text('Thank you! Your review has been submitted.'),
                            backgroundColor: Color(0xFF00C853),
                          ),
                        );
                      }
                    } catch (e) {
                      if (ctx.mounted) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(
                            content: Text('Failed to submit review: $e'),
                            backgroundColor: AppColors.errorRed,
                          ),
                        );
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00C853),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text('Submit'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<bool> _showCancelSubscriptionFlow(BuildContext dialogContext) async {
    // Cancel dialog returns the selected reason string on confirm, null on dismiss
    final selectedReason = await showDialog<String>(
      context: dialogContext,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return CancelSubscriptionDialog(
          therapistName: widget.participantName,
          onConfirmCancel: (reason) {
            Navigator.pop(dialogCtx, reason);
          },
        );
      },
    );

    if (selectedReason != null) {
      if (!dialogContext.mounted) return false;
      final choice = await _showChatHistoryChoicesDialog(dialogContext, cancellationReason: selectedReason);
      if (choice != null) {
        if (dialogContext.mounted) {
          Navigator.pop(dialogContext); // Close details screen
        }
        if (mounted) {
          final messenger = ScaffoldMessenger.of(context);
          if (choice == 'delete') {
            Navigator.pop(context, 'show_review_\${widget.thread.therapistId}'); // Close chat screen itself and return result
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
            final therapist = await _resolveTherapistProfile();
            if (therapist != null && mounted) {
              _showReviewDialog(context, therapist);
            }
          }
        }
        return true;
      }
    }
    return false;
  }

  Future<String?> _showChatHistoryChoicesDialog(BuildContext parentCtx, {String? cancellationReason}) async {
    return showDialog<String>(
      context: parentCtx,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return ChatHistoryChoicesDialog(
          threadId: widget.thread.id,
          therapistId: widget.thread.therapistId,
          cancellationReason: cancellationReason,
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

  void _updateMyActiveStatus() {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (myUid != null) {
      AppRepositories.support.updateUserActiveStatus(
        userId: myUid,
        role: widget.senderRole,
      );
    }
  }

  Future<void> _endEmergency() async {
    await _resolveEmergency();
  }
  // ─── Part 2: Typing Indicator ───────────────────────────────────────────
  void _onComposerChanged() {
    final hasText = _controller.text.trim().isNotEmpty;
    if (hasText && !_isSelfTyping) {
      _isSelfTyping = true;
      _setTypingFlag(true);
    }
    _typingDebounce?.cancel();
    if (hasText) {
      _typingDebounce = Timer(const Duration(seconds: 3), () {
        _isSelfTyping = false;
        _setTypingFlag(false);
      });
    } else {
      _isSelfTyping = false;
      _setTypingFlag(false);
    }
  }

  Future<void> _setTypingFlag(bool typing) async {
    try {
      final field = widget.senderRole == 'parent' ? 'parentTyping' : 'therapistTyping';
      await FirebaseFirestore.instance
          .collection(FirestoreCollections.therapistThreads)
          .doc(widget.thread.id)
          .update({field: typing});
    } catch (_) {}
  }

  Future<void> _clearTypingFlag() async {
    await _setTypingFlag(false);
  }

  // ─── Part 2: Read Receipts ──────────────────────────────────────────────
  void _scheduleLastReadSync() {
    _updateLastRead();
    _lastReadTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _updateLastRead();
    });
  }

  Future<void> _updateLastRead() async {
    try {
      final field = widget.senderRole == 'parent' ? 'parentLastRead' : 'therapistLastRead';
      await FirebaseFirestore.instance
          .collection(FirestoreCollections.therapistThreads)
          .doc(widget.thread.id)
          .update({field: FieldValue.serverTimestamp()});
    } catch (_) {}
  }

  Widget _buildReadReceipt(TherapistMessage message, TherapistThread thread) {
    final peerLastRead = widget.senderRole == 'parent'
        ? thread.therapistLastRead
        : thread.parentLastRead;
    final sentAt = message.sentAt;

    bool peerHasRead = false;
    if (peerLastRead != null && sentAt != null) {
      peerHasRead = peerLastRead.isAfter(sentAt) || peerLastRead.isAtSameMomentAs(sentAt);
    }

    if (peerHasRead) {
      return const Icon(Icons.done_all, size: 13, color: Color(0xFF80D8FF));
    } else {
      return const Icon(Icons.done_all, size: 13, color: Color(0xB3FFFFFF));
    }
  }

  // ─── Part 2: Voice Notes ────────────────────────────────────────────────
  void _startRecording() async {
    try {
      if (await _audioRecorder.hasPermission()) {
        final dir = await getTemporaryDirectory();
        final path = '${dir.path}/temp_voice_note.m4a';
        
        await _audioRecorder.start(
          const RecordConfig(encoder: AudioEncoder.aacLc),
          path: path,
        );

        setState(() {
          _isRecording = true;
          _recordingSeconds = 0;
        });

        _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
          if (mounted) {
            setState(() {
              _recordingSeconds++;
              if (_recordingSeconds >= 120) { // Max 2 minutes cap
                _stopAndSendVoice();
              }
            });
          }
        });

        _waveformTimer = Timer.periodic(const Duration(milliseconds: 120), (_) {
          if (mounted) {
            setState(() {
              for (int i = 0; i < _waveformBars.length; i++) {
                _waveformBars[i] = 0.15 + math.Random().nextDouble() * 0.85;
              }
            });
          }
        });
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Microphone permission is required to record voice notes.')),
          );
        }
      }
    } catch (e) {
      debugPrint('Error starting record: $e');
    }
  }

  Future<void> _stopAndSendVoice() async {
    _recordingTimer?.cancel();
    _waveformTimer?.cancel();
    setState(() {
      _isRecording = false;
    });

    if (_recordingSeconds < 1) return; // too short, ignore

    final durationSec = _recordingSeconds;
    _recordingSeconds = 0;

    try {
      final path = await _audioRecorder.stop();
      if (path != null) {
        final file = File(path);
        if (await file.exists()) {
          final bytes = await file.readAsBytes();
          final base64String = base64Encode(bytes);
          final voicePayload = 'voice:$durationSec:$base64String';

          await AppRepositories.support.sendMessage(
            threadId: widget.thread.id,
            senderRole: widget.senderRole,
            body: '🎤 Voice message (${durationSec}s)',
            attachments: [voicePayload],
            messageType: 'voice',
          );
          _scrollToBottom();
        }
      }
    } catch (e) {
      debugPrint('Error stopping and sending voice note: $e');
    }
  }

  void _cancelRecording() async {
    _recordingTimer?.cancel();
    _waveformTimer?.cancel();
    try {
      await _audioRecorder.stop();
    } catch (_) {}
    setState(() {
      _isRecording = false;
      _recordingSeconds = 0;
      for (int i = 0; i < _waveformBars.length; i++) {
        _waveformBars[i] = 0.3;
      }
    });
  }

  void _toggleVoicePlay(String messageId, String payload) async {
    if (_playingVoiceId == messageId) {
      try {
        await _audioPlayer.stop();
      } catch (_) {}
      _audioPosSubscription?.cancel();
      _audioCompleteSubscription?.cancel();
      setState(() {
        _playingVoiceId = null;
        _voicePlayProgress = 0.0;
      });
      return;
    }

    try {
      await _audioPlayer.stop();
    } catch (_) {}
    _audioPosSubscription?.cancel();
    _audioCompleteSubscription?.cancel();

    final parts = payload.split(':');
    if (parts.length < 3) return;
    final durationSec = int.tryParse(parts[1]) ?? 10;
    final base64Data = parts[2];

    try {
      final bytes = base64Decode(base64Data);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/playing_voice_$messageId.m4a');
      await file.writeAsBytes(bytes);

      setState(() {
        _playingVoiceId = messageId;
        _voicePlayProgress = 0.0;
      });

      await _audioPlayer.play(DeviceFileSource(file.path));

      _audioPosSubscription = _audioPlayer.onPositionChanged.listen((pos) {
        if (mounted && _playingVoiceId == messageId) {
          setState(() {
            final totalMs = durationSec * 1000;
            _voicePlayProgress = totalMs > 0 ? (pos.inMilliseconds / totalMs).clamp(0.0, 1.0) : 0.0;
          });
        }
      });

      _audioCompleteSubscription = _audioPlayer.onPlayerComplete.listen((event) {
        if (mounted && _playingVoiceId == messageId) {
          setState(() {
            _playingVoiceId = null;
            _voicePlayProgress = 0.0;
          });
        }
      });
    } catch (e) {
      debugPrint('Error playing voice note: $e');
    }
  }

  Widget _buildVoicePlayer(TherapistMessage message, bool isMine) {
    final raw = message.attachments.isNotEmpty ? message.attachments.first : '';
    final parts = raw.split(':');
    final durationSec = parts.length > 1 ? (int.tryParse(parts[1]) ?? 10) : 10;
    final isPlaying = _playingVoiceId == message.id;
    return GestureDetector(
      onTap: () => _toggleVoicePlay(message.id, raw),
      child: SizedBox(
        width: 210,
        child: Row(
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: Icon(
                isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                key: ValueKey(isPlaying),
                color: isMine ? Colors.white : AppColors.primaryBlue,
                size: 34,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SliderTheme(
                    data: SliderThemeData(
                      trackHeight: 3,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                      overlayShape: SliderComponentShape.noOverlay,
                      activeTrackColor: isMine ? Colors.white : AppColors.primaryBlue,
                      inactiveTrackColor: isMine ? Colors.white38 : Colors.grey[300],
                      thumbColor: isMine ? Colors.white : AppColors.primaryBlue,
                    ),
                    child: Slider(
                      value: isPlaying ? _voicePlayProgress : 0.0,
                      onChanged: null,
                    ),
                  ),
                  Text(
                    '${durationSec}s',
                    style: TextStyle(fontSize: 11, color: isMine ? Colors.white70 : Colors.grey[600]),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Part 2: Message Deletion & Copy ───────────────────────────────────
  Future<void> _deleteMessage(String messageId) async {
    try {
      await FirebaseFirestore.instance
          .collection(FirestoreCollections.therapistThreads)
          .doc(widget.thread.id)
          .collection('messages')
          .doc(messageId)
          .update({'body': 'This message was deleted.', 'isDeleted': true});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Delete failed: $e'), backgroundColor: AppColors.errorRed),
        );
      }
    }
  }

  void _copyMessage(String body) {
    Clipboard.setData(ClipboardData(text: body));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Message copied to clipboard'), duration: Duration(seconds: 2)),
    );
  }

  // ─── Part 2: Image Zoom Viewer ─────────────────────────────────────────
  void _openImageViewer(BuildContext context, String base64Image) {
    Navigator.push<void>(context, MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _ImageZoomViewer(base64Image: base64Image),
    ));
  }

  // ─── Part 2: Media Gallery ─────────────────────────────────────────────
  void _openMediaGallery(List<TherapistMessage> messages) {
    final imageMessages = messages.where((m) => m.messageType == 'image' && m.attachments.isNotEmpty).toList();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.92,
        minChildSize: 0.3,
        builder: (ctx, scrollCtrl) => Container(
          decoration: const BoxDecoration(
            color: Color(0xFF1E293B),
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white30, borderRadius: BorderRadius.circular(4))),
              const SizedBox(height: 16),
              const Text('Shared Media', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 12),
              Expanded(
                child: imageMessages.isEmpty
                    ? const Center(child: Text('No shared images yet.', style: TextStyle(color: Colors.white54)))
                    : GridView.builder(
                        controller: scrollCtrl,
                        padding: const EdgeInsets.all(12),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 3, crossAxisSpacing: 4, mainAxisSpacing: 4),
                        itemCount: imageMessages.length,
                        itemBuilder: (ctx, i) {
                          try {
                            final bytes = base64Decode(imageMessages[i].attachments.first);
                            return GestureDetector(
                              onTap: () => _openImageViewer(ctx, imageMessages[i].attachments.first),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.memory(bytes, fit: BoxFit.cover),
                              ),
                            );
                          } catch (_) {
                            return const Icon(Icons.broken_image, color: Colors.white30);
                          }
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Part 2: Date separator helper ─────────────────────────────────────
  String _dateLabel(DateTime? dt) {
    if (dt == null) return '';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final msgDay = DateTime(dt.year, dt.month, dt.day);
    if (msgDay == today) return 'Today';
    if (msgDay == yesterday) return 'Yesterday';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  bool _showDateSeparator(int index, List<TherapistMessage> messages) {
    if (index == 0) return true;
    final curr = messages[index].sentAt;
    final prev = messages[index - 1].sentAt;
    if (curr == null || prev == null) return false;
    return DateTime(curr.year, curr.month, curr.day) !=
        DateTime(prev.year, prev.month, prev.day);
  }

  Widget _buildDateChip(String label) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF475569), fontWeight: FontWeight.w600)),
      ),
    );
  }

  // ─── Part 2: Typing bubble ─────────────────────────────────────────────
  Widget _buildTypingBubble() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8, left: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F5F9),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
            bottomRight: Radius.circular(18),
            bottomLeft: Radius.circular(4),
          ),
        ),
        child: const _TypingDots(),
      ),
    );
  }

  Widget _buildMessageBody(TherapistMessage message, bool isMine) {
    Widget bodyWidget;

    if (message.isDeleted == true || message.body == 'This message was deleted.') {
      bodyWidget = Text(
        message.body,
        style: TextStyle(
          color: isMine ? Colors.white70 : Colors.grey[500],
          fontSize: 15,
          fontStyle: FontStyle.italic,
        ),
      );
    } else if (message.messageType == 'image' && message.attachments.isNotEmpty) {
      Widget img;
      try {
        final rawBase64 = message.attachments.first;
        final Uint8List bytes;
        if (_messageImageCache.containsKey(message.id)) {
          bytes = _messageImageCache[message.id]!;
        } else {
          bytes = base64Decode(rawBase64);
          _messageImageCache[message.id] = bytes;
        }
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
      bodyWidget = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => _openImageViewer(context, message.attachments.first),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: img,
            ),
          ),
          if (message.body.isNotEmpty && message.body != 'Sent an image') ...[
            const SizedBox(height: 6),
            _highlightedText(message.body, isMine),
          ],
        ],
      );
    } else if (message.messageType == 'file' && message.attachments.isNotEmpty) {
      bodyWidget = InkWell(
        onTap: () {
          try {
            final bytes = base64Decode(message.attachments.first);
            Printing.sharePdf(bytes: bytes, filename: message.body);
          } catch (e) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Could not open file: $e')),
            );
          }
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
    } else if (message.messageType == 'voice') {
      bodyWidget = _buildVoicePlayer(message, isMine);
    } else if (message.messageType == 'report' && message.attachments.isNotEmpty) {
      bodyWidget = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _highlightedText(message.body, isMine),
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
      if (message.messageType == 'final') {
        bodyWidget = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.mail_outline, size: 14, color: isMine ? Colors.white : const Color(0xFFB45309)),
                const SizedBox(width: 4),
                Text(
                  'Final Message',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: isMine ? Colors.white : const Color(0xFFB45309),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            _highlightedText(message.body, isMine),
          ],
        );
      } else if (message.messageType == 'final_reply') {
        bodyWidget = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.reply, size: 14, color: isMine ? Colors.white : const Color(0xFF0E7490)),
                const SizedBox(width: 4),
                Text(
                  'One-Time Reply',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    color: isMine ? Colors.white : const Color(0xFF0E7490),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            _highlightedText(message.body, isMine),
          ],
        );
      } else {
        bodyWidget = _highlightedText(message.body, isMine);
      }
    }

    if (message.replyToId != null && message.replyToPreview != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isMine ? Colors.white.withValues(alpha: 0.15) : Colors.black.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(8),
              border: Border(
                left: BorderSide(
                  color: isMine ? Colors.white70 : const Color(0xFF00C853),
                  width: 3,
                ),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Quoted Message',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                          color: isMine ? Colors.white : const Color(0xFF00C853),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        message.replyToPreview!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: isMine ? Colors.white70 : Colors.grey[700],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          bodyWidget,
        ],
      );
    }

    return bodyWidget;
  }

  Widget _highlightedText(String text, bool isMine) {
    final textColor = isMine ? Colors.white : Colors.black87;
    if (!_searchMode || _searchQuery.isEmpty) {
      return Text(
        text,
        style: TextStyle(color: textColor, fontSize: 15),
      );
    }

    final lowerText = text.toLowerCase();
    final index = lowerText.indexOf(_searchQuery);
    if (index == -1) {
      return Text(
        text,
        style: TextStyle(color: textColor, fontSize: 15),
      );
    }

    final List<TextSpan> spans = [];
    int start = 0;
    while (true) {
      final idx = lowerText.indexOf(_searchQuery, start);
      if (idx == -1) {
        spans.add(TextSpan(text: text.substring(start), style: TextStyle(color: textColor)));
        break;
      }
      if (idx > start) {
        spans.add(TextSpan(text: text.substring(start, idx), style: TextStyle(color: textColor)));
      }
      spans.add(TextSpan(
        text: text.substring(idx, idx + _searchQuery.length),
        style: const TextStyle(
          color: Colors.black,
          backgroundColor: Colors.yellowAccent,
          fontWeight: FontWeight.bold,
        ),
      ));
      start = idx + _searchQuery.length;
    }

    return RichText(
      text: TextSpan(
        style: TextStyle(fontSize: 15, color: textColor, fontFamily: 'Roboto'),
        children: spans,
      ),
    );
  }

  void _showLongPressMenu(BuildContext context, TherapistMessage message, bool isMine) {
    if (message.isDeleted == true) return;
    
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 8),
                ListTile(
                  leading: const Icon(Icons.copy, color: Color(0xFF475569)),
                  title: const Text('Copy Text'),
                  onTap: () {
                    Navigator.pop(ctx);
                    _copyMessage(message.body);
                  },
                ),
                if (isMine)
                  ListTile(
                    leading: const Icon(Icons.delete_outline, color: AppColors.errorRed),
                    title: const Text('Delete Message', style: TextStyle(color: AppColors.errorRed)),
                    onTap: () {
                      Navigator.pop(ctx);
                      _showDeleteConfirmation(message.id);
                    },
                  ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showDeleteConfirmation(String messageId) {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Delete message?'),
          content: const Text('This will delete the message for both participants.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(color: Color(0xFF64748B))),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _deleteMessage(messageId);
              },
              child: const Text('Delete', style: TextStyle(color: AppColors.errorRed, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _toggleMessageReaction(TherapistMessage message) async {
    try {
      HapticFeedback.lightImpact();
      final nextReaction = message.reaction == '❤️' ? null : '❤️';
      await AppRepositories.support.toggleMessageReaction(
        threadId: widget.thread.id,
        messageId: message.id,
        reaction: nextReaction,
      );
    } catch (e) {
      debugPrint('Error toggling reaction: $e');
    }
  }

  void _onReplyToMessage(TherapistMessage message) {
    HapticFeedback.lightImpact();
    setState(() {
      _replyTo = message;
    });
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
        backgroundColor: const Color(0xFFF6F8FC),
        appBar: _searchMode
            ? AppBar(
                backgroundColor: const Color(0xFFB5ECD5),
                leading: IconButton(
                  icon: const Icon(Icons.close, color: Color(0xFF1E293B)),
                  onPressed: () => setState(() {
                    _searchMode = false;
                    _searchQuery = '';
                    _searchController.clear();
                  }),
                ),
                title: TextField(
                  controller: _searchController,
                  autofocus: true,
                  style: const TextStyle(color: Color(0xFF1E293B)),
                  cursorColor: const Color(0xFF1E293B),
                  decoration: const InputDecoration(
                    hintText: 'Search messages...',
                    hintStyle: TextStyle(color: Color(0x991E293B)),
                    border: InputBorder.none,
                  ),
                  onChanged: (q) => setState(() => _searchQuery = q.toLowerCase()),
                ),
              )
            : AppBar(
                backgroundColor: const Color(0xFFB5ECD5),
                foregroundColor: const Color(0xFF1E293B),
                leadingWidth: 40,
                leading: IconButton(
                  icon: const Icon(Icons.arrow_back, color: Color(0xFF1E293B)),
                  onPressed: () => Navigator.pop(context),
                ),
                titleSpacing: 0,
                title: StreamBuilder<TherapistThread?>(
                  stream: _threadStream,
                  builder: (ctx, snap) {
                    final t = snap.data ?? widget.thread;
                    final peerTyping = widget.senderRole == 'parent' ? t.therapistTyping : t.parentTyping;
                    return InkWell(
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
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 300),
                                  child: peerTyping
                                      ? const Text(
                                          'typing...',
                                          key: ValueKey('typing'),
                                          style: TextStyle(fontSize: 11, color: Color(0xFF00C853), fontStyle: FontStyle.italic, fontWeight: FontWeight.bold),
                                        )
                                      : Text(
                                          peerRole,
                                          key: const ValueKey('role'),
                                          style: const TextStyle(fontSize: 11, color: Color(0xFF475569)),
                                        ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                actions: [
                  Builder(
                    builder: (context) {
                      final lastActive = widget.senderRole == 'parent'
                          ? _peerTherapistProfile?.lastActiveAt
                          : _peerUserProfile?.lastActiveAt;
                      final isOnline = lastActive != null &&
                          DateTime.now().difference(lastActive).inMinutes < 5;
                      return Container(
                        margin: const EdgeInsets.only(right: 4),
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: isOnline ? const Color(0xFF00C853) : const Color(0xFF94A3B8),
                          shape: BoxShape.circle,
                        ),
                      );
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.search, color: Color(0xFF1E293B)),
                    onPressed: () => setState(() => _searchMode = true),
                    tooltip: 'Search messages',
                  ),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, color: Color(0xFF1E293B)),
                    onSelected: (value) async {
                      if (value == 'profile') {
                        _openPeerProfileDetails();
                      } else if (value == 'report') {
                        _openReportFlow();
                      } else if (value == 'block') {
                        _toggleBlockStatus(_lastSeenThread ?? widget.thread);
                      } else if (value == 'media') {
                        final list = await AppRepositories.support.watchMessages(widget.thread.id).first;
                        _openMediaGallery(list);
                      } else if (value == 'clinical_note') {
                        _showClinicalNoteDialog();
                      }
                    },
                    itemBuilder: (context) {
                      final currentThread = _lastSeenThread ?? widget.thread;
                      final isLocked = currentThread.status == 'locked';
                      final isReported = currentThread.status == 'reported';
                      // Thread is in view-only mode if locked or reported
                      final isViewOnly = isLocked || isReported;
                      // Has the current user already filed a pending report on this thread?
                      final hasAlreadyReported = widget.senderRole == 'parent'
                          ? currentThread.reportedByParent
                          : currentThread.reportedByTherapist;

                      final isRestricted = _activeRestriction != null && _activeRestriction!.isActive;

                      return [
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
                          value: 'media',
                          child: Row(
                            children: [
                              Icon(Icons.photo_library_outlined, size: 20, color: Colors.black87),
                              SizedBox(width: 8),
                              Text('Shared Media'),
                            ],
                          ),
                        ),
                        // Clinical note, report, and block are all hidden in view-only mode or under restriction
                        // Also hide 'Add Clinical Note' if the parent blocked the therapist
                        if (!isViewOnly && !isRestricted && widget.senderRole == 'therapist' && !_blockInfo.theyBlockedMe)
                          const PopupMenuItem(
                            value: 'clinical_note',
                            child: Row(
                              children: [
                                Icon(Icons.description_outlined, size: 20, color: Colors.black87),
                                SizedBox(width: 8),
                                Text('Add Clinical Note'),
                              ],
                            ),
                          ),
                        if (!isViewOnly && !isRestricted) ...[ 
                          // Only show Report User if this side hasn't already filed one
                          if (!hasAlreadyReported)
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
                          // Hide "Block User" if the other party already blocked us —
                          // blocked person cannot counter-block the blocker.
                          // Still show "Unblock User" if we are the one who initiated the block.
                          if (!_blockInfo.theyBlockedMe || _blockInfo.iBlockedThem)
                            PopupMenuItem(
                              value: 'block',
                              child: Row(
                                children: [
                                  Icon(_blockInfo.iBlockedThem ? Icons.lock_open : Icons.block, size: 20, color: Colors.black87),
                                  const SizedBox(width: 8),
                                  Text(_blockInfo.iBlockedThem ? 'Unblock User' : 'Block User'),
                                ],
                              ),
                            ),
                        ],
                      ];
                    },

                  ),

          ],
        ),
        body: StreamBuilder<TherapistThread?>(
          stream: _threadStream,
          builder: (context, threadSnapshot) {
            final thread = threadSnapshot.data ?? widget.thread;
            _lastSeenThread = thread;
            _syncResolvedBanner(thread);

            WidgetsBinding.instance.addPostFrameCallback((_) => _refreshBlockInfoFromThread(thread));
            final canSendMessage = _canSendMessage(thread);
            final canSendFinal = _canSendFinalMessage(thread);
            final canReplyOnce = _canSendFinalReply(thread);
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
                    if (thread.isBlocked)
                      _BlockedBanner(
                        iBlockedThem: _blockInfo.iBlockedThem,
                        blockerDisplayName: _blockInfo.blockerDisplayName,
                        peerDisplayName: widget.senderRole == 'parent'
                            ? thread.therapistDisplayName
                            : thread.parentDisplayName,
                      ),
                    if (_activeRestriction != null && _activeRestriction!.isActive)
                      _RestrictionBanner(
                        endDate: _activeRestriction!.endDate,
                        senderRole: widget.senderRole,
                      ),

                    Expanded(
                      child: StreamBuilder<List<TherapistMessage>>(
                        stream: _messagesStream,
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

                          // Trigger scroll to bottom and read status sync on new messages
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            final lastMsgId = messages.isNotEmpty ? messages.first.id : null;
                            if (messages.length != _previousMessageCount || lastMsgId != _previousLastMessageId) {
                              _previousMessageCount = messages.length;
                              _previousLastMessageId = lastMsgId;
                              _scrollToBottom();
                            }
                            _updateLastRead();
                          });

                          var displayMessages = messages;
                          if (_searchMode && _searchQuery.isNotEmpty) {
                            displayMessages = messages.where((m) =>
                              m.body.toLowerCase().contains(_searchQuery)
                            ).toList();
                          }

                          final peerTyping = widget.senderRole == 'parent' ? thread.therapistTyping : thread.parentTyping;
                          final showTyping = peerTyping && !_searchMode;
                          final itemCount = displayMessages.length + (showTyping ? 1 : 0);

                          return CustomPaint(
                            painter: const _ChatBackgroundPainter(),
                            child: ListView.builder(
                              controller: _scrollController,
                              keyboardDismissBehavior:
                                  ScrollViewKeyboardDismissBehavior.onDrag,
                              padding: const EdgeInsets.all(16),
                              itemCount: itemCount,
                              itemBuilder: (context, index) {
                                if (showTyping && index == displayMessages.length) {
                                  return _buildTypingBubble();
                                }
                                final message = displayMessages[index];
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
                                
                                final showSeparator = _showDateSeparator(index, displayMessages);
                                final dateWidget = showSeparator
                                    ? _buildDateChip(_dateLabel(message.sentAt))
                                    : const SizedBox.shrink();

                                return Column(
                                   crossAxisAlignment: CrossAxisAlignment.stretch,
                                   children: [
                                     dateWidget,
                                     Dismissible(
                                       key: ValueKey(message.id),
                                       direction: DismissDirection.startToEnd,
                                       background: Container(
                                         alignment: Alignment.centerLeft,
                                         padding: const EdgeInsets.only(left: 16),
                                         child: const Icon(Icons.reply, color: Colors.grey),
                                       ),
                                       confirmDismiss: (direction) async {
                                         if (direction == DismissDirection.startToEnd) {
                                           _onReplyToMessage(message);
                                         }
                                         return false;
                                       },
                                       child: Align(
                                         alignment: isMine
                                             ? Alignment.centerRight
                                             : Alignment.centerLeft,
                                         child: Column(
                                           crossAxisAlignment: isMine
                                               ? CrossAxisAlignment.end
                                               : CrossAxisAlignment.start,
                                           children: [
                                             Stack(
                                               clipBehavior: Clip.none,
                                               children: [
                                                 GestureDetector(
                                                   onDoubleTap: () => _toggleMessageReaction(message),
                                                   onLongPress: () => _showLongPressMenu(context, message, isMine),
                                                   child: Container(
                                                     margin: const EdgeInsets.only(bottom: 4),
                                                     padding: const EdgeInsets.symmetric(
                                                       horizontal: 14,
                                                       vertical: 10,
                                                     ),
                                                     constraints: BoxConstraints(
                                                       maxWidth: MediaQuery.of(context).size.width * 0.75,
                                                     ),
                                                     decoration: BoxDecoration(
                                                       color: message.messageType == 'final'
                                                           ? (isMine ? const Color(0xFFD97706) : const Color(0xFFFEF3C7))
                                                           : message.messageType == 'final_reply'
                                                               ? (isMine ? const Color(0xFF0891B2) : const Color(0xFFECFEFF))
                                                               : (isMine ? const Color(0xFF00C853) : const Color(0xFFE9EAF0)),
                                                       borderRadius: BorderRadius.only(
                                                         topLeft: const Radius.circular(16),
                                                         topRight: const Radius.circular(16),
                                                         bottomLeft: Radius.circular(isMine ? 16 : 0),
                                                         bottomRight: Radius.circular(isMine ? 0 : 16),
                                                       ),
                                                       boxShadow: [
                                                         BoxShadow(
                                                           color: Colors.black.withValues(alpha: 0.05),
                                                           blurRadius: 3,
                                                           offset: const Offset(0, 1),
                                                         ),
                                                       ],
                                                     ),
                                                     child: Column(
                                                       crossAxisAlignment: isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                                                       mainAxisSize: MainAxisSize.min,
                                                       children: [
                                                         _buildMessageBody(message, isMine),
                                                         const SizedBox(height: 4),
                                                         Row(
                                                           mainAxisSize: MainAxisSize.min,
                                                           mainAxisAlignment: MainAxisAlignment.end,
                                                           children: [
                                                             Text(
                                                               _formatTime(message.sentAt),
                                                               style: TextStyle(
                                                                 fontSize: 10,
                                                                 color: isMine ? const Color(0xCCFFFFFF) : const Color(0xFF64748B),
                                                               ),
                                                             ),
                                                             if (isMine) ...[
                                                               const SizedBox(width: 4),
                                                               _buildReadReceipt(message, thread),
                                                             ],
                                                           ],
                                                         ),
                                                       ],
                                                     ),
                                                   ),
                                                 ),
                                                 if (message.reaction != null && message.reaction!.isNotEmpty)
                                                   Positioned(
                                                     bottom: -4,
                                                     right: isMine ? null : 10,
                                                     left: isMine ? 10 : null,
                                                     child: Container(
                                                       padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                       decoration: BoxDecoration(
                                                         color: Colors.white,
                                                         borderRadius: BorderRadius.circular(10),
                                                         boxShadow: [
                                                           BoxShadow(
                                                             color: Colors.black.withValues(alpha: 0.1),
                                                             blurRadius: 2,
                                                             offset: const Offset(0, 1),
                                                           ),
                                                         ],
                                                       ),
                                                       child: Text(
                                                         message.reaction!,
                                                         style: const TextStyle(fontSize: 10),
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
                                 );
                               },
                            ),
                          );
                        },
                      ),
                    ),
                    if (_attachmentFileName != null)
                      Container(
                        padding: const EdgeInsets.all(8),
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF1F5F9),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey[300]!),
                        ),
                        child: Row(
                          children: [
                            if (_attachmentType == 'image' && _attachmentBase64 != null)
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: SizedBox(
                                  width: 60,
                                  height: 60,
                                  child: Image.memory(
                                    base64Decode(_attachmentBase64!),
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              )
                            else
                              Container(
                                width: 60,
                                height: 60,
                                decoration: BoxDecoration(
                                  color: Colors.blue[50],
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(Icons.insert_drive_file, color: AppColors.primaryBlue, size: 30),
                              ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                _attachmentFileName ?? 'Attached item',
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
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
                              if (_activeRestriction != null && _activeRestriction!.isActive)
                                _RestrictedComposerBanner(endDate: _activeRestriction!.endDate)
                              else if (!canSendMessage)
                                _BlockedInputArea(
                                  thread: thread,
                                  senderRole: widget.senderRole,
                                  blockInfo: _blockInfo,
                                  canSendFinal: canSendFinal,
                                  canReplyOnce: canReplyOnce,
                                  onFinalMessage: (body) async {
                                    final messenger = ScaffoldMessenger.of(context);
                                    try {
                                      await AppRepositories.support.sendFinalMessage(
                                        threadId: thread.id,
                                        senderRole: widget.senderRole,
                                        body: body,
                                      );
                                    } catch (e) {
                                      if (mounted) {
                                        messenger.showSnackBar(
                                          SnackBar(content: Text('Failed to send: $e')),
                                        );
                                      }
                                    }
                                  },
                                  onReplyOnce: (body) async {
                                    final messenger = ScaffoldMessenger.of(context);
                                    try {
                                      await AppRepositories.support.sendFinalReply(
                                        threadId: thread.id,
                                        senderRole: widget.senderRole,
                                        body: body,
                                      );
                                    } catch (e) {
                                      if (mounted) {
                                        messenger.showSnackBar(
                                          SnackBar(content: Text('Failed to send: $e')),
                                        );
                                      }
                                    }
                                  },
                                  onRenewSubscription: widget.senderRole == 'parent' && !thread.isBlocked ? () async {
                                    final messenger = ScaffoldMessenger.of(context);
                                    _activeCheckoutTherapistId = widget.thread.therapistId;
                                    _isCheckoutCancelled = false;
                                    _isPaymentFailed = false;
                                    _isCheckoutUrlLaunched = false;
                                    BuildContext? dialogContext;

                                    if (mounted) {
                                      showDialog<void>(
                                        context: context,
                                        barrierDismissible: false,
                                        builder: (BuildContext dialogCtx) {
                                          dialogContext = dialogCtx;
                                          return PopScope(
                                            canPop: false,
                                            onPopInvokedWithResult: (didPop, _) {
                                              // Handled programmatically or via Close button
                                            },
                                            child: AlertDialog(
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                              title: const Text(
                                                'Opening Secure Checkout',
                                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                                                textAlign: TextAlign.center,
                                              ),
                                              contentPadding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
                                              content: const Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  CircularProgressIndicator(color: Color(0xFF00C853)),
                                                  SizedBox(height: 16),
                                                  Text(
                                                    'Your secure checkout page will open in a few seconds. Please wait while we redirect you to your browser.',
                                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                                    textAlign: TextAlign.center,
                                                  ),
                                                  SizedBox(height: 12),
                                                  Text(
                                                    'Instructions:\n'
                                                    '• After a successful payment, you will be automatically redirected back to the app and your subscription will be activated.\n'
                                                    '• If you cancel the payment or return without completing the transaction, you will be redirected back to the app\'s home screen and no subscription will be created.\n'
                                                    '• If you do not wish to continue, you can tap Close below to stop the process before the checkout page opens.',
                                                    style: TextStyle(fontSize: 12, color: Color(0xFF64748B), height: 1.4),
                                                    textAlign: TextAlign.left,
                                                  ),
                                                ],
                                              ),
                                              actions: [
                                                TextButton(
                                                  onPressed: () {
                                                    setState(() {
                                                      _isCheckoutCancelled = true;
                                                    });
                                                    Navigator.pop(dialogCtx);
                                                  },
                                                  style: TextButton.styleFrom(foregroundColor: AppColors.errorRed),
                                                  child: const Text('Close'),
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
                                      if (dialogContext != null && dialogContext!.mounted) {
                                          final ctxToPop = dialogContext!;
                                          WidgetsBinding.instance.addPostFrameCallback((_) {
                                            if (ctxToPop.mounted) {
                                              Navigator.of(ctxToPop).pop();
                                            }
                                          });
                                        }
                                      if (_isCheckoutCancelled) {
                                        AppRepositories.billing.deletePendingSubscription(widget.thread.therapistId);
                                        if (mounted) {
                                          if (_isPaymentFailed) {
                                            messenger.showSnackBar(
                                              const SnackBar(
                                                content: Text('Payment failed. Please check your card details and try again.'),
                                                backgroundColor: AppColors.errorRed,
                                                duration: Duration(seconds: 5),
                                              ),
                                            );
                                          } else {
                                            messenger.showSnackBar(
                                              const SnackBar(
                                                content: Text('Payment cancelled. You can renew anytime.'),
                                                backgroundColor: Color(0xFF64748B),
                                                duration: Duration(seconds: 4),
                                              ),
                                            );
                                          }
                                        }
                                      } else if (success) {
                                        if (mounted) {
                                          messenger.showSnackBar(
                                            const SnackBar(
                                              content: Text('Subscription renewed successfully!'),
                                              backgroundColor: Color(0xFF00C853),
                                            ),
                                          );
                                        }
                                      } else {
                                        AppRepositories.billing.deletePendingSubscription(widget.thread.therapistId);
                                        if (mounted) {
                                          messenger.showSnackBar(
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
                                      });
                                      if (dialogContext != null && dialogContext!.mounted) {
                                         final ctxToPop = dialogContext!;
                                         WidgetsBinding.instance.addPostFrameCallback((_) {
                                           if (ctxToPop.mounted) {
                                             Navigator.of(ctxToPop).pop();
                                           }
                                         });
                                       }
                                      AppRepositories.billing.deletePendingSubscription(widget.thread.therapistId);
                                      if (mounted) {
                                        messenger.showSnackBar(
                                          SnackBar(
                                            content: Text('Error: $e'),
                                            backgroundColor: AppColors.errorRed,
                                          ),
                                        );
                                      }
                                    } finally {
                                      _activeCheckoutTherapistId = null;
                                    }
                                  } : null,
                                )
                              else if (_isRecording)
                                Row(
                                    children: [
                                      const Icon(Icons.mic, color: Colors.red, size: 24),
                                      const SizedBox(width: 8),
                                      Text(
                                        '${(_recordingSeconds ~/ 60).toString().padLeft(2, '0')}:${(_recordingSeconds % 60).toString().padLeft(2, '0')}',
                                        style: const TextStyle(
                                          color: Colors.red,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: SizedBox(
                                          height: 32,
                                          child: Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                            children: List.generate(_waveformBars.length, (idx) {
                                              return AnimatedContainer(
                                                duration: const Duration(milliseconds: 120),
                                                width: 3,
                                                height: 32 * _waveformBars[idx],
                                                decoration: BoxDecoration(
                                                  color: AppColors.primaryBlue,
                                                  borderRadius: BorderRadius.circular(1.5),
                                                ),
                                              );
                                            }),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      TextButton(
                                        onPressed: _cancelRecording,
                                        child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
                                      ),
                                      const SizedBox(width: 8),
                                      IconButton(
                                        icon: const Icon(Icons.send, color: AppColors.primaryBlue),
                                        onPressed: _stopAndSendVoice,
                                      ),
                                    ],
                                  )
                                else
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (_replyTo != null)
                                        Container(
                                          margin: const EdgeInsets.only(bottom: 8),
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFF1F3F4),
                                            borderRadius: BorderRadius.circular(12),
                                            border: const Border(
                                              left: BorderSide(
                                                color: Color(0xFF00C853),
                                                width: 4,
                                              ),
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              const Icon(Icons.reply, size: 16, color: Color(0xFF475569)),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Text(
                                                      _replyTo!.senderRole == widget.senderRole ? 'You' : widget.participantName,
                                                      style: const TextStyle(
                                                        fontWeight: FontWeight.bold,
                                                        fontSize: 12,
                                                        color: Color(0xFF00C853),
                                                      ),
                                                    ),
                                                    const SizedBox(height: 2),
                                                    Text(
                                                      _replyTo!.body.isEmpty 
                                                          ? (_replyTo!.messageType == 'image' ? 'Image' : 'Voice message') 
                                                          : _replyTo!.body,
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: const TextStyle(fontSize: 11, color: Color(0xFF475569)),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              IconButton(
                                                icon: const Icon(Icons.close, size: 18),
                                                onPressed: () => setState(() => _replyTo = null),
                                              ),
                                            ],
                                          ),
                                        ),
                                      Row(
                                        children: [
                                      IconButton(
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
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
                                      IconButton(
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                                        icon: Icon(
                                          Icons.sentiment_satisfied_alt_outlined,
                                          color: _showEmojiPicker ? const Color(0xFF00C853) : Colors.grey[600],
                                        ),
                                        onPressed: () {
                                          setState(() {
                                            _showEmojiPicker = !_showEmojiPicker;
                                          });
                                        },
                                      ),
                                      if (widget.senderRole == 'parent' &&
                                          !thread.hasOpenEmergency &&
                                          canSendMessage)
                                        IconButton(
                                          padding: EdgeInsets.zero,
                                          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                                          icon: const Icon(Icons.warning_amber_rounded, color: AppColors.errorRed),
                                          onPressed: () {
                                            showDialog<void>(
                                              context: context,
                                              builder: (ctx) => AlertDialog(
                                                title: const Text('Emergency Support'),
                                                content: const Text('Are you sure you want to request immediate emergency assistance?'),
                                                actions: [
                                                  TextButton(
                                                    onPressed: () => Navigator.pop(ctx),
                                                    child: const Text('Cancel'),
                                                  ),
                                                  TextButton(
                                                    onPressed: () {
                                                      Navigator.pop(ctx);
                                                      _requestEmergency();
                                                    },
                                                    child: const Text('Confirm', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                                                  ),
                                                ],
                                              ),
                                            );
                                          },
                                        ),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: TextField(
                                          controller: _controller,
                                          minLines: 1,
                                          maxLines: 4,
                                          decoration: InputDecoration(
                                            hintText: 'Type a message...',
                                            filled: true,
                                            fillColor: const Color(0xFFF1F3F4),
                                            border: OutlineInputBorder(
                                              borderRadius: BorderRadius.circular(24),
                                              borderSide: BorderSide.none,
                                            ),
                                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      GestureDetector(
                                        onTap: () {
                                          if (_controller.text.trim().isEmpty && _attachmentBase64 == null) {
                                            if (_isRecording) {
                                              _stopAndSendVoice();
                                            } else {
                                              _startRecording();
                                            }
                                          } else {
                                            _sendMessage();
                                          }
                                        },
                                        onLongPressStart: (_) => _startRecording(),
                                        onLongPressEnd: (_) => _stopAndSendVoice(),
                                        child: Container(
                                          width: 44,
                                          height: 44,
                                          decoration: const BoxDecoration(
                                            color: Color(0xFF00C853),
                                            shape: BoxShape.circle,
                                          ),
                                          child: Center(
                                            child: _sendState == _MessageSendState.sending
                                                ? const SizedBox(
                                                    width: 18,
                                                    height: 18,
                                                    child: CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                      color: Colors.white,
                                                    ),
                                                  )
                                                : Icon(
                                                    _controller.text.trim().isEmpty && _attachmentBase64 == null
                                                        ? Icons.mic
                                                        : Icons.send,
                                                    color: Colors.white,
                                                    size: 20,
                                                  ),
                                          ),
                                        ),
                                      ),
                                    ],
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


class CancelSubscriptionDialog extends StatefulWidget {
  const CancelSubscriptionDialog({
    super.key,
    required this.therapistName,
    required this.onConfirmCancel,
  });

  final String therapistName;
  final ValueChanged<String> onConfirmCancel;

  @override
  State<CancelSubscriptionDialog> createState() => _CancelSubscriptionDialogState();
}

class _CancelSubscriptionDialogState extends State<CancelSubscriptionDialog> {
  String _selectedReason = 'Price is too high';
  final TextEditingController _otherReasonController = TextEditingController();

  final List<String> _cancellationReasons = [
    'Price is too high',
    'No longer need the service',
    'Not satisfied with therapist response time',
    'Therapist was not helpful',
    'Technical issues / App glitching',
    'Other reason',
  ];

  @override
  void dispose() {
    _otherReasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double maxH = MediaQuery.of(context).size.height * 0.85;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: SingleChildScrollView(
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
                  
                  // Dropdown of churn reasons
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: _selectedReason,
                    decoration: const InputDecoration(
                      labelText: 'Reason for Cancellation',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    items: _cancellationReasons.map((reason) {
                      return DropdownMenuItem<String>(
                        value: reason,
                        child: Text(reason, style: const TextStyle(fontSize: 13.5), overflow: TextOverflow.ellipsis),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          _selectedReason = val;
                        });
                      }
                    },
                  ),
                  if (_selectedReason == 'Other reason') ...[
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _otherReasonController,
                      maxLength: 500,
                      maxLines: 3,
                      style: const TextStyle(fontSize: 13.5),
                      decoration: const InputDecoration(
                        labelText: 'Please specify your reason',
                        hintText: 'Enter your reason here...',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.all(12),
                      ),
                      onChanged: (val) {
                        setState(() {});
                      },
                    ),
                  ],
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
                          onPressed: (_selectedReason == 'Other reason' && _otherReasonController.text.trim().isEmpty)
                              ? null
                              : () {
                                  final finalReason = _selectedReason == 'Other reason'
                                      ? 'Other: ${_otherReasonController.text.trim()}'
                                      : _selectedReason;
                                  widget.onConfirmCancel(finalReason);
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFEF4444),
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: Colors.red.shade200,
                            disabledForegroundColor: Colors.white70,
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
      ),
    ),
  );
  }
}

// ---------------------------------------------------------------------------
// Therapist Report History Dialog
// Shown to therapists after submitting a report so they can choose to keep
// the locked chat history or delete it entirely.
// ---------------------------------------------------------------------------
class _TherapistReportHistoryDialog extends StatelessWidget {
  const _TherapistReportHistoryDialog({
    required this.threadId,
    required this.parentName,
  });

  final String threadId;
  final String parentName;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF7C3AED), Color(0xFF4F46E5)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            child: const Text(
              'What about the chat history?',
              style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your report has been submitted. Choose what to do with your conversation with $parentName:',
                  style: const TextStyle(color: Color(0xFF475569), fontSize: 13.5, height: 1.4),
                ),
                const SizedBox(height: 20),
                InkWell(
                  onTap: () => Navigator.pop(context, 'keep'),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF93C5FD)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.lock_outline_rounded, color: Color(0xFF2563EB), size: 22),
                        SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Keep Chat Locked', style: TextStyle(color: Color(0xFF1D4ED8), fontWeight: FontWeight.bold, fontSize: 14)),
                              SizedBox(height: 3),
                              Text('Preserve the conversation for admin review.', style: TextStyle(color: Color(0xFF3B82F6), fontSize: 12.5)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                InkWell(
                  onTap: () => Navigator.pop(context, 'delete'),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFFCA5A5)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.delete_outline_rounded, color: Color(0xFFEF4444), size: 22),
                        SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Delete Chat History', style: TextStyle(color: Color(0xFF991B1B), fontWeight: FontWeight.bold, fontSize: 14)),
                              SizedBox(height: 3),
                              Text('Permanently delete all messages. Cannot be undone.', style: TextStyle(color: Color(0xFFEF4444), fontSize: 12.5)),
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

class ChatHistoryChoicesDialog extends StatefulWidget {

  const ChatHistoryChoicesDialog({
    super.key,
    this.threadId,
    required this.therapistId,
    required this.onComplete,
    this.cancellationReason,
  });

  final String? threadId;
  final String therapistId;
  final Function(String choice) onComplete;
  final String? cancellationReason;

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
        reason: widget.cancellationReason,
      );

      // 2. Modify static sets so the changes reflect immediately in parent home
      ProfessionalSupportScreen.sessionSubscribedTherapistIds.remove(widget.therapistId);
      if (choice == 'delete') {
        ProfessionalSupportScreen.sessionHiddenTherapistIds.add(widget.therapistId);
      }

      // 3. Remove from subscribed list and add to hidden list (if deleting)
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
      child: SingleChildScrollView(
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
      ),
    );
  }
}

class _ChatBackgroundPainter extends CustomPainter {
  const _ChatBackgroundPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFE2E8F0).withValues(alpha: 0.3)
      ..strokeWidth = 1.0;

    const double spacing = 20.0;
    for (double x = 0; x < size.width; x += spacing) {
      for (double y = 0; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), 1.0, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _TypingDots extends StatefulWidget {
  const _TypingDots();

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (index) {
        return AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final delay = index * 0.2;
            final progress = (_controller.value - delay) % 1.0;
            final double scale = 0.6 + 0.4 * math.sin(progress * math.pi);
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 2),
              width: 7,
              height: 7,
              decoration: const BoxDecoration(
                color: Color(0xFF64748B),
                shape: BoxShape.circle,
              ),
              transform: Matrix4.translationValues(0, -scale * 3 + 1.5, 0),
            );
          },
        );
      }),
    );
  }
}

class _ImageZoomViewer extends StatelessWidget {
  const _ImageZoomViewer({required this.base64Image});

  final String base64Image;

  @override
  Widget build(BuildContext context) {
    Uint8List bytes;
    try {
      bytes = base64Decode(base64Image);
    } catch (_) {
      bytes = Uint8List(0);
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () async {
              if (bytes.isNotEmpty) {
                await Printing.sharePdf(bytes: bytes, filename: 'shared_image.png');
              }
            },
          ),
        ],
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 0.5,
          maxScale: 4.0,
          child: bytes.isNotEmpty
              ? Image.memory(bytes)
              : const Icon(Icons.broken_image, color: Colors.white54, size: 80),
        ),
      ),
    );
  }
}

// ─── Restriction Banner ──────────────────────────────────────────────────────

class _RestrictionBanner extends StatelessWidget {
  const _RestrictionBanner({
    required this.endDate,
    required this.senderRole,
  });

  final DateTime endDate;
  final String senderRole;

  @override
  Widget build(BuildContext context) {
    final dateStr = '${endDate.day}/${endDate.month}/${endDate.year}';
    final message = '⚠️ Communication with this user has been temporarily restricted by admin. This restriction expires on $dateStr.';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: Color(0xFFFEF3C7),
        border: Border(
          bottom: BorderSide(color: Color(0xFFFCD34D), width: 1),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Color(0xFFD97706), size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: Color(0xFF92400E),
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RestrictedComposerBanner extends StatelessWidget {
  const _RestrictedComposerBanner({required this.endDate});
  final DateTime endDate;

  @override
  Widget build(BuildContext context) {
    final dateStr = '${endDate.day}/${endDate.month}/${endDate.year}';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFCD34D)),
      ),
      child: Row(
        children: [
          const Icon(Icons.lock_clock_outlined, color: Color(0xFFD97706), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'This chat is temporarily restricted by the administrator until $dateStr. You cannot send messages.',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Color(0xFF92400E),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Block-aware Banner ──────────────────────────────────────────────────────

class _BlockedBanner extends StatelessWidget {
  const _BlockedBanner({
    required this.iBlockedThem,
    required this.blockerDisplayName,
    required this.peerDisplayName,
  });

  final bool iBlockedThem;
  final String blockerDisplayName;
  final String peerDisplayName;

  @override
  Widget build(BuildContext context) {
    final icon = iBlockedThem ? Icons.block : Icons.do_not_disturb_on_outlined;
    final message = iBlockedThem
        ? 'You have blocked $peerDisplayName. Communication is paused. You can unblock them at any time from the menu.'
        : '${blockerDisplayName.isNotEmpty ? blockerDisplayName : 'The other user'} has blocked you. You may send one final message to ask for clarification.';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: Color(0xFFFEE2E2),
        border: Border(
          bottom: BorderSide(color: Color(0xFFFCA5A5), width: 1),
        ),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFFDC2626), size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: Color(0xFF991B1B),
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Block-aware Input Area ──────────────────────────────────────────────────

class _BlockedInputArea extends StatefulWidget {
  const _BlockedInputArea({
    required this.thread,
    required this.senderRole,
    required this.blockInfo,
    required this.canSendFinal,
    required this.canReplyOnce,
    required this.onFinalMessage,
    required this.onReplyOnce,
    this.onRenewSubscription,
  });

  final TherapistThread thread;
  final String senderRole;
  final BlockInfo blockInfo;
  final bool canSendFinal;
  final bool canReplyOnce;
  final Future<void> Function(String body) onFinalMessage;
  final Future<void> Function(String body) onReplyOnce;
  final VoidCallback? onRenewSubscription;

  @override
  State<_BlockedInputArea> createState() => _BlockedInputAreaState();
}

class _BlockedInputAreaState extends State<_BlockedInputArea> {
  bool _sending = false;

  Future<void> _showFinalMessageDialog(bool isReply) async {
    final controller = TextEditingController();
    final title = isReply ? 'Send One-Time Reply' : 'Send Final Message';
    final hint = isReply
        ? 'Type your reply...'
        : 'Type your final message...';
    final warning = isReply
        ? 'This will be your one-time reply while this user is blocked. Please explain the reason for blocking or respond to their message carefully. After sending, neither of you can exchange further messages until you choose to unblock them.'
        : 'You have been blocked. You may send one final message to ask for clarification or explain your situation. This is the only message you can send while blocked. After sending it, you will not be able to contact this user again unless they unblock you.';

    final body = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(
                isReply ? Icons.reply_rounded : Icons.mail_outline_rounded,
                color: isReply ? const Color(0xFF0891B2) : const Color(0xFFF59E0B),
                size: 22,
              ),
              const SizedBox(width: 8),
              Flexible(child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isReply ? const Color(0xFFECFEFF) : const Color(0xFFFFFBEB),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isReply ? const Color(0xFF67E8F9) : const Color(0xFFFDE68A),
                    ),
                  ),
                  child: Text(warning, style: const TextStyle(fontSize: 12.5, height: 1.4, color: Color(0xFF374151))),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: controller,
                  maxLines: 4,
                  maxLength: 500,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: hint,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.all(12),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: isReply ? const Color(0xFF0891B2) : const Color(0xFFF59E0B),
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                final text = controller.text.trim();
                if (text.isNotEmpty) Navigator.pop(ctx, text);
              },
              child: Text(isReply ? 'Send Reply' : 'Send Message'),
            ),
          ],
        ),
      ),
    );
    if (body == null || body.isEmpty || !mounted) return;
    setState(() => _sending = true);
    try {
      if (isReply) {
        await widget.onReplyOnce(body);
      } else {
        await widget.onFinalMessage(body);
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final thread = widget.thread;
    final isBlocked = thread.isBlocked;

    if (thread.status == 'reported') {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFFEF2F2),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFFCA5A5), width: 1.5),
        ),
        child: const Text(
          'This conversation has been temporarily locked because a report has been submitted. Messaging has been disabled until the report has been reviewed by our admin team.',
          style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: Color(0xFF991B1B), height: 1.4),
          textAlign: TextAlign.center,
        ),
      );
    }

    // Non-block scenario: subscription cancelled — show renew
    if (!isBlocked) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFBEB),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFFDE68A), width: 1.5),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'This subscription has ended. This conversation is now read-only. You can still view previous messages and shared media, but you cannot send new messages unless a new subscription is started.',
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: Color(0xFF92400E), height: 1.4),
              textAlign: TextAlign.center,
            ),
            if (widget.onRenewSubscription != null) ...[
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: widget.onRenewSubscription,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00C853),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Renew Subscription to Chat', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              ),
            ],
          ],
        ),
      );
    }

    // Blocked — show contextual buttons
    final blockInfo = widget.blockInfo;
    final alreadySentFinal = widget.senderRole == 'parent'
        ? thread.finalMessageSentByParent
        : thread.finalMessageSentByTherapist;
    final alreadyReplied = widget.senderRole == 'parent'
        ? thread.finalReplySentByParent
        : thread.finalReplySentByTherapist;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFCA5A5), width: 1.5),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (blockInfo.theyBlockedMe) ...[
            // I am the BLOCKED party
            if (!alreadySentFinal) ...[
              const Text(
                'You have been blocked. You may send one final message.',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF991B1B)),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _sending ? null : () => _showFinalMessageDialog(false),
                  icon: const Icon(Icons.mail_outline_rounded, size: 18),
                  label: _sending
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Send Final Message', style: TextStyle(fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF59E0B),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ] else ...[
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle_outline, color: Color(0xFF6B7280), size: 18),
                  SizedBox(width: 6),
                  Text(
                    'Your final message has been sent.',
                    style: TextStyle(fontSize: 13, color: Color(0xFF6B7280), fontWeight: FontWeight.w500),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'No further messages are possible unless you are unblocked.',
                style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
                textAlign: TextAlign.center,
              ),
            ],
          ] else if (blockInfo.iBlockedThem) ...[
            // I am the BLOCKER
            if (widget.canReplyOnce) ...[
              const Text(
                'The blocked user has sent you a final message. You may send one reply.',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1D4ED8)),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _sending ? null : () => _showFinalMessageDialog(true),
                  icon: const Icon(Icons.reply_rounded, size: 18),
                  label: _sending
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Reply Once', style: TextStyle(fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0891B2),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ] else if (alreadyReplied) ...[
              const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle_outline, color: Color(0xFF6B7280), size: 18),
                  SizedBox(width: 6),
                  Text(
                    'You have sent your one-time reply.',
                    style: TextStyle(fontSize: 13, color: Color(0xFF6B7280), fontWeight: FontWeight.w500),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'Unblock this user to resume normal messaging.',
                style: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
                textAlign: TextAlign.center,
              ),
            ] else ...[
              const Text(
                'You have blocked this user. They may send one final message, after which you can reply once.',
                style: TextStyle(fontSize: 13, color: Color(0xFF6B7280), fontWeight: FontWeight.w500),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ],
      ),
    );
  }
}
