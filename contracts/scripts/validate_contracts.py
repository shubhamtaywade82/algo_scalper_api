#!/usr/bin/env python3
"""Validate every fixture against its JSON Schema (draft 2020-12).

Contract-test policy (contracts/README.md): a fixture that fails validation means
the contract is broken, in either the schema or the example. Both services run
the same fixtures through their own validators (json_schemer here, a Node
validator in the agent) once the G0 CI wiring lands; this script is the
standalone canonical check inside this repo.
"""
import json
import sys
from pathlib import Path

from jsonschema import Draft202012Validator, FormatChecker

BASE = Path(__file__).resolve().parent.parent
SCHEMAS = BASE / "schemas"
FIXTURES = BASE / "fixtures"

PAIRS = sorted(
    p.name.replace(".schema.json", "") for p in SCHEMAS.glob("*.schema.json")
)


def main() -> int:
    failures = 0
    for name in PAIRS:
        schema_path = SCHEMAS / f"{name}.schema.json"
        fixture_path = FIXTURES / f"{name}.example.json"
        if not fixture_path.exists():
            print(f"FAIL {name}: missing fixture {fixture_path}")
            failures += 1
            continue
        schema = json.loads(schema_path.read_text())
        fixture = json.loads(fixture_path.read_text())
        Draft202012Validator.check_schema(schema)
        validator = Draft202012Validator(schema, format_checker=FormatChecker())
        errors = sorted(validator.iter_errors(fixture), key=lambda e: e.json_path)
        if errors:
            failures += 1
            for err in errors:
                print(f"FAIL {name} at {err.json_path}: {err.message}")
        else:
            print(f"OK   {name}: fixture validates against schema")

    orphan_fixtures = sorted(
        p.name.replace(".example.json", "")
        for p in FIXTURES.glob("*.example.json")
        if p.name.replace(".example.json", "") not in PAIRS
    )
    for orphan in orphan_fixtures:
        print(f"FAIL orphan fixture without schema: {orphan}")
        failures += 1

    if failures:
        print(f"\n{failures} failure(s)")
        return 1
    print(f"\nAll {len(PAIRS)} contract pairs valid.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
