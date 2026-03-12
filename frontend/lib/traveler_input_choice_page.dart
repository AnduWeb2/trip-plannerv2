import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'add_traveler_page.dart';

class TravelerInputChoicePage extends StatelessWidget {
  const TravelerInputChoicePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Add Traveler', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        backgroundColor: const Color(0xFF5B85AA),
        elevation: 4,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'How would you like to add traveler details?',
              style: GoogleFonts.poppins(fontSize: 20, fontWeight: FontWeight.w700, color: const Color(0xFF333333)),
            ),
            const SizedBox(height: 8),
            Text(
              'Choose a method to fill in the traveler information.',
              style: GoogleFonts.poppins(fontSize: 14, color: Colors.grey[600]),
            ),
            const SizedBox(height: 32),
            _buildChoiceTile(
              context,
              icon: Icons.edit_note,
              title: 'Enter Manually',
              subtitle: 'Fill in the traveler details yourself',
              onTap: () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AddTravelerPage()),
                );
                if (result == true && context.mounted) {
                  Navigator.pop(context, true);
                }
              },
            ),
            const SizedBox(height: 16),
            _buildChoiceTile(
              context,
              icon: Icons.document_scanner,
              title: 'Scan Document',
              subtitle: 'Take a photo of the traveler\'s ID or passport',
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Document scanning coming soon!',
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
                    ),
                    backgroundColor: const Color(0xFF5B85AA),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChoiceTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF5B85AA).withValues(alpha: 0.3), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF5B85AA).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: const Color(0xFF5B85AA), size: 32),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600, color: const Color(0xFF333333)),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: GoogleFonts.poppins(fontSize: 13, fontWeight: FontWeight.w400, color: Colors.grey[500]),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }
}
