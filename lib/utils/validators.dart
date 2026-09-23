class Validators {
  static bool isGujaratiValid(String text) {
    final norm = text.replaceAll(RegExp(r'\s'), '');
    if (norm.isEmpty) return false;
    final gujChars = norm.replaceAll(RegExp(r'[^઀-૿]'), '');
    return (gujChars.length / norm.length) >= 0.5;
  }
}
