abstract class MobileModelAdapter {
  String get runtimeName;
  String get modelName;
  Future<bool> isAvailable();
  Future<String> generate(
      {required String systemPrompt,
      required String userPrompt,
      int maxNewTokens = 256});
}

class UnconfiguredMobileModelAdapter implements MobileModelAdapter {
  @override
  String get runtimeName => 'UNCONFIGURED';
  @override
  String get modelName => 'UNCONFIGURED';
  @override
  Future<bool> isAvailable() async => false;
  @override
  Future<String> generate(
      {required String systemPrompt,
      required String userPrompt,
      int maxNewTokens = 256}) {
    throw StateError(
        'No mobile neural runtime is configured. The locked MRS router must stop at the hard-residual dependency rather than bypass it.');
  }
}
