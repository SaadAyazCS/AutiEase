import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/app_models.dart';
import '../repositories/app_repositories.dart';
import '../services/firebase_service.dart';
import '../services/play_preferences_service.dart';
import '../widgets/figma_module_scaffold.dart';
import '../widgets/session_guard.dart';
import 'communication_info_screen.dart';
import 'learning_play_info_screen.dart';

enum _ProfileTab { parent, child }

class MyProfileScreen extends StatefulWidget {
  const MyProfileScreen({super.key});

  @override
  State<MyProfileScreen> createState() => _MyProfileScreenState();
}

class _MyProfileScreenState extends State<MyProfileScreen> {
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _childNameController = TextEditingController();
  final _savedPasswordDisplay = TextEditingController(text: '************');
  final _newPasswordController = TextEditingController();
  final FirebaseService _firebaseService = FirebaseService();
  final PlayPreferencesService _playPreferencesService =
      const PlayPreferencesService();

  bool _communicationEnabled = false;
  bool _learningEnabled = false;
  bool _isSaving = false;
  bool _revealSavedPassword = false;
  bool _obscureNewPassword = true;
  UserProfile? _profile;
  ChildProfile? _child;
  PlayPreferences _playPreferences = PlayPreferences.defaults;
  String? _loadError;
  _ProfileTab _activeTab = _ProfileTab.parent;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final profile = await AppRepositories.users.getCurrentUserProfile();
      ChildProfile? child;
      if (profile?.role == 'parent') {
        child = await AppRepositories.users.getActiveChildForCurrentParent();
      }

      _profile = profile;
      _child = child;

      if (_profile != null) {
        _firstNameController.text = _profile!.firstName;
        _lastNameController.text = _profile!.lastName;
        _emailController.text = _profile!.email;
        _phoneController.text = _profile!.phone;
        _playPreferences = PlayPreferences.fromMap(_profile!.playSettings);
      }
      if (_child != null) {
        _childNameController.text = _child!.name;
        _communicationEnabled = _child!.supportAreas.contains('Communication');
        _learningEnabled =
            _child!.supportAreas.contains('Learning & Play') ||
            _child!.supportAreas.contains('Learning');
      }
      _loadError = null;
    } catch (error) {
      _loadError = error.toString();
    }

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _save() async {
    if (_profile == null || _isSaving) {
      return;
    }
    setState(() => _isSaving = true);
    try {
      if (_activeTab == _ProfileTab.parent) {
        final firstName = _firstNameController.text.trim();
        final lastName = _lastNameController.text.trim();
        final fullName = '$firstName $lastName'.trim();
        final newPassword = _newPasswordController.text.trim();

        if (newPassword.isNotEmpty) {
          final passwordError = _validatePassword(newPassword);
          if (passwordError.isNotEmpty) {
            if (!mounted) {
              return;
            }
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(passwordError)));
            return;
          }
        }

        await AppRepositories.users.updateCurrentUser({
          'firstName': firstName,
          'lastName': lastName,
          'fullName': fullName,
          'phone': _phoneController.text.trim(),
        });
        final authUser = FirebaseAuth.instance.currentUser;
        if (authUser != null &&
            fullName.isNotEmpty &&
            authUser.displayName?.trim() != fullName) {
          try {
            await authUser.updateDisplayName(fullName);
          } catch (_) {
            // Ignore auth profile update failures; Firestore remains source of truth.
          }
        }

        if (newPassword.isNotEmpty) {
          final result = await _firebaseService.updateCurrentUserPassword(
            newPassword: newPassword,
          );
          if (result['success'] != true) {
            if (!mounted) {
              return;
            }
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  result['message']?.toString() ?? 'Failed to update password.',
                ),
              ),
            );
            return;
          }
          _newPasswordController.clear();
        }
      } else if (_child != null) {
        if (!_communicationEnabled && !_learningEnabled) {
          if (!mounted) {
            return;
          }
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Please keep at least one support area enabled for your child.',
              ),
            ),
          );
          return;
        }
        await AppRepositories.users.upsertChildProfile(
          ChildProfile(
            id: _child!.id,
            parentId: _child!.parentId,
            name: _childNameController.text.trim(),
            avatar: _child!.avatar,
            supportAreas: [
              if (_communicationEnabled) 'Communication',
              if (_learningEnabled) 'Learning & Play',
            ],
            status: _child!.status,
            activePlanId: _child!.activePlanId,
            createdAt: _child!.createdAt,
            updatedAt: DateTime.now(),
          ),
        );
      }

      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _activeTab == _ProfileTab.parent
                ? 'Parent profile updated'
                : 'Child profile updated',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _showPlayPreferencesDialog() async {
    var draft = _playPreferences;
    final saved = await showDialog<PlayPreferences>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text(
                'Learning game preferences',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
              ),
              content: SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Choose how challenging the learning games should be.',
                        style: TextStyle(fontSize: 14, height: 1.35),
                      ),
                      const SizedBox(height: 14),
                      for (final difficulty in ParentDifficulty.values) ...[
                        _DifficultyChoiceTile(
                          difficulty: difficulty,
                          selected: draft.difficulty == difficulty,
                          onTap: () {
                            setDialogState(() {
                              draft = draft.copyWith(difficulty: difficulty);
                            });
                          },
                        ),
                        const SizedBox(height: 8),
                      ],
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF4F8FB),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFD4DCE5)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Low stimulation mode',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF1F2C45),
                                    ),
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    'Calmer transitions, fewer moving objects, and lighter celebrations.',
                                    style: TextStyle(
                                      fontSize: 13,
                                      height: 1.3,
                                      color: Color(0xFF556070),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Switch(
                              value: draft.lowStimulationMode,
                              onChanged: (value) {
                                setDialogState(() {
                                  draft = draft.copyWith(
                                    lowStimulationMode: value,
                                  );
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, draft),
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    if (saved == null) {
      return;
    }
    await _playPreferencesService.save(saved);
    if (!mounted) {
      return;
    }
    setState(() => _playPreferences = saved);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Learning game preferences saved.')),
    );
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _childNameController.dispose();
    _savedPasswordDisplay.dispose();
    _newPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canShowChildTab = _profile?.role == 'parent';
    return SessionGuard(
      role: SessionGuardRole.authenticated,
      child: FigmaModuleScaffold(
        title: 'My Profile',
        onBack: () => Navigator.pop(context),
        child: _loadError != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Unable to load profile.\n\n$_loadError',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : _profile == null
            ? const Center(child: CircularProgressIndicator())
            : Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.only(
                    bottomRight: Radius.circular(38),
                  ),
                ),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 170),
                  children: [
                    _TabSelector(
                      activeTab: _activeTab,
                      canShowChild: canShowChildTab,
                      onTabChange: (tab) {
                        setState(() => _activeTab = tab);
                      },
                    ),
                    const SizedBox(height: 16),
                    if (_activeTab == _ProfileTab.parent || !canShowChildTab)
                      _buildParentSection()
                    else
                      _buildChildSection(),
                    const SizedBox(height: 18),
                    ElevatedButton(
                      onPressed: _isSaving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4EA9E3),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              _activeTab == _ProfileTab.parent
                                  ? 'Save Parent Changes'
                                  : 'Save Child Changes',
                              style: const TextStyle(
                                fontSize: 19 / 1.2,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildParentSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Parent Details',
          style: TextStyle(
            fontSize: 36 / 1.5,
            fontWeight: FontWeight.w700,
            color: Color(0xFF2A456F),
          ),
        ),
        const SizedBox(height: 6),
        Container(height: 1, color: const Color(0xFFD8DEE8)),
        const SizedBox(height: 10),
        _buildLabel('First Name'),
        _buildField(_firstNameController),
        _buildLabel('Last Name'),
        _buildField(_lastNameController),
        _buildLabel('Email'),
        _buildField(_emailController, readOnly: true),
        _buildLabel('Phone Number'),
        _buildField(_phoneController),
        _buildLabel('Current password'),
        ..._savedPasswordWidgets(),
        _buildLabel('New password (optional)'),
        _buildField(
          _newPasswordController,
          obscureText: _obscureNewPassword,
          trailing: IconButton(
            onPressed: () {
              setState(() => _obscureNewPassword = !_obscureNewPassword);
            },
            icon: Icon(
              _obscureNewPassword ? Icons.visibility_off : Icons.visibility,
              color: const Color(0xFF556070),
            ),
          ),
        ),
      ],
    );
  }

  static const String _savedPasswordRevealMessageParent =
      'Your actual password is not displayed on this screen for security. Tap the eye to hide again. Use the field below only when you want to set a new password.';

  bool _parentHasEmailPassword() =>
      FirebaseAuth.instance.currentUser?.providerData.any(
        (provider) => provider.providerId == 'password',
      ) ??
      false;

  void _toggleParentSavedPasswordVisibility() {
    setState(() {
      _revealSavedPassword = !_revealSavedPassword;
      _savedPasswordDisplay.text = _revealSavedPassword
          ? _savedPasswordRevealMessageParent
          : '************';
    });
  }

  List<Widget> _savedPasswordWidgets() {
    if (!_parentHasEmailPassword()) {
      return [
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text(
            'You signed in with Google. Your password is managed through your Google account.',
            style: TextStyle(
              fontSize: 12,
              color: Color(0xFF556070),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ];
    }

    return [
      _buildField(
        _savedPasswordDisplay,
        readOnly: true,
        obscureText: !_revealSavedPassword,
        trailing: IconButton(
          onPressed: _toggleParentSavedPasswordVisibility,
          icon: Icon(
            _revealSavedPassword ? Icons.visibility_off : Icons.visibility,
            color: const Color(0xFF556070),
          ),
        ),
      ),
      const SizedBox(height: 12),
    ];
  }

  Widget _buildChildSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Child\'s Information',
          style: TextStyle(
            fontSize: 36 / 1.5,
            fontWeight: FontWeight.w700,
            color: Color(0xFF2A456F),
          ),
        ),
        const SizedBox(height: 10),
        _buildLabel('Child\'s Name'),
        _buildField(_childNameController),
        const SizedBox(height: 8),
        const Text(
          'Support Areas for Your Child',
          style: TextStyle(
            fontSize: 34 / 1.5,
            fontWeight: FontWeight.w700,
            color: Color(0xFF2A456F),
          ),
        ),
        const SizedBox(height: 10),
        _supportAreaTile(
          label: 'Communication',
          selected: _communicationEnabled,
          onToggle: () => setState(() {
            _communicationEnabled = !_communicationEnabled;
          }),
        ),
        const SizedBox(height: 8),
        _supportAreaTile(
          label: 'Learning & Play',
          selected: _learningEnabled,
          onToggle: () => setState(() {
            _learningEnabled = !_learningEnabled;
          }),
        ),
        const SizedBox(height: 12),
        _learningGamePreferencesTile(),
      ],
    );
  }

  Widget _learningGamePreferencesTile() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _showPlayPreferencesDialog,
        borderRadius: BorderRadius.circular(10),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFF7FBFE),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFD4DCE5)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              const Icon(Icons.tune_rounded, color: Color(0xFF2A456F)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Learning game preferences',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF2A456F),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${_playPreferences.difficulty.label}'
                      '${_playPreferences.lowStimulationMode ? ' • Low stimulation' : ''}',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF556070),
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }

  Widget _supportAreaTile({
    required String label,
    required bool selected,
    required VoidCallback onToggle,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(10),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? const Color(0xFF4EA9E3)
                  : const Color(0xFFDBE1EA),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 32 / 1.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF2A456F),
                  ),
                ),
              ),
              InkWell(
                borderRadius: BorderRadius.circular(999),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => label == 'Communication'
                          ? const CommunicationInfoScreen()
                          : const LearningPlayInfoScreen(),
                    ),
                  );
                },
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.info_outline_rounded, size: 22),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 16),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: Color(0xFF1E293B),
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  Widget _buildField(
    TextEditingController controller, {
    bool enabled = true,
    bool readOnly = false,
    bool obscureText = false,
    Widget? trailing,
  }) {
    final inert = !enabled || readOnly;
    return Container(
      decoration: BoxDecoration(
        color: inert ? const Color(0xFFF8FAFC) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          if (!inert)
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
        ],
      ),
      child: TextField(
        controller: controller,
        enabled: enabled,
        readOnly: readOnly,
        obscureText: obscureText,
        style: TextStyle(
          fontSize: 16,
          color: inert ? const Color(0xFF64748B) : const Color(0xFF0F172A),
          fontWeight: FontWeight.w500,
        ),
        decoration: InputDecoration(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
          filled: true,
          fillColor: Colors.transparent,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE2E8F0), width: 1.5),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF4EA9E3), width: 2),
          ),
          disabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE2E8F0), width: 1),
          ),
          suffixIcon: trailing,
        ),
      ),
    );
  }

  String _validatePassword(String password) {
    if (password.length < 6) {
      return 'Password must be at least 6 characters long';
    }
    if (!password.contains(RegExp(r'[A-Z]'))) {
      return 'Password must contain at least one uppercase letter for strong password';
    }
    if (!password.contains(RegExp(r'[a-z]'))) {
      return 'Password must contain at least one lowercase letter for strong password';
    }
    if (!password.contains(RegExp(r'[0-9]'))) {
      return 'Password must contain at least one number for strong password';
    }
    return '';
  }
}

class _DifficultyChoiceTile extends StatelessWidget {
  const _DifficultyChoiceTile({
    required this.difficulty,
    required this.selected,
    required this.onTap,
  });

  final ParentDifficulty difficulty;
  final bool selected;
  final VoidCallback onTap;

  String get _description {
    return switch (difficulty) {
      ParentDifficulty.easy => 'Fewer choices and shorter hold games.',
      ParentDifficulty.normal => 'Balanced object count and challenge.',
      ParentDifficulty.challenge =>
        'More choices, distractors, and longer hold games.',
    };
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFEAF6FF) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected
                  ? const Color(0xFF4EA9E3)
                  : const Color(0xFFD4DCE5),
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: selected
                    ? const Color(0xFF187C9A)
                    : const Color(0xFF7A8495),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      difficulty.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1F2C45),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _description,
                      style: const TextStyle(
                        fontSize: 12,
                        height: 1.25,
                        color: Color(0xFF556070),
                      ),
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

class _TabSelector extends StatelessWidget {
  const _TabSelector({
    required this.activeTab,
    required this.canShowChild,
    required this.onTabChange,
  });

  final _ProfileTab activeTab;
  final bool canShowChild;
  final ValueChanged<_ProfileTab> onTabChange;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: const Color(0xFFE8EFF3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD4DCE5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _tabButton(
              label: 'Parent',
              selected: activeTab == _ProfileTab.parent,
              onTap: () => onTabChange(_ProfileTab.parent),
            ),
          ),
          Expanded(
            child: _tabButton(
              label: 'Child',
              selected: activeTab == _ProfileTab.child,
              onTap: canShowChild ? () => onTabChange(_ProfileTab.child) : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabButton({
    required String label,
    required bool selected,
    required VoidCallback? onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: selected
              ? Border.all(color: const Color(0xFFD4DCE5))
              : Border.all(color: Colors.transparent),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 30 / 1.5,
            fontWeight: FontWeight.w700,
            color: onTap == null
                ? const Color(0xFFB0B8C5)
                : const Color(0xFF2A456F),
          ),
        ),
      ),
    );
  }
}
