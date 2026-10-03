import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../core/identity.dart';

const String sharedQueryPlannerVersion = 'B2_QUERY_PLANNER_V1';

enum SharedQueryClass {
  exact,
  temporal,
  contradiction,
  failure,
  semantic,
  genealogyArchaeology,
  multiProject
}

enum SharedQueryMode { fast, standard, deep }

class SharedQueryPlan {
  final SharedQueryClass queryClass;
  final SharedQueryMode mode;
  final String route;
  final String normalizedQuery;
  final List<String> reasons;
  final bool exhaustiveRequested;
  final int projectCount;
  const SharedQueryPlan(
      {required this.queryClass,
      required this.mode,
      required this.route,
      required this.normalizedQuery,
      required this.reasons,
      required this.exhaustiveRequested,
      required this.projectCount});
  String get queryClassWire => switch (queryClass) {
        SharedQueryClass.exact => 'EXACT',
        SharedQueryClass.temporal => 'TEMPORAL',
        SharedQueryClass.contradiction => 'CONTRADICTION',
        SharedQueryClass.failure => 'FAILURE',
        SharedQueryClass.semantic => 'SEMANTIC',
        SharedQueryClass.genealogyArchaeology => 'GENEALOGY_ARCHAEOLOGY',
        SharedQueryClass.multiProject => 'MULTI_PROJECT'
      };
  String get modeWire => mode.name.toUpperCase();
  Map<String, Object?> toJson() => {
        'version': sharedQueryPlannerVersion,
        'queryClass': queryClassWire,
        'mode': modeWire,
        'route': route,
        'normalizedQuery': normalizedQuery,
        'reasons': reasons,
        'exhaustiveRequested': exhaustiveRequested,
        'projectCount': projectCount
      };
}

String _norm(String value) => normalizeText(value);
bool _has(RegExp re, String q) => re.hasMatch(q);
final _deep = RegExp(
    r'\b(deep archaeology|deep search|archaeolog(?:y|ical)|search everything|search all|all evidence|exhaustive|nothing (?:is|was) missed|make sure nothing|full genealogy|lineage|origin trail|trace back)\b',
    caseSensitive: false);
final _multi = RegExp(
    r'\b(across projects?|multiple projects?|cross[- ]project|all projects?|compare projects?|compare across)\b',
    caseSensitive: false);
final _contradiction = RegExp(
    r'\b(contradict(?:ion|s|ed|ory)?|conflict(?:ing|s|ed)?|disagree|inconsistent|mismatch|which is true)\b',
    caseSensitive: false);
final _failure = RegExp(
    r"\b(fail(?:ed|ure|ing)?|error|bug|crash|broken|didn['’]?t work|doesn['’]?t work|known bad|repair)\b",
    caseSensitive: false);
final _temporal = RegExp(
    r'\b(current|currently|latest|now|changed|change|before|after|timeline|history|supersed\w*|replaced|decision|decided|version|status|when did|what did we use|what are we using|what did we decide)\b',
    caseSensitive: false);
final _relational = RegExp(
    r'\b(why|cause|causal|depends?|dependency|relationship|relate|connect|connection|pattern)\b',
    caseSensitive: false);
final _exact = RegExp(
    r'''(?:\b(?:id|hash|sha|version|commit|receipt|mission)\b\s*[:=#-]?\s*[a-z0-9_.:-]{5,}|["“”'][^"“”']{3,}["“”'])''',
    caseSensitive: false);

SharedQueryPlan planSharedQuery(String query,
    {SharedQueryMode? requestedMode, int projectCount = 0}) {
  final q = _norm(query);
  final reasons = <String>[];
  late SharedQueryClass qc;
  late SharedQueryMode mode;
  late String route;
  if (_has(_deep, q)) {
    qc = SharedQueryClass.genealogyArchaeology;
    mode = SharedQueryMode.deep;
    route = 'G_ADAPTIVE_HETEROGENEOUS';
    reasons.add('explicit genealogy/archaeology or exhaustive-search intent');
  } else if (_has(_multi, q) || projectCount > 1) {
    qc = SharedQueryClass.multiProject;
    mode = SharedQueryMode.standard;
    route = 'G_ADAPTIVE_HETEROGENEOUS';
    reasons.add('cross-project or multi-project retrieval');
  } else if (_has(_contradiction, q)) {
    qc = SharedQueryClass.contradiction;
    mode = SharedQueryMode.standard;
    route = 'F_TEMPORAL_TRUTH';
    reasons.add('conflict/contradiction resolution requires truth lineage');
  } else if (_has(_failure, q)) {
    qc = SharedQueryClass.failure;
    mode = SharedQueryMode.standard;
    route = 'G_ADAPTIVE_HETEROGENEOUS';
    reasons.add('failure/repair memory requested');
  } else if (_has(_temporal, q)) {
    qc = SharedQueryClass.temporal;
    mode = SharedQueryMode.standard;
    route = 'F_TEMPORAL_TRUTH';
    reasons.add('current-state/history/timeline intent');
  } else if (_has(_relational, q)) {
    qc = SharedQueryClass.semantic;
    mode = SharedQueryMode.standard;
    route = 'G_ADAPTIVE_HETEROGENEOUS';
    reasons.add('relationship/dependency/causal retrieval');
  } else if (_has(_exact, q)) {
    qc = SharedQueryClass.exact;
    mode = SharedQueryMode.fast;
    route = 'B_250_CHUNK';
    reasons.add('exact identifier/quoted-literal lookup');
  } else {
    qc = SharedQueryClass.semantic;
    mode = SharedQueryMode.fast;
    route = 'B_250_CHUNK';
    reasons.add('bounded semantic retrieval');
  }
  if (requestedMode != null && requestedMode != mode) {
    mode = requestedMode;
    reasons.add('explicit mode override: ${requestedMode.name.toUpperCase()}');
  }
  return SharedQueryPlan(
      queryClass: qc,
      mode: mode,
      route: route,
      normalizedQuery: q,
      reasons: reasons,
      exhaustiveRequested: qc == SharedQueryClass.genealogyArchaeology ||
          mode == SharedQueryMode.deep,
      projectCount: projectCount < 0 ? 0 : projectCount);
}

Object? _sortJson(Object? value) {
  if (value is List) return value.map(_sortJson).toList();
  if (value is Map) {
    final keys = value.keys.map((e) => e.toString()).toList()..sort();
    return {for (final k in keys) k: _sortJson(value[k])};
  }
  return value;
}

String hashSharedQueryPlan(SharedQueryPlan plan) => sha256
    .convert(utf8.encode(jsonEncode(_sortJson(plan.toJson()))))
    .toString();
