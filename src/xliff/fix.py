#!/usr/bin/env python3
import sys
import re

conf_start_re   = re.compile(r'<trans-unit[^>]*\bid="[^"]*\.configuration\.title"')
normal_start_re = re.compile(r'<trans-unit[^>]*\bid="[^"]*\.normalTitle"')
source_re       = re.compile(r'<source>(.*?)</source>')
target_re       = re.compile(r'<target>(.*?)</target>')

def find_block_end(lines, start_idx):
    depth = 0
    for j in range(start_idx, len(lines)):
        if '<trans-unit' in lines[j]:
            depth += 1
        if '</trans-unit>' in lines[j]:
            depth -= 1
            if depth == 0:
                return j
    return start_idx

def process(lines):
    out        = []
    i          = 0
    saved_src  = saved_tgt = None

    while i < len(lines):
        line = lines[i]

        # capture .configuration.title
        if saved_src is None and conf_start_re.search(line):
            end   = find_block_end(lines, i)
            block = lines[i:end+1]
            for ln in block:
                m = source_re.search(ln)
                if m: saved_src = m.group(1)
                m = target_re.search(ln)
                if m: saved_tgt = m.group(1)
            i = end + 1
            continue

        # patch .normalTitle
        if saved_src is not None and normal_start_re.search(line):
            end       = find_block_end(lines, i)
            block     = lines[i:end+1]
            patched   = []
            orig_norm = None
            quoted_re = None

            for ln in block:
                m = source_re.search(ln)
                if m:
                    orig_norm = m.group(1)
                    quoted_re = re.compile(r'"' + re.escape(orig_norm) + r'"')
                    ln = source_re.sub(f'<source>{saved_src}</source>', ln, count=1)

                m = target_re.search(ln)
                if m:
                    ln = target_re.sub(f'<target>{saved_tgt}</target>', ln, count=1)

                if quoted_re:
                    ln = quoted_re.sub(f'"{saved_src}"', ln)

                patched.append(ln)

            out.extend(patched)
            saved_src = saved_tgt = None
            i = end + 1
            continue

        # everything else
        out.append(line)
        i += 1

    return out

def main():
    files = sys.argv[1:]
    if files:
        for fname in files:
            with open(fname, encoding='utf-8') as f:
                lines = f.readlines()
            new_lines = process(lines)
            with open(fname, 'w', encoding='utf-8') as f:
                f.writelines(new_lines)
    else:
        lines = sys.stdin.readlines()
        sys.stdout.writelines(process(lines))

if __name__ == '__main__':
    main()
