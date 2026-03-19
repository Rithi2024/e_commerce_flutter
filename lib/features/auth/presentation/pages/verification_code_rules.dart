const int verificationCodeMinLength = 6;
const int verificationCodeMaxLength = 8;

final RegExp verificationCodePattern = RegExp(
  '^\\d{$verificationCodeMinLength,$verificationCodeMaxLength}\$',
);

bool isValidVerificationCode(String value) {
  return verificationCodePattern.hasMatch(value.trim());
}
