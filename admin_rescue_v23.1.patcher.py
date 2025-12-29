#!/usr/bin/env python3
"""
apply_unified_patch.py

Apply a unified diff patch to a text file safely.

Usage:
  python3 apply_unified_patch.py original_file patch_file

Behavior:
- Creates a timestamped backup of the original file
- Applies unified diff hunks
- Aborts if any hunk fails to apply cleanly
"""

import sys
import time
from pathlib import Path

def die(msg):
    print(f"ERROR: {msg}", file=sys.stderr)
    sys.exit(1)

def read_lines(path):
    try:
        return path.read_text(encoding="utf-8").splitlines(keepends=True)
    except Exception as e:
        die(f"Failed to read {path}: {e}")

def write_lines(path, lines):
    try:
        path.write_text("".join(lines), encoding="utf-8")
    except Exception as e:
        die(f"Failed to write {path}: {e}")

def apply_patch(original_lines, patch_lines):
    result = []
    orig_idx = 0
    patch_idx = 0

    while patch_idx < len(patch_lines):
        line = patch_lines[patch_idx]

        # Skip diff headers
        if line.startswith(("---", "+++", "diff ", "index ")):
            patch_idx += 1
            continue

        if line.startswith("@@"):
            # Parse hunk header
            try:
                header = line
                _, ranges, _ = header.split("@@", 2)
                old_range, _ = ranges.strip().split(" ", 1)
                old_start = int(old_range.split(",")[0].lstrip("-")) - 1
            except Exception:
                die(f"Malformed hunk header: {line.strip()}")

            # Copy unchanged lines before hunk
            while orig_idx < old_start:
                result.append(original_lines[orig_idx])
                orig_idx += 1

            patch_idx += 1

            # Apply hunk
            while patch_idx < len(patch_lines):
                pline = patch_lines[patch_idx]

                if pline.startswith("@@"):
                    break

                if pline.startswith(" "):
                    if orig_idx >= len(original_lines) or original_lines[orig_idx] != pline[1:]:
                        die("Context mismatch while applying patch")
                    result.append(original_lines[orig_idx])
                    orig_idx += 1

                elif pline.startswith("-"):
                    if orig_idx >= len(original_lines) or original_lines[orig_idx] != pline[1:]:
                        die("Removal mismatch while applying patch")
                    orig_idx += 1

                elif pline.startswith("+"):
                    result.append(pline[1:])

                else:
                    die(f"Unexpected patch line: {pline.strip()}")

                patch_idx += 1

        else:
            die(f"Unexpected patch content: {line.strip()}")

    # Append remaining original lines
    result.extend(original_lines[orig_idx:])
    return result

def main():
    if len(sys.argv) != 3:
        die("Usage: python3 apply_unified_patch.py <original_file> <patch_file>")

    original_path = Path(sys.argv[1])
    patch_path = Path(sys.argv[2])

    if not original_path.exists():
        die(f"Original file not found: {original_path}")
    if not patch_path.exists():
        die(f"Patch file not found: {patch_path}")

    original_lines = read_lines(original_path)
    patch_lines = read_lines(patch_path)

    print("Applying patch...")
    patched_lines = apply_patch(original_lines, patch_lines)

    backup_path = original_path.with_suffix(
        original_path.suffix + f".bak.{int(time.time())}"
    )
    original_path.rename(backup_path)
    print(f"Backup created: {backup_path}")

    write_lines(original_path, patched_lines)
    print("Patch applied successfully.")

if __name__ == "__main__":
    main()

