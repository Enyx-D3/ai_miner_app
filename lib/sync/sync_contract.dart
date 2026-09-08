/// Cross-platform Brain2 P2P wire-table contract.
///
/// Web uses `compiledCapabilities` / `failureMemories`; the current mobile
/// storage schema uses `capabilities` / `failureMemory`. Hash verification is
/// always performed against the original wire payload. These helpers are used
/// only when applying records to the local database or choosing bootstrap table
/// names.
const Map<String, String> brain2LocalToWireTable = {
  'capabilities': 'compiledCapabilities',
  'failureMemory': 'failureMemories',
};

const Map<String, String> brain2WireToLocalTable = {
  'compiledCapabilities': 'capabilities',
  'failureMemories': 'failureMemory',
};

const Set<String> brain2SharedWireTables = {
  'sources',
  'conversations',
  'messages',
  'atoms',
  'truths',
  'projects',
  'ticks',
  'decisions',
  'patterns',
  'experiments',
  'missions',
  'checkpoints',
  'verifications',
  'transactions',
  'patternTests',
  'portableExpertise',
  'compiledCapabilities',
  'reasoningTrajectories',
  'failureMemories',
  'databoxes',
  'evidenceBlocks',
  'mrsRuns',
  'intelligenceSnapshots',
  'wikiSnapshots',
  'notebookSnapshots',
};

const Set<String> brain2WebMergeWireTables = {
  'sources',
  'conversations',
  'messages',
  'atoms',
  'truths',
  'projects',
  'ticks',
  'decisions',
  'patterns',
  'experiments',
  'missions',
  'checkpoints',
  'verifications',
  'transactions',
  'patternTests',
  'portableExpertise',
  'compiledCapabilities',
  'reasoningTrajectories',
  'failureMemories',
  'databoxes',
  'evidenceBlocks',
};

String brain2WireTableForLocal(String localTable) =>
    brain2LocalToWireTable[localTable] ?? localTable;

String brain2LocalTableForWire(String wireTable) =>
    brain2WireToLocalTable[wireTable] ?? wireTable;

bool brain2SupportsWireTable(String wireTable) =>
    brain2SharedWireTables.contains(wireTable);
