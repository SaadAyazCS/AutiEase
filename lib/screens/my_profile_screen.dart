import 'package:flutter/material.dart';

import '../models/app_models.dart';
import '../repositories/app_repositories.dart';
import '../utils/app_colors.dart';
import '../widgets/figma_module_scaffold.dart';
import '../widgets/session_guard.dart';

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
  bool _communicationEnabled = false;
  bool _learningEnabled = false;
  bool _isSaving = false;
  UserProfile? _profile;
  ChildProfile? _child;
  String? _loadError;

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
    if (_profile == null) {
      return;
    }
    setState(() => _isSaving = true);
    await AppRepositories.users.updateCurrentUser({
      'firstName': _firstNameController.text.trim(),
      'lastName': _lastNameController.text.trim(),
      'phone': _phoneController.text.trim(),
    });
    if (_child != null) {
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
    setState(() => _isSaving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Profile saved to Firestore'),
        backgroundColor: Colors.green,
      ),
    );
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _childNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isParent = _profile?.role == 'parent';
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
                    'Unable to load profile right now.\n\n$_loadError',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : _profile == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 170),
                children: [
                  _SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildLabel('First Name'),
                        _buildField(_firstNameController),
                        _buildLabel('Last Name'),
                        _buildField(_lastNameController),
                        _buildLabel('Phone'),
                        _buildField(_phoneController),
                        _buildLabel('Email'),
                        _buildField(_emailController, enabled: false),
                      ],
                    ),
                  ),
                  if (isParent) ...[
                    const SizedBox(height: 14),
                    _SectionCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Child Profile',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1A2D4B),
                            ),
                          ),
                          const SizedBox(height: 12),
                          _buildLabel('Child Name'),
                          _buildField(_childNameController),
                          SwitchListTile(
                            value: _communicationEnabled,
                            onChanged: (value) {
                              setState(() => _communicationEnabled = value);
                            },
                            title: const Text('Communication enabled'),
                            contentPadding: EdgeInsets.zero,
                          ),
                          SwitchListTile(
                            value: _learningEnabled,
                            onChanged: (value) {
                              setState(() => _learningEnabled = value);
                            },
                            title: const Text('Learning enabled'),
                            contentPadding: EdgeInsets.zero,
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  ElevatedButton(
                    onPressed: _isSaving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryBlue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    child: _isSaving
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text('Save changes'),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 12),
      child: Text(
        label,
        style: const TextStyle(
          fontWeight: FontWeight.w600,
          color: Color(0xFF223651),
        ),
      ),
    );
  }

  Widget _buildField(TextEditingController controller, {bool enabled = true}) {
    return TextField(
      controller: controller,
      enabled: enabled,
      decoration: InputDecoration(
        filled: true,
        fillColor: enabled ? const Color(0xFFF8FAFC) : const Color(0xFFE2E8F0),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }
}
