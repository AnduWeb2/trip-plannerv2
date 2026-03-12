import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'config.dart';
import 'add_traveler_page.dart';

class TravelerInputChoicePage extends StatelessWidget {
  const TravelerInputChoicePage({super.key});

  Future<void> _onScanDocument(BuildContext context) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Scan Document',
                style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              ListTile(
                leading: const Icon(Icons.camera_alt, color: Color(0xFF5B85AA)),
                title: Text('Take a photo', style: GoogleFonts.poppins()),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library, color: Color(0xFF5B85AA)),
                title: Text('Choose from gallery', style: GoogleFonts.poppins()),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
            ],
          ),
        ),
      ),
    );

    if (source == null || !context.mounted) return;

    final picked = await ImagePicker().pickImage(source: source, imageQuality: 85);
    if (picked == null || !context.mounted) return;

    // Show loading overlay while we call the backend
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Center(
        child: Container(
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(color: Color(0xFF5B85AA)),
              const SizedBox(height: 16),
              Text('Scanning document...', style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ),
    );

    try {
      final bytes = await File(picked.path).readAsBytes();
      final ext = picked.path.split('.').last.toLowerCase();
      final base64Image = 'data:image/$ext;base64,${base64Encode(bytes)}';

      final storage = const FlutterSecureStorage();
      String? token = await storage.read(key: 'access_token');

      Future<http.Response> sendRequest(String? t) => http.post(
            Uri.parse('${AppConfig.baseUrl}/user/api/scan-document/'),
            headers: {
              if (t != null) 'Authorization': 'Bearer $t',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'image': base64Image}),
          );

      http.Response response = await sendRequest(token);

      if (response.statusCode == 401) {
        final refreshToken = await storage.read(key: 'refresh_token');
        if (refreshToken != null) {
          final refreshResp = await http.post(
            Uri.parse('${AppConfig.baseUrl}/user/api/token/refresh/'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'refresh': refreshToken}),
          );
          if (refreshResp.statusCode == 200) {
            final newAccess = jsonDecode(refreshResp.body)['access'] as String?;
            if (newAccess != null) {
              await storage.write(key: 'access_token', value: newAccess);
              token = newAccess;
              response = await sendRequest(token);
            }
          }
        }
      }

      if (!context.mounted) return;
      Navigator.pop(context); // close loading dialog

      if (response.statusCode == 200) {
        final extracted = jsonDecode(response.body) as Map<String, dynamic>;
        final result = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => AddTravelerPage(prefillData: extracted),
          ),
        );
        if (result == true && context.mounted) {
          Navigator.pop(context, true);
        }
      } else {
        final msg = jsonDecode(response.body)['error'] ?? 'Failed to scan document.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg, style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context); // close loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}', style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

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
              onTap: () => _onScanDocument(context),
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
