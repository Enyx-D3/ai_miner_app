import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:brain2_ai_miner_mobile/miner/multi_provider_export_extractor.dart';

void main() {
  test('normalizes Claude export while preserving provider', () async {
    final dir = await Directory.systemTemp.createTemp('brain2-claude-test-');
    addTearDown(() => dir.delete(recursive: true));
    final input = File('${dir.path}/claude_conversations.json');
    final output = File('${dir.path}/prepared.json');
    await input.writeAsString(jsonEncode([
      {
        'uuid': 'claude-conv-1',
        'name': 'Claude Project',
        'created_at': '2026-01-01T00:00:00Z',
        'chat_messages': [
          {
            'uuid': 'm1',
            'sender': 'human',
            'text': 'hello claude',
          },
          {
            'uuid': 'm2',
            'sender': 'assistant',
            'text': 'hello human',
          },
        ],
      }
    ]));

    final prepared = await MultiProviderExportExtractor().prepare(
      inputPath: input.path,
      inputName: input.path.split(Platform.pathSeparator).last,
      outputPath: output.path,
    );
    expect(prepared.providers, contains('claude'));
    final decoded = jsonDecode(await output.readAsString()) as List;
    final conversation = (decoded.single as Map).cast<String, Object?>();
    expect(conversation['_brain2_provider'], 'claude');
    expect(conversation['messages'], isA<List>());
  });

  test('normalizes Gemini role/parts messages', () async {
    final dir = await Directory.systemTemp.createTemp('brain2-gemini-test-');
    addTearDown(() => dir.delete(recursive: true));
    final input = File('${dir.path}/gemini.json');
    final output = File('${dir.path}/prepared.json');
    await input.writeAsString(jsonEncode([
      {
        'id': 'gemini-conv-1',
        'title': 'Gemini Project',
        'messages': [
          {
            'id': 'g1',
            'role': 'user',
            'parts': [
              {'text': 'hello gemini'}
            ],
          },
          {
            'id': 'g2',
            'role': 'model',
            'parts': [
              {'text': 'hello user'}
            ],
          },
        ],
      }
    ]));

    final prepared = await MultiProviderExportExtractor().prepare(
      inputPath: input.path,
      inputName: 'gemini.json',
      outputPath: output.path,
    );
    expect(prepared.providers, contains('gemini'));
    final decoded = jsonDecode(await output.readAsString()) as List;
    final conversation = (decoded.single as Map).cast<String, Object?>();
    expect(conversation['_brain2_provider'], 'gemini');
  });

  test('accepts B2 SourceEnvelope', () async {
    final dir = await Directory.systemTemp.createTemp('brain2-envelope-test-');
    addTearDown(() => dir.delete(recursive: true));
    final input = File('${dir.path}/source_envelope.json');
    final output = File('${dir.path}/prepared.json');
    await input.writeAsString(jsonEncode({
      'format': 'B2_SOURCE_ENVELOPE',
      'version': 2,
      'provider': 'copilot',
      'sourceLabel': 'Copilot Export',
      'sourceType': 'archive',
      'conversationExternalId': 'copilot-1',
      'conversationTitle': 'Copilot Project',
      'messages': [
        {'externalId': 'c1', 'sequence': 0, 'role': 'user', 'text': 'hello'},
        {
          'externalId': 'c2',
          'sequence': 1,
          'role': 'assistant',
          'text': 'hi'
        },
      ],
    }));

    final prepared = await MultiProviderExportExtractor().prepare(
      inputPath: input.path,
      inputName: 'source_envelope.json',
      outputPath: output.path,
    );
    expect(prepared.providers, contains('copilot'));
  });
}
