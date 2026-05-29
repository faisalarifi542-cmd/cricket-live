import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../widgets/custom_header.dart';
import '../widgets/glass_card.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _nameController = TextEditingController(text: 'Arjun Reddy');
  final _emailController = TextEditingController(text: 'arjun.reddy@email.com');
  final _phoneController = TextEditingController(text: '+91 98765 43210');
  String _favTeam = 'SRH';

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: const BoxDecoration(gradient: AppColors.backgroundGradient),
        child: SafeArea(
          child: Column(
            children: [
              const CustomHeader(showBackButton: true),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 8),
                      const Text('Edit Profile', style: TextStyle(color: AppColors.textPrimary, fontSize: 22, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 20),
                      // Avatar
                      Center(
                        child: Stack(
                          children: [
                            Container(
                              width: 90,
                              height: 90,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(colors: [AppColors.blue.withOpacity(0.4), AppColors.cyan.withOpacity(0.2)]),
                                border: Border.all(color: AppColors.cyan.withOpacity(0.5), width: 2),
                              ),
                              child: const Icon(Icons.person, color: Colors.white, size: 44),
                            ),
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Container(
                                width: 30,
                                height: 30,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: AppColors.blue,
                                  border: Border.all(color: AppColors.primaryBg, width: 2),
                                ),
                                child: const Icon(Icons.camera_alt, color: Colors.white, size: 14),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      _buildField('Full Name', _nameController, Icons.person_outline),
                      const SizedBox(height: 12),
                      _buildField('Email', _emailController, Icons.email_outlined),
                      const SizedBox(height: 12),
                      _buildField('Phone', _phoneController, Icons.phone_outlined),
                      const SizedBox(height: 12),
                      // Fav team dropdown
                      GlassCard(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                        borderRadius: 14,
                        child: Row(
                          children: [
                            const Icon(Icons.shield_outlined, color: AppColors.textMuted, size: 20),
                            const SizedBox(width: 12),
                            Expanded(
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: _favTeam,
                                  dropdownColor: AppColors.cardBg,
                                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                                  items: ['SRH', 'CSK', 'MI', 'RCB', 'KKR', 'DC', 'RR', 'PBKS', 'LSG', 'GT']
                                      .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                                      .toList(),
                                  onChanged: (v) => setState(() => _favTeam = v!),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 28),
                      // Save button
                      GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(colors: [AppColors.blue, Color(0xFF00C6FF)]),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Text(
                            'Save Changes',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildField(String label, TextEditingController controller, IconData icon) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      borderRadius: 14,
      child: Row(
        children: [
          Icon(icon, color: AppColors.textMuted, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: controller,
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
              decoration: InputDecoration(
                labelText: label,
                labelStyle: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                border: InputBorder.none,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
