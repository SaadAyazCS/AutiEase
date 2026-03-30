import 'package:flutter/material.dart';

import '../services/firebase_service.dart';
import '../widgets/figma_module_scaffold.dart';
import '../widgets/session_guard.dart';

class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({super.key});

  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _feedbackController = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    try {
      final userData = await FirebaseService().getCurrentUserData();
      if (userData != null) {
        _nameController.text =
            '${userData['firstName'] ?? ''} ${userData['lastName'] ?? ''}'
                .trim();
        _emailController.text = userData['email'] ?? '';
      }
    } catch (_) {}
  }

  Future<void> _submitFeedback() async {
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final feedback = _feedbackController.text.trim();
    if (name.isEmpty || email.isEmpty || feedback.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please fill all fields.')));
      return;
    }

    setState(() => _isLoading = true);
    try {
      await FirebaseService().submitFeedback(
        name: name,
        email: email,
        feedback: feedback,
      );
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Thank you for your feedback!'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error submitting feedback: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _feedbackController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SessionGuard(
      role: SessionGuardRole.authenticated,
      child: FigmaModuleScaffold(
        title: 'Feedback',
        onBack: () => Navigator.pop(context),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(bottomRight: Radius.circular(38)),
          ),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(14, 24, 14, 170),
            children: [
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 2),
                child: Text(
                  'We value your feedback! Please share your thoughts to help us improve.',
                  style: TextStyle(
                    fontSize: 18 / 1.2,
                    color: Color(0xFF1E1E1E),
                    height: 1.5,
                  ),
                ),
              ),
              const SizedBox(height: 18),
              _buildLabel('Your Name'),
              _buildField(_nameController),
              const SizedBox(height: 10),
              _buildLabel('Email'),
              _buildField(_emailController),
              const SizedBox(height: 10),
              _buildLabel('Write Your Feedback Here'),
              _buildField(_feedbackController, maxLines: 7),
              const SizedBox(height: 18),
              ElevatedButton(
                onPressed: _isLoading ? null : _submitFeedback,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF4EA9E3),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Submit Feedback',
                        style: TextStyle(
                          fontSize: 18 / 1.2,
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

  Widget _buildLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 32 / 1.5,
        fontWeight: FontWeight.w700,
        color: Color(0xFF1E1E1E),
      ),
    );
  }

  Widget _buildField(TextEditingController controller, {int maxLines = 1}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFD8DDE7)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        decoration: const InputDecoration(
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
      ),
    );
  }
}
