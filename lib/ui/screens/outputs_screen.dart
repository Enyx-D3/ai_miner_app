import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../app/brain2_controller.dart';
import '../../services/result_return_service.dart';
import '../widgets.dart';

class OutputsScreen extends StatefulWidget {
  final Brain2Controller c;
  const OutputsScreen(this.c, {super.key});
  @override
  State<OutputsScreen> createState() => _OutputsScreenState();
}

class _OutputsScreenState extends State<OutputsScreen> {
  List<Map<String, Object?>> rows = [];
  bool busy = true;
  ResultReturnState? last;
  String? note;
  ResultReturnService get service =>
      ResultReturnService(widget.c.db, widget.c.mutations, widget.c.reader);
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    rows =
        await widget.c.db.records('transactions', orderBy: 'updated_at DESC');
    if (mounted) setState(() => busy = false);
  }

  Future<void> importResult() async {
    final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['json', 'b2result'],
        allowMultiple: false);
    final path = picked?.files.single.path;
    if (path == null) return;
    setState(() {
      busy = true;
      note = null;
    });
    try {
      final decoded = jsonDecode(await File(path).readAsString());
      if (decoded is! Map) {
        throw const FormatException('B2RESULT must be a JSON object.');
      }
      final state =
          await service.importAndVerify(decoded.cast<String, Object?>());
      if (mounted) {
        setState(() {
          last = state;
          note = state.detail;
        });
      }
      await load();
    } catch (e) {
      if (mounted) {
        setState(() => note = 'Result import failed: $e');
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  Future<void> approve() async {
    final state = last;
    if (state == null || state.status != 'PASS') return;
    setState(() => busy = true);
    try {
      final atomId =
          await service.approveVerifiedResult(state.resultTransactionId);
      if (mounted) {
        setState(() => note =
            'Accepted as verified returned observation $atomId. Current Truth was not modified.');
      }
      await load();
    } catch (e) {
      if (mounted) {
        setState(() => note = 'Approval failed: $e');
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => RefreshIndicator(
      onRefresh: load,
      child: ListView(padding: const EdgeInsets.all(16), children: [
        const PageTitle('Outputs & Result Return',
            'Import B2RESULT, verify B2JOB/Databox/evidence provenance, then explicitly approve a PASS result back into project memory as an observation. It never becomes Current Truth automatically.'),
        const SizedBox(height: 12),
        FilledButton.icon(
            onPressed: busy ? null : importResult,
            icon: const Icon(Icons.upload_file_outlined),
            label: const Text('Import B2RESULT')),
        if (last != null || note != null) ...[
          const SizedBox(height: 12),
          Card(
              child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (last != null)
                          Row(children: [
                            Text('PROVENANCE ${last!.status}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w900)),
                            const Spacer(),
                            Flexible(
                                child: Text(last!.resultTransactionId,
                                    style: const TextStyle(
                                        fontFamily: 'monospace', fontSize: 9),
                                    overflow: TextOverflow.ellipsis))
                          ]),
                        if (note != null) ...[
                          const SizedBox(height: 8),
                          Text(note!)
                        ],
                        if (last?.status == 'PASS') ...[
                          const SizedBox(height: 12),
                          FilledButton.icon(
                              onPressed: busy ? null : approve,
                              icon: const Icon(Icons.verified_user_outlined),
                              label: const Text('Approve into project memory')),
                          const SizedBox(height: 8),
                          const Text(
                              'Explicit approval emits R1 ALLOW and stores the answer as a verified observation only. A separate promotion gate is required for Current Truth.',
                              style: TextStyle(fontSize: 11))
                        ]
                      ])))
        ],
        const SizedBox(height: 12),
        if (busy)
          const Center(child: CircularProgressIndicator())
        else if (rows.isEmpty)
          const Card(
              child: Padding(
                  padding: EdgeInsets.all(22),
                  child: Text(
                      'No records yet. Compile a B2JOB or import a verified B2RESULT.')))
        else
          ...rows.take(300).map((r) => RecordTile(r))
      ]));
}
