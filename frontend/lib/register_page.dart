import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:google_fonts/google_fonts.dart';
import 'config.dart';
import 'dart:convert';
import 'widgets/custom_button.dart';
import 'widgets/custom_text_field.dart';
import 'widgets/app_header.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final usernameController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();
  bool isLoading = false;

  Future<void> register() async {
    // Validation
    if (usernameController.text.isEmpty ||
        emailController.text.isEmpty ||
        passwordController.text.isEmpty ||
        confirmPasswordController.text.isEmpty) {
      _showError('All fields are required');
      return;
    }

    if (passwordController.text != confirmPasswordController.text) {
      _showError('Passwords do not match');
      return;
    }

    setState(() => isLoading = true);

    try {
      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/user/api/register/'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': usernameController.text,
          'email': emailController.text,
          'password': passwordController.text,
          'password2': confirmPasswordController.text,
        }),
      );

      if (response.statusCode == 201) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Registration successful! Please log in now.',
                style: GoogleFonts.poppins(fontWeight: FontWeight.w500),
              ),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 2),
            ),
          );
          Navigator.pushReplacementNamed(context, '/login');
        }
      } else {
        String errorMessage = 'Registration failed. Please try again.';

        try {
          final errorBody = jsonDecode(response.body);

          if (errorBody is Map) {
            if (errorBody.containsKey('email')) {
              errorMessage = 'Invalid email or email already exists';
            } else if (errorBody.containsKey('username')) {
              errorMessage = 'Username already exists';
            } else if (errorBody.containsKey('password')) {
              errorMessage = 'Passwords don\'t match or password is too weak';
            } else if (errorBody.containsKey('password2')) {
              errorMessage = 'Passwords don\'t match';
            } else {
              errorMessage = 'Registration failed. Please check your information.';
            }
          }
        } catch (e) {
          errorMessage = 'Registration failed. Please try again.';
        }

        if (mounted) {
          _showError(errorMessage);
        }
      }
    } catch (e) {
      if (mounted) {
        _showError('Unable to connect to server. Please check your internet connection.');
      }
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  void _showError(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          'Error',
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            color: Colors.red,
          ),
        ),
        content: Text(
          message,
          style: GoogleFonts.poppins(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'OK',
              style: GoogleFonts.poppins(
                color: const Color(0xFF5B85AA),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    usernameController.dispose();
    emailController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Back Button
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey[300]!),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.arrow_back, color: Color(0xFF333333)),
                  ),
                ),
                const SizedBox(height: 32),

                // Header
                const AppHeader(
                  title: 'Create Account',
                  subtitle: 'Join us and start planning your amazing trips',
                ),
                const SizedBox(height: 40),

                // Form
                CustomTextField(
                  controller: usernameController,
                  label: 'Username',
                  hint: 'Choose a username',
                  prefixIcon: Icons.person,
                ),
                const SizedBox(height: 20),

                CustomTextField(
                  controller: emailController,
                  label: 'Email',
                  hint: 'Enter your email address',
                  prefixIcon: Icons.email,
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 20),

                CustomTextField(
                  controller: passwordController,
                  label: 'Password',
                  hint: 'Create a strong password',
                  prefixIcon: Icons.lock,
                  obscureText: true,
                ),
                const SizedBox(height: 20),

                CustomTextField(
                  controller: confirmPasswordController,
                  label: 'Confirm Password',
                  hint: 'Re-enter your password',
                  prefixIcon: Icons.lock_clock,
                  obscureText: true,
                ),
                const SizedBox(height: 32),

                // Buttons
                CustomButton(
                  label: 'Create Account',
                  icon: Icons.check_circle,
                  isLoading: isLoading,
                  onPressed: register,
                ),
                const SizedBox(height: 12),

                CustomButton(
                  label: 'Back to Login',
                  icon: Icons.arrow_back,
                  isOutlined: true,
                  onPressed: () => Navigator.pop(context),
                ),

                const SizedBox(height: 24),
                Center(
                  child: Text(
                    'By creating an account, you agree to our Terms of Service',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: Colors.grey[400],
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
