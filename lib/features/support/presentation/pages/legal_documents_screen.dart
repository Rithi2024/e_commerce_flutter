import 'package:flutter/material.dart';

enum LegalDocumentType { terms, privacy }

class LegalDocumentsScreen extends StatelessWidget {
  const LegalDocumentsScreen({super.key, required this.type});

  final LegalDocumentType type;

  String get _title {
    switch (type) {
      case LegalDocumentType.terms:
        return 'Terms & Conditions';
      case LegalDocumentType.privacy:
        return 'Privacy Policy';
    }
  }

  List<Widget> _buildContent() {
    switch (type) {
      case LegalDocumentType.terms:
        return const [
          _SectionTitle('1. Use of Service'),
          _SectionBody(
            'By using this app, you agree to use it only for lawful shopping activities and account management.',
          ),
          _SectionTitle('2. Orders and Payments'),
          _SectionBody(
            'All orders are subject to confirmation, stock availability, and payment verification where applicable.',
          ),
          _SectionTitle('3. Account Responsibility'),
          _SectionBody(
            'You are responsible for keeping your account credentials secure and for any activity under your account.',
          ),
          _SectionTitle('4. Changes'),
          _SectionBody(
            'We may update these terms from time to time. Continued use means you accept the latest version.',
          ),
        ];
      case LegalDocumentType.privacy:
        return const [
          _SectionTitle('1. Information We Collect'),
          _SectionBody(
            'We collect information you provide, such as name, phone, address, and order details, to operate the service.',
          ),
          _SectionTitle('2. How We Use Information'),
          _SectionBody(
            'Your data is used to process orders, provide customer support, improve the app, and send emails when you opt in.',
          ),
          _SectionTitle('3. Data Sharing'),
          _SectionBody(
            'We do not sell your personal information. Data may be shared only with service providers needed to process payments and deliveries.',
          ),
          _SectionTitle('4. Contact and Updates'),
          _SectionBody(
            'If you have privacy questions, contact support. This policy may be updated as features and legal requirements change.',
          ),
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: _buildContent(),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 6),
      child: Text(
        text,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _SectionBody extends StatelessWidget {
  const _SectionBody(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: const TextStyle(height: 1.35)),
    );
  }
}
