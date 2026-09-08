#!/usr/bin/env python3
"""
Brain2 AI Miner Mobile - Patch 08
Fixes the current build/analyze blockers after parity patches:

1) project_resolver.dart malformed Dart ternary:
     confidence:fingerprint.allTerms.length>=4?.82:.62,
   -> confidence: fingerprint.allTerms.length >= 4 ? 0.82 : 0.62,

2) Replaces Flutter's stale default Counter/MyApp widget test with a
   Brain2App root-widget existence smoke test that does not boot plugins/DB.

3) Removes one known unused import introduced in memory_diagnostics.dart
   when it is present.

Run from the mobile project root:
    python3 patch_08_fix_build_errors.py .
"""

from __future__ import annotations

import re
import shutil
import sys
import time
from pathlib import Path


def backup(path: Path) -> Path:
    stamp = int(time.time())
    dst = path.with_name(f"{path.name}.patch08_backup_{stamp}")
    shutil.copy2(path, dst)
    return dst


def patch_project_resolver(root: Path) -> bool:
    p = root / "lib/intelligence/project_resolver.dart"
    if not p.exists():
        raise SystemExit(f"ERROR: missing {p}")

    s = p.read_text()
    original = s

    # Handles the exact broken form and whitespace variants.
    pattern = re.compile(
        r"confidence\s*:\s*fingerprint\.allTerms\.length\s*>=\s*4\s*"
        r"\?\s*\.?82\s*:\s*\.?62\s*,"
    )

    replacement = (
        "confidence: fingerprint.allTerms.length >= 4 ? 0.82 : 0.62,"
    )

    s, count = pattern.subn(replacement, s, count=1)

    if count == 0:
        # Accept an already-correct file.
        if re.search(
            r"confidence\s*:\s*fingerprint\.allTerms\.length\s*>=\s*4\s*"
            r"\?\s*0\.82\s*:\s*0\.62\s*,",
            s,
        ):
            print("ALREADY FIXED: project_resolver confidence ternary")
            return False
        raise SystemExit(
            "ERROR: project_resolver confidence pattern not found. "
            "No project_resolver changes written."
        )

    b = backup(p)
    p.write_text(s)
    print("PASS: fixed project_resolver confidence ternary")
    print("  backup:", b)
    return s != original


def patch_widget_test(root: Path) -> bool:
    p = root / "test/widget_test.dart"
    if not p.exists():
        raise SystemExit(f"ERROR: missing {p}")

    s = p.read_text()

    # If this is already a Brain2-specific test, leave it alone.
    if "Brain2 root widget is available" in s:
        print("ALREADY FIXED: widget_test.dart")
        return False

    # We only auto-replace the stale Flutter template test, not an intentional
    # project-specific test.
    stale_markers = (
        "const MyApp()",
        "Counter increments smoke test",
        "find.byIcon(Icons.add)",
    )
    if not any(marker in s for marker in stale_markers):
        raise SystemExit(
            "ERROR: widget_test.dart is not the known stale Flutter template. "
            "Refusing to overwrite a possibly intentional test."
        )

    replacement = """import 'package:flutter_test/flutter_test.dart';
import 'package:brain2_ai_miner_mobile/app/brain2_app.dart';

void main() {
  test('Brain2 root widget is available', () {
    const app = Brain2App();
    expect(app, isA<Brain2App>());
  });
}
"""

    b = backup(p)
    p.write_text(replacement)
    print("PASS: replaced stale MyApp/Counter widget test")
    print("  backup:", b)
    return True


def cleanup_memory_diagnostics(root: Path) -> bool:
    p = root / "lib/intelligence/memory_diagnostics.dart"
    if not p.exists():
        return False

    s = p.read_text()
    original = s
    s = s.replace("import '../core/identity.dart';\n", "", 1)

    if s != original:
        b = backup(p)
        p.write_text(s)
        print("PASS: removed unused memory_diagnostics identity import")
        print("  backup:", b)
        return True

    return False


def main() -> None:
    root = Path(sys.argv[1] if len(sys.argv) > 1 else ".").resolve()

    required = [
        root / "pubspec.yaml",
        root / "lib",
        root / "test",
    ]
    if not all(p.exists() for p in required):
        raise SystemExit(
            f"ERROR: {root} does not look like the Brain2 Flutter project root."
        )

    print("Brain2 Mobile Patch 08 - build blocker repair")
    print("root:", root)

    changed = False
    changed |= patch_project_resolver(root)
    changed |= patch_widget_test(root)
    changed |= cleanup_memory_diagnostics(root)

    print()
    if changed:
        print("PASS patch_08_fix_build_errors")
    else:
        print("NO-OP patch_08_fix_build_errors (already applied)")
    print()
    print("Next:")
    print("  dart format lib/intelligence/project_resolver.dart "
          "lib/intelligence/memory_diagnostics.dart test/widget_test.dart")
    print("  flutter analyze")
    print("  flutter run")


if __name__ == "__main__":
    main()
