import 'package:flutter_test/flutter_test.dart';
import 'package:marketflow/core/auth/profile_identity_text.dart';

void main() {
  group('ProfileIdentityText', () {
    test('prefers the explicit profile name', () {
      final name = ProfileIdentityText.contactName(
        explicitName: 'Rithybhi Sok',
        userMetadata: const <String, dynamic>{'full_name': 'Fallback Name'},
        email: 'rithybhi@example.com',
      );

      expect(name, 'Rithybhi Sok');
    });

    test('falls back to auth metadata when profile name is blank', () {
      final name = ProfileIdentityText.contactName(
        explicitName: '',
        userMetadata: const <String, dynamic>{'full_name': 'Market Flow'},
        email: 'market@example.com',
      );

      expect(name, 'Market Flow');
    });

    test('derives a readable name from email when needed', () {
      final name = ProfileIdentityText.contactName(
        explicitName: '',
        userMetadata: const <String, dynamic>{},
        email: 'rithybhi.sok@example.com',
      );

      expect(name, 'Rithybhi Sok');
    });

    test('falls back to metadata phone when profile phone is blank', () {
      final phone = ProfileIdentityText.contactPhone(
        explicitPhone: '',
        userMetadata: const <String, dynamic>{'phone_number': '+85512345678'},
      );

      expect(phone, '+85512345678');
    });
  });
}
