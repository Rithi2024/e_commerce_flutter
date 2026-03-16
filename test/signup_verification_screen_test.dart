import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:marketflow/features/auth/presentation/pages/signup_verification_screen.dart';

void main() {
  testWidgets('Signup verification screen renders dedicated form', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SignupVerificationScreen(
          initialEmail: 'hello@example.com',
          introMessage:
              'We sent a verification code to your email. Check inbox and spam if you do not see it right away.',
        ),
      ),
    );

    expect(find.text('Verify your email'), findsOneWidget);
    expect(find.text('Verify email'), findsOneWidget);
    expect(find.text('Resend code'), findsOneWidget);
    expect(find.text('Back to sign in'), findsOneWidget);
    expect(
      find.textContaining('We sent a verification code to your email'),
      findsOneWidget,
    );
    expect(find.byType(TextField), findsNWidgets(2));
  });
}
