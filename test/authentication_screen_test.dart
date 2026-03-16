import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:marketflow/features/auth/domain/entities/user_profile_model.dart';
import 'package:marketflow/features/auth/domain/repository/auth_repository.dart';
import 'package:marketflow/features/auth/domain/usecases/auth_use_cases.dart';
import 'package:marketflow/features/auth/presentation/bloc/authentication_provider.dart';
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
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Password'), findsOneWidget);
    expect(find.text('Continue to verification'), findsNothing);
    expect(find.byType(TextField), findsNWidgets(2));

    expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.pump();
    expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);
  });

  testWidgets('Unverified sign in opens the verification screen', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _buildTestApp(
        _FakeAuthRepository(
          loginHandler: (_, _) async {
            throw AuthException('Email not confirmed');
          },
        ),
      ),
    );

    await tester.enterText(find.byType(TextField).at(0), 'verify@example.com');
    await tester.enterText(find.byType(TextField).at(1), 'secret123');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Sign In'));
    await tester.pumpAndSettle();

    expect(find.text('Verify your email'), findsOneWidget);
    expect(
      find.textContaining('Your account still needs email verification'),
      findsOneWidget,
    );
  });

  testWidgets('Register phone field keeps +855 and accepts digits only', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _buildTestApp(_FakeAuthRepository(registerHandler: (_, _) async => null)),
    );

    await tester.tap(find.text('Create Account'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(1), '+855 012ab34567890');
    await tester.pump();

    expect(find.text('+855 '), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField).at(1)).controller!.text,
      '123456789',
    );
  });

  testWidgets(
    'Register opens the verification screen when confirmation is required',
    (WidgetTester tester) async {
      final repository = _FakeAuthRepository(
        registerHandler: (_, _) async => null,
      );

      await tester.pumpWidget(_buildTestApp(repository));

      await tester.tap(find.text('Create Account'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).at(0), 'Market Flow');
      await tester.enterText(find.byType(TextField).at(1), '12345678');
      await tester.enterText(find.byType(TextField).at(2), 'hello@example.com');
      await tester.enterText(find.byType(TextField).at(3), 'secret123');
      await tester.ensureVisible(
        find.widgetWithText(ElevatedButton, 'Create Account'),
      );
      await tester.tap(find.widgetWithText(ElevatedButton, 'Create Account'));
      await tester.pumpAndSettle();

      expect(find.text('Verify your email'), findsOneWidget);
      expect(
        find.textContaining('We sent a verification code to your email'),
        findsOneWidget,
      );
      expect(repository.resendSignupVerificationCalls, 1);
    },
  );
}

Widget _buildTestApp(_FakeAuthRepository repository) {
  return ChangeNotifierProvider<AuthenticationProvider>(
    create: (_) => AuthenticationProvider(useCases: AuthUseCases(repository)),
    child: MaterialApp(
      theme: ThemeData(
        useMaterial3: false,
        splashFactory: InkRipple.splashFactory,
      ),
      home: const AuthenticationScreen(),
    ),
  );
}

class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository({this.loginHandler, this.registerHandler});

  final Future<User?> Function(String email, String password)? loginHandler;
  final Future<User?> Function(String email, String password)? registerHandler;

  int resendSignupVerificationCalls = 0;

  @override
  User? currentUser() => null;

  @override
  Stream<User?> onUserChanges() => const Stream<User?>.empty();

  @override
  Future<User?> login({required String email, required String password}) {
    return loginHandler?.call(email, password) ?? Future<User?>.value(null);
  }

  @override
  Future<User?> register({required String email, required String password}) {
    return registerHandler?.call(email, password) ?? Future<User?>.value(null);
  }

  @override
  Future<void> resendSignupVerification({required String email}) async {
    resendSignupVerificationCalls += 1;
  }

  @override
  Future<void> sendRegistrationEmails({
    required String email,
    required String fullName,
    required bool promoOptIn,
  }) async {}

  @override
  Future<void> verifySignupCode({
    required String email,
    required String code,
  }) async {}

  @override
  Future<void> requestEmailChange({required String newEmail}) async {}

  @override
  Future<void> resendEmailChangeCode({required String newEmail}) async {}

  @override
  Future<void> confirmEmailChange({
    required String newEmail,
    required String code,
  }) async {}

  @override
  Future<void> updatePassword({
    required String currentPassword,
    required String newPassword,
  }) async {}

  @override
  Future<User?> updateUserMetadata({required Map<String, dynamic> data}) async {
    return null;
  }

  @override
  Future<String> uploadProfileAvatar({
    required Uint8List bytes,
    required String fileName,
  }) async => 'https://example.com/avatar.png';

  @override
  Future<void> logout() async {}

  @override
  Future<UserProfile?> fetchProfile() async => null;

  @override
  Future<UserProfile?> upsertProfile({
    required String name,
    required String phone,
    required String address,
    bool? promoEmailOptIn,
  }) async => null;
}
