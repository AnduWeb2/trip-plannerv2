import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'config.dart';
import 'widgets/custom_button.dart';
import 'widgets/custom_text_field.dart';

class AddTravelerPage extends StatefulWidget {
  final Map<String, dynamic>? traveler;
  final Map<String, dynamic>? prefillData;

  const AddTravelerPage({super.key, this.traveler, this.prefillData});

  @override
  State<AddTravelerPage> createState() => _AddTravelerPageState();
}

class _AddTravelerPageState extends State<AddTravelerPage> {
  final storage = const FlutterSecureStorage();
  final _formKey = GlobalKey<FormState>();

  final firstNameController = TextEditingController();
  final lastNameController = TextEditingController();
  final phoneCodeController = TextEditingController();
  final phoneNumberController = TextEditingController();
  final nationalityController = TextEditingController();

  // Document fields
  final docNumberController = TextEditingController();
  final issuanceCountryController = TextEditingController();
  final issuanceLocationController = TextEditingController();

  DateTime? dateOfBirth;
  String gender = 'Male';
  String documentType = 'PASSPORT';
  DateTime? issuanceDate;
  DateTime? expiryDate;
  bool isLoading = false;
  bool _autoValidate = false;
  bool _dobError = false;
  bool _issuanceDateError = false;
  bool _expiryDateError = false;

  @override
  void initState() {
    super.initState();
    final t = widget.traveler;
    if (t != null) {
      firstNameController.text = t['first_name'] ?? '';
      lastNameController.text = t['last_name'] ?? '';
      phoneCodeController.text = t['phone_country_code'] ?? '';
      phoneNumberController.text = t['phone_number'] ?? '';
      nationalityController.text = t['nationality'] ?? '';
      gender = t['gender'] ?? 'Male';
      final dob = t['date_of_birth'] as String?;
      if (dob != null) {
        dateOfBirth = DateTime.tryParse(dob);
      }
      final doc = t['document'];
      if (doc != null) {
        docNumberController.text = doc['documentNumber'] ?? '';
        issuanceCountryController.text = doc['issuanceCountry'] ?? '';
        issuanceLocationController.text = doc['issuanceLocation'] ?? '';
        documentType = doc['documentType'] ?? 'PASSPORT';
        final iDate = doc['issuanceDate'] as String?;
        if (iDate != null) issuanceDate = DateTime.tryParse(iDate);
        final eDate = doc['expiryDate'] as String?;
        if (eDate != null) expiryDate = DateTime.tryParse(eDate);
      }
    }

    // Pre-populate from Claude scan
    final p = widget.prefillData;
    if (p != null) {
      if (p['first_name'] != null) firstNameController.text = p['first_name'];
      if (p['last_name'] != null) lastNameController.text = p['last_name'];
      if (p['nationality'] != null) nationalityController.text = p['nationality'];
      if (p['gender'] != null && (p['gender'] == 'Male' || p['gender'] == 'Female')) {
        gender = p['gender'];
      }
      if (p['date_of_birth'] != null) dateOfBirth = DateTime.tryParse(p['date_of_birth']);
      if (p['documentType'] != null && (p['documentType'] == 'PASSPORT' || p['documentType'] == 'ID')) {
        documentType = p['documentType'];
      }
      if (p['documentNumber'] != null) docNumberController.text = p['documentNumber'];
      if (p['issuanceCountry'] != null) issuanceCountryController.text = p['issuanceCountry'];
      if (p['issuanceLocation'] != null) issuanceLocationController.text = p['issuanceLocation'];
      if (p['issuanceDate'] != null) issuanceDate = DateTime.tryParse(p['issuanceDate']);
      if (p['expiryDate'] != null) expiryDate = DateTime.tryParse(p['expiryDate']);
    }
  }

  @override
  void dispose() {
    firstNameController.dispose();
    lastNameController.dispose();
    phoneCodeController.dispose();
    phoneNumberController.dispose();
    nationalityController.dispose();
    docNumberController.dispose();
    issuanceCountryController.dispose();
    issuanceLocationController.dispose();
    super.dispose();
  }

  Future<void> _pickDateOfBirth() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(2000, 1, 1),
      firstDate: DateTime(1900),
      lastDate: now,
    );
    if (picked != null) {
      setState(() {
        dateOfBirth = picked;
        _dobError = false;
      });
    }
  }

  Future<void> _pickDocumentDate({required bool isIssuance}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: isIssuance ? DateTime(2020, 1, 1) : DateTime(now.year + 5, 1, 1),
      firstDate: DateTime(1900),
      lastDate: DateTime(now.year + 20),
    );
    if (picked != null) {
      setState(() {
        if (isIssuance) {
          issuanceDate = picked;
          _issuanceDateError = false;
        } else {
          expiryDate = picked;
          _expiryDateError = false;
        }
      });
    }
  }

  String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<String?> _refreshAccessToken() async {
    try {
      final refreshToken = await storage.read(key: 'refresh_token');
      if (refreshToken == null) return null;

      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/user/api/token/refresh/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refresh': refreshToken}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final newAccess = data['access'] as String?;
        final newRefresh = data['refresh'] as String?;
        if (newAccess != null) {
          await storage.write(key: 'access_token', value: newAccess);
          if (newRefresh != null) {
            await storage.write(key: 'refresh_token', value: newRefresh);
          }
          return newAccess;
        }
      }
    } catch (_) {}
    return null;
  }

  Future<void> _submit() async {
    final isEdit = widget.traveler != null;

    final bool missingTab0 =
        firstNameController.text.trim().isEmpty ||
        lastNameController.text.trim().isEmpty ||
        dateOfBirth == null ||
        phoneCodeController.text.trim().isEmpty ||
        phoneNumberController.text.trim().isEmpty ||
        nationalityController.text.trim().isEmpty;

    final bool missingDoc = !isEdit && (
        docNumberController.text.trim().isEmpty ||
        issuanceDate == null ||
        expiryDate == null ||
        issuanceCountryController.text.trim().isEmpty
    );

    if (missingTab0) {
      setState(() {
        _activeTab = 0;
        _autoValidate = true;
        _dobError = dateOfBirth == null;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _formKey.currentState?.validate();
      });
      return;
    }

    if (missingDoc) {
      setState(() {
        _activeTab = 1;
        _autoValidate = true;
        _issuanceDateError = issuanceDate == null;
        _expiryDateError = expiryDate == null;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _formKey.currentState?.validate();
      });
      return;
    }

    if (!(_formKey.currentState?.validate() ?? true)) return;

    setState(() => isLoading = true);

    final travelerId = widget.traveler?['id'];

    try {
      final payload = {
        'first_name': firstNameController.text.trim(),
        'last_name': lastNameController.text.trim(),
        'date_of_birth': _formatDate(dateOfBirth!),
        'gender': gender,
        'phone_country_code': phoneCodeController.text.trim(),
        'phone_number': phoneNumberController.text.trim(),
        'nationality': nationalityController.text.trim().toUpperCase(),
        // Document fields — always included for new travelers; optional for edits
        if (!isEdit || docNumberController.text.trim().isNotEmpty) ...{
          'documentType': documentType,
          'documentNumber': docNumberController.text.trim(),
          if (issuanceDate != null) 'issuanceDate': _formatDate(issuanceDate!),
          if (expiryDate != null) 'expiryDate': _formatDate(expiryDate!),
          'issuanceCountry': issuanceCountryController.text.trim().toUpperCase(),
          if (issuanceLocationController.text.trim().isNotEmpty)
            'issuanceLocation': issuanceLocationController.text.trim(),
        },
      };

      Future<http.Response> sendRequest(String? token) {
        final uri = isEdit
            ? Uri.parse('${AppConfig.baseUrl}/user/api/update-traveler/$travelerId/')
            : Uri.parse('${AppConfig.baseUrl}/user/api/create-traveler/');
        final headers = {
          if (token != null) 'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        };
        final body = jsonEncode(payload);
        return isEdit
            ? http.patch(uri, headers: headers, body: body)
            : http.post(uri, headers: headers, body: body);
      }

      String? token = await storage.read(key: 'access_token');
      http.Response response = await sendRequest(token);

      if (response.statusCode == 401) {
        final refreshed = await _refreshAccessToken();
        if (refreshed != null) {
          token = refreshed;
          response = await sendRequest(token);
        }
      }

      final successCode = isEdit ? 200 : 201;
      final successMsg = isEdit ? 'Traveler updated successfully!' : 'Traveler added successfully!';

      if (response.statusCode == successCode) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                successMsg,
                style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
              ),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context, true);
        }
      } else {
        const fieldLabels = {
          'first_name': 'First name',
          'last_name': 'Last name',
          'date_of_birth': 'Date of birth',
          'phone_country_code': 'Phone country code',
          'phone_number': 'Phone number',
          'nationality': 'Nationality',
          'documentType': 'Document type',
          'documentNumber': 'Document number',
          'issuanceDate': 'Issuance date',
          'expiryDate': 'Expiry date',
          'issuanceCountry': 'Issuance country',
          'issuanceLocation': 'Issuance location',
        };
        String errorMsg = isEdit ? 'Failed to update traveler.' : 'Failed to add traveler.';
        try {
          final body = jsonDecode(response.body);
          if (body is Map) {
            final errors = body.entries.map((e) {
              final label = fieldLabels[e.key] ?? e.key;
              final msg = e.value is List ? (e.value as List).join(', ') : e.value.toString();
              return '\u2022 $label: $msg';
            }).join('\n');
            errorMsg = errors;
          }
        } catch (_) {}
        if (mounted) _showError('Please fix the following', errorMsg);
      }
    } catch (e) {
      if (mounted) _showError('Error', e.toString());
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete Traveler', style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: Colors.red)),
        content: Text(
          'Are you sure you want to delete ${widget.traveler!['first_name']} ${widget.traveler!['last_name']}?',
          style: GoogleFonts.poppins(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: GoogleFonts.poppins(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Delete', style: GoogleFonts.poppins(color: Colors.red, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    if (confirmed == true) await _deleteTraveler();
  }

  Future<void> _deleteTraveler() async {
    final travelerId = widget.traveler!['id'];
    setState(() => isLoading = true);
    try {
      Future<http.Response> sendRequest(String? token) {
        return http.delete(
          Uri.parse('${AppConfig.baseUrl}/user/api/delete-traveler/$travelerId/'),
          headers: {
            if (token != null) 'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
        );
      }

      String? token = await storage.read(key: 'access_token');
      http.Response response = await sendRequest(token);

      if (response.statusCode == 401) {
        final refreshed = await _refreshAccessToken();
        if (refreshed != null) {
          token = refreshed;
          response = await sendRequest(token);
        }
      }

      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Traveler deleted successfully!', style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context, true);
        }
      } else {
        if (mounted) _showError('Error', 'Failed to delete traveler.');
      }
    } catch (e) {
      if (mounted) _showError('Error', e.toString());
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  void _showError(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title, style: GoogleFonts.poppins(fontWeight: FontWeight.w600, color: Colors.red)),
        content: Text(message, style: GoogleFonts.poppins(fontSize: 14)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('OK', style: GoogleFonts.poppins(color: const Color(0xFF5B85AA), fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  int _activeTab = 0;

  Widget _buildTabBar() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF0F4F8),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          _buildTabButton(0, 'Traveler Details', Icons.person),
          _buildTabButton(1, 'Document Details', Icons.badge),
        ],
      ),
    );
  }

  Widget _buildTabButton(int index, String label, IconData icon) {
    final isActive = _activeTab == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _activeTab = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isActive ? const Color(0xFF5B85AA) : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: isActive ? Colors.white : Colors.grey[600]),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isActive ? Colors.white : Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTravelerDetailsForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CustomTextField(
          controller: firstNameController,
          label: 'First Name',
          hint: 'Enter first name',
          prefixIcon: Icons.person,
          validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter a first name' : null,
        ),
        const SizedBox(height: 16),
        CustomTextField(
          controller: lastNameController,
          label: 'Last Name',
          hint: 'Enter last name',
          prefixIcon: Icons.person_outline,
          validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter a last name' : null,
        ),
        const SizedBox(height: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Date of Birth', style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: const Color(0xFF333333))),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: _pickDateOfBirth,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFAFAFA),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _dobError ? Colors.red : const Color(0xFFD0D0D0),
                    width: 1.5,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.calendar_today, color: _dobError ? Colors.red : const Color(0xFF5B85AA), size: 20),
                    const SizedBox(width: 12),
                    Text(
                      dateOfBirth != null ? _formatDate(dateOfBirth!) : 'Select date of birth',
                      style: GoogleFonts.poppins(fontSize: 14, color: dateOfBirth != null ? const Color(0xFF333333) : Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
            if (_dobError) ...[  
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Text(
                  'Please select a date of birth',
                  style: GoogleFonts.poppins(fontSize: 12, color: Colors.red[700]),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Gender', style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: const Color(0xFF333333))),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFFAFAFA),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFD0D0D0), width: 1.5),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: gender,
                  isExpanded: true,
                  style: GoogleFonts.poppins(fontSize: 14, color: const Color(0xFF333333)),
                  items: const [
                    DropdownMenuItem(value: 'Male', child: Text('Male')),
                    DropdownMenuItem(value: 'Female', child: Text('Female')),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => gender = val);
                  },
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            SizedBox(
              width: 100,
              child: CustomTextField(
                controller: phoneCodeController,
                label: 'Code',
                hint: '+40',
                prefixIcon: Icons.public,
                keyboardType: TextInputType.phone,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: CustomTextField(
                controller: phoneNumberController,
                label: 'Phone Number',
                hint: '0712345678',
                prefixIcon: Icons.phone,
                keyboardType: TextInputType.phone,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter a phone number' : null,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        CustomTextField(
          controller: nationalityController,
          label: 'Nationality (2-letter code)',
          hint: 'RO',
          prefixIcon: Icons.flag,
          validator: (v) {
            if (v == null || v.trim().isEmpty) return 'Please enter a nationality code';
            if (v.trim().length != 2) return 'Use a 2-letter code (e.g. RO)';
            return null;
          },
        ),
      ],
    );
  }

  Widget _buildDocumentDetailsForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.traveler == null) ...[
          Text(
            'Required to create a traveler',
            style: GoogleFonts.poppins(fontSize: 13, color: Colors.red[400]),
          ),
          const SizedBox(height: 20),
        ],
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Document Type', style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: const Color(0xFF333333))),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFFAFAFA),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFD0D0D0), width: 1.5),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: documentType,
                  isExpanded: true,
                  style: GoogleFonts.poppins(fontSize: 14, color: const Color(0xFF333333)),
                  items: const [
                    DropdownMenuItem(value: 'PASSPORT', child: Text('Passport')),
                    DropdownMenuItem(value: 'ID', child: Text('National ID')),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => documentType = val);
                  },
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        CustomTextField(
          controller: docNumberController,
          label: 'Document Number',
          hint: 'e.g. AB123456',
          prefixIcon: Icons.badge,
          validator: widget.traveler == null
              ? (v) => (v == null || v.trim().isEmpty) ? 'Please enter the document number' : null
              : null,
        ),
        const SizedBox(height: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Issuance Date', style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: const Color(0xFF333333))),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => _pickDocumentDate(isIssuance: true),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFAFAFA),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _issuanceDateError ? Colors.red : const Color(0xFFD0D0D0),
                    width: 1.5,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.calendar_today, color: _issuanceDateError ? Colors.red : const Color(0xFF5B85AA), size: 20),
                    const SizedBox(width: 12),
                    Text(
                      issuanceDate != null ? _formatDate(issuanceDate!) : 'Select issuance date',
                      style: GoogleFonts.poppins(fontSize: 14, color: issuanceDate != null ? const Color(0xFF333333) : Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
            if (_issuanceDateError) ...[  
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Text(
                  'Please select an issuance date',
                  style: GoogleFonts.poppins(fontSize: 12, color: Colors.red[700]),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Expiry Date', style: GoogleFonts.poppins(fontSize: 14, fontWeight: FontWeight.w600, color: const Color(0xFF333333))),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => _pickDocumentDate(isIssuance: false),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFAFAFA),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _expiryDateError ? Colors.red : const Color(0xFFD0D0D0),
                    width: 1.5,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.calendar_today, color: _expiryDateError ? Colors.red : const Color(0xFF5B85AA), size: 20),
                    const SizedBox(width: 12),
                    Text(
                      expiryDate != null ? _formatDate(expiryDate!) : 'Select expiry date',
                      style: GoogleFonts.poppins(fontSize: 14, color: expiryDate != null ? const Color(0xFF333333) : Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
            if (_expiryDateError) ...[  
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Text(
                  'Please select an expiry date',
                  style: GoogleFonts.poppins(fontSize: 12, color: Colors.red[700]),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 16),
        CustomTextField(
          controller: issuanceCountryController,
          label: 'Issuance Country (2-letter code)',
          hint: 'RO',
          prefixIcon: Icons.location_on,
          validator: widget.traveler == null
              ? (v) {
                  if (v == null || v.trim().isEmpty) return 'Please enter the issuance country code';
                  if (v.trim().length != 2) return 'Use a 2-letter code (e.g. RO)';
                  return null;
                }
              : null,
        ),
        const SizedBox(height: 16),
        CustomTextField(
          controller: issuanceLocationController,
          label: 'Issuance Location (optional)',
          hint: 'e.g. Bucharest',
          prefixIcon: Icons.place,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.traveler != null ? 'Edit Traveler' : 'Add Traveler', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
        backgroundColor: const Color(0xFF5B85AA),
        elevation: 4,
        actions: [
          if (widget.traveler != null)
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: _confirmDelete,
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          autovalidateMode: _autoValidate ? AutovalidateMode.onUserInteraction : AutovalidateMode.disabled,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTabBar(),
              const SizedBox(height: 24),
              _activeTab == 0 ? _buildTravelerDetailsForm() : _buildDocumentDetailsForm(),
              const SizedBox(height: 32),
              CustomButton(
                label: widget.traveler != null ? 'Save Changes' : 'Add Traveler',
                onPressed: _submit,
                isLoading: isLoading,
                icon: widget.traveler != null ? Icons.save : Icons.person_add,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
