import 'package:flutter/material.dart';
import '../utils/app_colors.dart';
import '../widgets/wave_background.dart';
import 'communication_info_screen.dart';
import 'learning_play_info_screen.dart';

class ChildProfileScreen extends StatefulWidget {
  final String firstName;
  final String lastName;
  final String email;
  final String phone;
  final String password;

  const ChildProfileScreen({
    super.key,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.phone,
    required this.password,
  });

  @override
  State<ChildProfileScreen> createState() => _ChildProfileScreenState();
}

class _ChildProfileScreenState extends State<ChildProfileScreen>
    with SingleTickerProviderStateMixin {
  final _nameController = TextEditingController();
  bool _isCommunicationSelected = false;
  bool _isLearningSelected = false;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeIn),
    );
    _animationController.forward();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  void _handleContinue() {
    if (_nameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill in all fields'),
          backgroundColor: AppColors.errorRed,
        ),
      );
      return;
    }
    if (_nameController.text.trim().length > 50) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Child name must not exceed 50 characters'),
          backgroundColor: AppColors.errorRed,
        ),
      );
      return;
    }
    if (!_isCommunicationSelected && !_isLearningSelected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select at least one support area'),
          backgroundColor: AppColors.errorRed,
        ),
      );
      return;
    }
    final List<String> supportArea = [];
    if (_isCommunicationSelected) supportArea.add('Communication');
    if (_isLearningSelected) supportArea.add('Learning & Play');
    Navigator.pop(context, {
      'childName': _nameController.text.trim(),
      'SupportArea': supportArea,
    });
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    final bool isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // Top wave
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: ClipPath(
              clipper: WaveClipper(),
              child: Container(
                height: screenHeight * 0.35,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppColors.primaryBlue, AppColors.lightBlue],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
            ),
          ),

          // Bottom wave
          if (!isKeyboardOpen)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: ClipPath(
                clipper: BottomWaveClipper(),
                child: Container(
                  height: 150,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [AppColors.lightBlue, AppColors.primaryBlue],
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                    ),
                  ),
                ),
              ),
            ),

          // Decorative shapes
          if (!isKeyboardOpen) ...[
            Positioned(
              bottom: 34,
              left: 44,
              child: Container(width: 20, height: 20, color: AppColors.yellow),
            ),
            Positioned(
              bottom: 54,
              left: 100,
              child: const Icon(Icons.star, color: AppColors.pink, size: 24),
            ),
            Positioned(
              bottom: 20,
              right: 152,
              child: CustomPaint(
                size: const Size(20, 20),
                painter: TrianglePainter(color: AppColors.red),
              ),
            ),
            Positioned(
              bottom: 10,
              right: 44,
              child: Container(
                width: 16,
                height: 16,
                decoration: const BoxDecoration(
                  color: AppColors.green,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ],

          // Main content
          SafeArea(
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: Column(
                children: [
                // Header
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: const Text(
                    'Child Profile',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                      color: Color.fromARGB(221, 0, 0, 0),
                    ),
                  ),
                ),

                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 30),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(height: screenHeight * 0.05),

                        // Child's Information Title
                        const Text(
                          "Child's Information",
                          style: TextStyle(
                            fontSize: 25,
                            fontWeight: FontWeight.w600,
                            color: Color.fromARGB(255, 0, 0, 0),
                          ),
                        ),
                        const SizedBox(height: 50),

                        // Child's Name
                        const Text(
                          "Child's Name",
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                            color: AppColors.darkBlue,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFFF4F7FB),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFD2DCE6)),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFB0C4DE).withValues(alpha: 0.4),
                                blurRadius: 8,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: TextField(
                            controller: _nameController,
                            maxLength: 50,
                            style: const TextStyle(color: Color(0xFF212121)),
                            buildCounter: (context, {required currentLength, required maxLength, required isFocused}) {
                              return Text(
                                '$currentLength/$maxLength',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppColors.textGrey,
                                ),
                              );
                            },
                            decoration: const InputDecoration(
                              hintText: 'Leo',
                              hintStyle: TextStyle(color: Color(0xFF212121)),
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.only(
                                left: 16,
                                right: 16,
                                top: 14,
                                bottom: 0,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Support Areas Section
                        const Text(
                          "Support Areas for Your Child",
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                            color: AppColors.darkBlue,
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Communication Card
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              _isCommunicationSelected = !_isCommunicationSelected;
                            });
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              color: AppColors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: _isCommunicationSelected
                                    ? AppColors.orange
                                    : AppColors.textGrey.withValues(alpha: 0.3),
                              ),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  "Communication",
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF212121)
                                  ),
                                ),
                                Row(
                                  children: [
                                    GestureDetector(
                                      onTap: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) => const CommunicationInfoScreen(),
                                          ),
                                        );
                                      },
                                      child: const Icon(Icons.info_outline, size: 18),
                                    ),
                                    const SizedBox(width: 8),
                                    _isCommunicationSelected
                                        ? const Icon(Icons.check_box, color: AppColors.orange)
                                        : const Icon(Icons.check_box_outline_blank, color: AppColors.textGrey),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Learning & Play Card
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              _isLearningSelected = !_isLearningSelected;
                            });
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              color: AppColors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: _isLearningSelected
                                    ? AppColors.orange
                                    : AppColors.textGrey.withValues(alpha: 0.3),
                              ),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  "Learning & Play",
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF212121),
                                  ),
                                ),
                                Row(
                                  children: [
                                    GestureDetector(
                                      onTap: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) => const LearningPlayInfoScreen(),
                                          ),
                                        );
                                      },
                                      child: const Icon(Icons.info_outline, size: 18),
                                    ),
                                    const SizedBox(width: 8),
                                    _isLearningSelected
                                        ? const Icon(Icons.check_box, color: AppColors.orange)
                                        : const Icon(Icons.check_box_outline_blank, color: AppColors.textGrey),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 40),

                        // Continue Button
                        Container(
                          width: double.infinity,
                          height: 55,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [AppColors.orange, AppColors.orangeDark],
                              begin: Alignment.centerLeft,
                              end: Alignment.centerRight,
                            ),
                            borderRadius: BorderRadius.circular(30),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.orangeDark.withValues(alpha: 0.4),
                                blurRadius: 12,
                                offset: const Offset(0, 6),
                              ),
                            ],
                          ),
                          child: ElevatedButton(
                            onPressed: () => _handleContinue(),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.transparent,
                              shadowColor: Colors.transparent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(30),
                              ),
                              elevation: 0,
                            ),
                            child: const Text(
                              'Save Child Profile',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: AppColors.white,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
  }
}
