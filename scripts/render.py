#!/usr/bin/env python3
"""Render a scaffold locally, the way scaffold-operator does.

Mirrors scaffold-operator's renderTemplate: *.tpl files have the suffix
stripped and exact {{ param }} placeholders substituted; every other file is
copied byte-for-byte. For local validation only; the operator is the real
renderer.

usage: render.py <scaffold> <out-dir> key=value...
  e.g. render.py golang-service /tmp/orders componentName=orders \
         repositoryName=orders owner=entr0pian componentOwner=team-a
"""
import pathlib
import re
import sys

PLACEHOLDER = re.compile(rb"\{\{\s*([A-Za-z0-9_]+)\s*\}\}")


def main() -> None:
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    scaffold, out = sys.argv[1], pathlib.Path(sys.argv[2])
    params = dict(arg.split("=", 1) for arg in sys.argv[3:])

    src = pathlib.Path(__file__).resolve().parent.parent / "templates" / scaffold / "template"
    for path in sorted(p for p in src.rglob("*") if p.is_file()):
        rel = path.relative_to(src)
        content = path.read_bytes()
        if rel.suffix == ".tpl":
            rel = rel.with_suffix("")
            # Unknown names are left in place, as the operator does.
            content = PLACEHOLDER.sub(
                lambda m: params.get(m[1].decode(), m[0].decode()).encode(), content
            )
        dest = out / rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(content)


if __name__ == "__main__":
    main()
