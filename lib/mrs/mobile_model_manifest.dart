class MobileModelManifest {
  final String id;
  final String displayName;
  final String fileName;
  final Uri downloadUri;
  final String sha256Hex;
  final int sizeBytes;
  final int contextSize;
  final int maxNewTokens;

  const MobileModelManifest({
    required this.id,
    required this.displayName,
    required this.fileName,
    required this.downloadUri,
    required this.sha256Hex,
    required this.sizeBytes,
    this.contextSize = 2048,
    this.maxNewTokens = 256,
  });

  static final v1Default = MobileModelManifest(
    id: 'smollm2-360m-instruct-q4-k-m',
    displayName: 'SmolLM2 360M Instruct Q4_K_M',
    fileName: 'SmolLM2-360M-Instruct-Q4_K_M.gguf',
    downloadUri: Uri.parse(
      'https://huggingface.co/bartowski/SmolLM2-360M-Instruct-GGUF/resolve/main/SmolLM2-360M-Instruct-Q4_K_M.gguf?download=true',
    ),
    sha256Hex:
        '2fa3f013dcdd7b99f9b237717fa0b12d75bbb89984cc1274be1471a465bac9c2',
    sizeBytes: 271000000,
  );
}
