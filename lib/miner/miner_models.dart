import 'dart:convert';

enum MinerStage {
  preparing,
  extracting,
  contextVault,
  packaging,
  importingMemory,
  intelligence,
  completed,
  failed,
}

class MinerProgress {
  final MinerStage stage;
  final int percent;
  final String message;

  const MinerProgress({
    required this.stage,
    required this.percent,
    required this.message,
  });
}

class MinerRunRecord {
  final String id;
  final String inputFileName;
  final int inputZipBytes;
  final int jsonBytes;
  final int jsonFileCount;
  final int paragraphs;
  final int atoms;
  final int threads;
  final int topicFiles;
  final int conversationsImported;
  final int messagesImported;
  final int extractionTimeMs;
  final int nativeProcessingTimeMs;
  final int outputZipTimeMs;
  final int intelligenceImportTimeMs;
  final int totalTimeMs;
  final int outputZipBytes;
  final bool nativeContextVaultUsed;
  final DateTime completedAt;
  final String outputZipPath;
  final List<String> generatedFiles;
  final List<String> providers;

  const MinerRunRecord({
    required this.id,
    required this.inputFileName,
    required this.inputZipBytes,
    required this.jsonBytes,
    required this.jsonFileCount,
    required this.paragraphs,
    required this.atoms,
    required this.threads,
    required this.topicFiles,
    required this.conversationsImported,
    required this.messagesImported,
    required this.extractionTimeMs,
    required this.nativeProcessingTimeMs,
    required this.outputZipTimeMs,
    required this.intelligenceImportTimeMs,
    required this.totalTimeMs,
    required this.outputZipBytes,
    required this.nativeContextVaultUsed,
    required this.completedAt,
    required this.outputZipPath,
    required this.generatedFiles,
    this.providers = const <String>[],
  });

  double get compressionPercent {
    if (inputZipBytes <= 0) return 0;
    return (1 - (outputZipBytes / inputZipBytes)) * 100;
  }

  MinerRunRecord copyWith({
    int? conversationsImported,
    int? messagesImported,
    int? intelligenceImportTimeMs,
    int? totalTimeMs,
    bool? nativeContextVaultUsed,
    DateTime? completedAt,
  }) {
    return MinerRunRecord(
      id: id,
      inputFileName: inputFileName,
      inputZipBytes: inputZipBytes,
      jsonBytes: jsonBytes,
      jsonFileCount: jsonFileCount,
      paragraphs: paragraphs,
      atoms: atoms,
      threads: threads,
      topicFiles: topicFiles,
      conversationsImported:
          conversationsImported ?? this.conversationsImported,
      messagesImported: messagesImported ?? this.messagesImported,
      extractionTimeMs: extractionTimeMs,
      nativeProcessingTimeMs: nativeProcessingTimeMs,
      outputZipTimeMs: outputZipTimeMs,
      intelligenceImportTimeMs:
          intelligenceImportTimeMs ?? this.intelligenceImportTimeMs,
      totalTimeMs: totalTimeMs ?? this.totalTimeMs,
      outputZipBytes: outputZipBytes,
      nativeContextVaultUsed:
          nativeContextVaultUsed ?? this.nativeContextVaultUsed,
      completedAt: completedAt ?? this.completedAt,
      outputZipPath: outputZipPath,
      generatedFiles: generatedFiles,
      providers: providers,
    );
  }

  Map<String, Object?> toJson() => {
        'id': id,
        'inputFileName': inputFileName,
        'inputZipBytes': inputZipBytes,
        'jsonBytes': jsonBytes,
        'jsonFileCount': jsonFileCount,
        'paragraphs': paragraphs,
        'atoms': atoms,
        'threads': threads,
        'topicFiles': topicFiles,
        'conversationsImported': conversationsImported,
        'messagesImported': messagesImported,
        'extractionTimeMs': extractionTimeMs,
        'nativeProcessingTimeMs': nativeProcessingTimeMs,
        'outputZipTimeMs': outputZipTimeMs,
        'intelligenceImportTimeMs': intelligenceImportTimeMs,
        'totalTimeMs': totalTimeMs,
        'outputZipBytes': outputZipBytes,
        'nativeContextVaultUsed': nativeContextVaultUsed,
        'completedAt': completedAt.toIso8601String(),
        'outputZipPath': outputZipPath,
        'generatedFiles': generatedFiles,
        'providers': providers,
      };

  factory MinerRunRecord.fromJson(Map<String, Object?> json) {
    int number(String key) => (json[key] as num?)?.toInt() ?? 0;

    return MinerRunRecord(
      id: '${json['id'] ?? ''}',
      inputFileName: '${json['inputFileName'] ?? ''}',
      inputZipBytes: number('inputZipBytes'),
      jsonBytes: number('jsonBytes'),
      jsonFileCount: number('jsonFileCount'),
      paragraphs: number('paragraphs'),
      atoms: number('atoms'),
      threads: number('threads'),
      topicFiles: number('topicFiles'),
      conversationsImported: number('conversationsImported'),
      messagesImported: number('messagesImported'),
      extractionTimeMs: number('extractionTimeMs'),
      nativeProcessingTimeMs: number('nativeProcessingTimeMs'),
      outputZipTimeMs: number('outputZipTimeMs'),
      intelligenceImportTimeMs: number('intelligenceImportTimeMs'),
      totalTimeMs: number('totalTimeMs'),
      outputZipBytes: number('outputZipBytes'),
      nativeContextVaultUsed: json['nativeContextVaultUsed'] == true,
      completedAt: DateTime.tryParse('${json['completedAt'] ?? ''}') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      outputZipPath: '${json['outputZipPath'] ?? ''}',
      generatedFiles: (json['generatedFiles'] as List? ?? const <Object?>[])
          .map((value) => '$value')
          .toList(growable: false),
      providers: (json['providers'] as List? ?? const <Object?>[])
          .map((value) => '$value')
          .where((value) => value.isNotEmpty)
          .toList(growable: false),
    );
  }

  String encode() => const JsonEncoder.withIndent('  ').convert(toJson());
}
