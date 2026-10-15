#!/usr/bin/env python3
"""Records how real Vim answers single normal-mode commands, as a fixture for VimGoldenTests.

Each case: a random ASCII document, a cursor position and one command. Vim runs it headless
(`vim -u NONE -es`, with modern 'nojoinspaces' and the engine's smartcase search) and the resulting
text and cursor are stored. MacMD's engine must produce the same.

Usage: scripts/generate-vim-golden.py [count] [seed] > Packages/MacMDKit/Tests/MacMDKitTests/Fixtures/vim-golden.json
"""
import json
import os
import random
import subprocess
import sys
import tempfile

WORDS = ["one", "two", "three", "a", "x1", "foo_bar", "end.", "(paren)", '"quoted"', "it's", "--", "Hello,", "w0rd"]

# Each command is a list of parts. Vim runs every part in its own `:normal!`, so a part that fails (a beep)
# doesn't cancel the rest, which is how MacMD's engine behaves too.
COMMANDS = [
    "x", "2x", "X", "2X", "D", "dd", "2dd", "dw", "d2w", "2dw", "de", "db", "d$", "d0", "d^", "dj", "dk", "dG", "dgg",
    "yy|p", "yy|P", "yw|P", "dd|p", "x|p", "dw|P", "yiw|P", "J", "3J", "~", "3~", "rZ", "3rZ",
    "cwZZ<Esc>", "c2wZZ<Esc>", "ccZZ<Esc>", "CZZ<Esc>", "sZ<Esc>", "SZ<Esc>", "ciwZ<Esc>", "cawZ<Esc>",
    "diw", "daw", "diW", "daW", 'di"', 'da"', "di(", "da(", "ci(Z<Esc>", "dip", "dap", "yip|P",
    "oZ<Esc>", "OZ<Esc>", "AZ<Esc>", "IZ<Esc>", "aZ<Esc>", "iZ<Esc>",
    "w", "3w", "b", "e", "W", "B", "E", "0", "^", "$", "gg", "G", "2G", "fo", "Fo", "to", "To", "fo|;", "to|;", "fo|,",
    "}", "{", "x|.", "dw|.", "AZ<Esc>|j|.", "vjd", "vwd", "Vjd", "Vd", "vey|P", "viwd", "v$d", "vjy", "veU", "ve~",
]


def random_document(rng):
    lines = []
    for _ in range(rng.randint(1, 6)):
        if rng.random() < 0.15:
            lines.append("")
            continue
        indent = " " * rng.choice([0, 0, 0, 2, 4])
        lines.append(indent + " ".join(rng.choice(WORDS) for _ in range(rng.randint(1, 6))))
    return "\n".join(lines) + "\n"


def parts(command):
    """Splits a command at "|" into the parts run separately: "fo|;" -> ["fo", ";"]."""
    return command.split("|")


def tokens(keys):
    """Splits "cwZZ<Esc>" into ["c", "w", "Z", "Z", "<Esc>"]."""
    result, index = [], 0
    while index < len(keys):
        if keys.startswith("<Esc>", index):
            result.append("<Esc>")
            index += 5
        else:
            result.append(keys[index])
            index += 1
    return result


def run_vim(text, line, col, command):
    with tempfile.TemporaryDirectory() as folder:
        path = os.path.join(folder, "doc.txt")
        pos = os.path.join(folder, "pos.txt")
        with open(path, "w") as handle:
            handle.write(text)
        normals = []
        for part in parts(command):
            escaped = part.replace("\\", "\\\\").replace('"', '\\"').replace("<Esc>", "\\<Esc>")
            normals += ["-c", f'execute "normal! {escaped}"']
        subprocess.run(
            ["vim", "-u", "NONE", "-i", "NONE", "-N", "-n", "-es",
             "-c", "set nojoinspaces ignorecase smartcase autoindent",
             "-c", f"call cursor({line}, {col})",
             *normals,
             "-c", f"call writefile([line('.'), col('.')], '{pos}')",
             "-c", "wq", path],
            check=False, timeout=10, capture_output=True)
        with open(path) as handle:
            result = handle.read()
        with open(pos) as handle:
            end_line, end_col = (int(value) for value in handle.read().split())
    return result, end_line, end_col


def main():
    count = int(sys.argv[1]) if len(sys.argv) > 1 else 600
    rng = random.Random(int(sys.argv[2]) if len(sys.argv) > 2 else 20261015)
    cases = []
    while len(cases) < count:
        text = random_document(rng)
        lines = text.split("\n")[:-1]
        line = rng.randint(1, len(lines))
        col = rng.randint(1, max(len(lines[line - 1]), 1))
        command = rng.choice(COMMANDS)
        # Cases where headless Vim differs from typing in Vim, or Vim quirks MacMD doesn't copy:
        word_object = any(part in command for part in ("iw", "aw", "iW", "aW"))
        if word_object and lines[line - 1].strip() == "":
            continue  # word objects on empty lines select neighbouring lines
        rest = text[sum(len(l) + 1 for l in lines[: line - 1]) + col - 1:]
        if command.startswith("ve") and not rest[1:].strip():
            continue  # same: `e` fails at the end of the text after moving, and `:normal` drops the rest
        if (command[0] in "vV" or command in ("J", "3J")) and line == len(lines):
            continue  # `:normal` aborts after a failing motion; typed, Vim beeps and still applies the operator
        result, end_line, end_col = run_vim(text, line, col, command)
        keys = command.replace("|", "")
        cases.append({
            "text": text, "line": line, "col": col, "keys": tokens(keys),
            "result": result, "endLine": end_line, "endCol": end_col,
        })
    json.dump(cases, sys.stdout, indent=1)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
