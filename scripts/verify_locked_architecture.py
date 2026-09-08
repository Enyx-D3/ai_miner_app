from pathlib import Path

root = Path(__file__).resolve().parents[1]
checks = {
    'MRS router': root / 'lib/mrs/brain2_mrs_runtime.dart',
    'model adapter': root / 'lib/mrs/mobile_model_adapter.dart',
    'Qwen model spec': root / 'lib/model/mobile_qwen_spec.dart',
    'ContextVault native': root / 'lib/contextvault/contextvault_native.dart',
    'ContextVault mobile ABI': root / 'native/contextvault/src/contextvault_mobile_ffi.cpp',
    'pure Dart Reader': root / 'lib/asif/asif_reader_core.dart',
    'atomization stack': root / 'lib/intelligence/atomization_stack.dart',
    'truth engine': root / 'lib/intelligence/truth_engine.dart',
    'intelligence pipeline': root / 'lib/intelligence/mobile_intelligence_pipeline.dart',
    'project resolver': root / 'lib/intelligence/project_resolver.dart',
    'mining flow': root / 'lib/miner/miner_service.dart',
    'multi-provider extractor': root / 'lib/miner/multi_provider_export_extractor.dart',
    'mining history': root / 'lib/miner/miner_history_repository.dart',
    'mine screen': root / 'lib/ui/screens/mine_screen.dart',
    'complete summary screen': root / 'lib/ui/screens/mining_complete_screen.dart',
    'B2M mobile service': root / 'lib/services/b2m_mobile_service.dart',
    'integration start': root / 'integration/00_INTEGRATION_START_HERE.md',
    'web parity handoff': root / 'integration/10_WEB_PARITY_STATUS_AND_WHATS_LEFT.md',
    'fllama decision': root / 'integration/11_FLLAMA_DECISION_AND_OPTIONAL_ADAPTER.md',
}
for name, path in checks.items():
    assert path.exists(), f'missing {name}: {path}'

mrs = (root / 'lib/mrs/brain2_mrs_runtime.dart').read_text()
order = [
    'DATABOX',
    'BRANCH_ZERO',
    'CAPABILITY_LOOKUP',
    'PATTERN_MEMORY',
    'COGNITIVE_R1',
    'TRACE_RPVM',
    'TINY_SPECIALIST',
    'HARD_RESIDUAL',
]
pos = -1
for token in order:
    new_pos = mrs.find(token)
    assert new_pos > pos, f'MRS order failure at {token}'
    pos = new_pos
assert 'BLOCKED_EXTERNAL_DEPENDENCY' in mrs
assert 'MobileModelAdapter' in mrs

reader = (root / 'lib/asif/asif_reader_core.dart').read_text()
assert 'Pure-Dart' in reader or 'Pure Dart' in reader
assert 'libasif_reader.so' not in reader

pipeline = (root / 'lib/intelligence/mobile_intelligence_pipeline.dart').read_text()
for token in ['atoms', 'truths', 'intelligenceSnapshots', 'wikiSnapshots', 'notebookSnapshots']:
    assert token in pipeline, f'missing parity pipeline stage {token}'

importer = (root / 'lib/services/import_service.dart').read_text()
assert 'intelligence.processConversation' in importer or 'intelligence.processConversationData' in importer

miner = (root / 'lib/miner/miner_service.dart').read_text()
for token in ['digestMarkdownFile', 'digest.zip', 'Isolate.run']:
    assert token in miner, f'missing miner integration: {token}'

extractor = (root / 'lib/miner/multi_provider_export_extractor.dart').read_text()
for token in ['ChatGPT', 'Claude', 'Gemini', '_brain2_provider']:
    assert token in extractor, f'missing multi-provider extractor token: {token}'

wiki = (root / 'lib/ui/screens/wiki_screen.dart').read_text()
assert 'wikiSnapshots' in wiki
notes = (root / 'lib/ui/screens/notebooks_screen.dart').read_text()
assert 'notebookSnapshots' in notes

b2m = (root / 'lib/services/b2m_mobile_service.dart').read_text()
for token in [
    'capabilities',
    'reasoningTrajectories',
    'failureMemory',
    'mrsRuns',
    'intelligenceSnapshots',
    'wikiSnapshots',
    'notebookSnapshots',
    'pickAndImportSnapshot',
    'integrity hash mismatch',
]:
    assert token in b2m, f'missing B2M parity token: {token}'

app = (root / 'lib/app/brain2_app.dart').read_text()
for token in ['Mine AI History', 'Mining History', 'Projects', 'Ask Brain2', 'Memory & .B2M', 'LifeWiki', 'Devices & Sync']:
    assert token in app, f'missing app navigation surface: {token}'

print('PASS: Brain2 AI Miner Mobile V9.6 multi-provider + optimized import + P2P web-parity static acceptance')
