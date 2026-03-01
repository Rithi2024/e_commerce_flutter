import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:marketflow/features/auth/presentation/pages/authentication_screen.dart';

void main() {
  testWidgets('Login screen renders and toggles password visibility', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          useMaterial3: false,
          splashFactory: InkRipple.splashFactory,
        ),
        home: const AuthenticationScreen(),
      ),
    );

    expect(find.text('Sign In'), findsNWidgets(2));
    expect(find.text('Create Account'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Email'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'Password'), findsOneWidget);

    expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.pump();
    expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);
  });
}
