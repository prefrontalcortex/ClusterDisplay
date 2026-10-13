#!/usr/bin/env python3
"""Scans the lines ADDED by a range of commits (or the whole history) for secrets and private data.

No third-party packages, no network access.  Rules are modelled on common secret scanners but this is not a
replacement for one: it only finds the patterns listed below.

Usage:
    scan-secrets.py --range <base>..<head>     scan commits in a range (CI: pull request or push)
    scan-secrets.py --all                      scan the whole history

Exit code: 1 if a SECRET rule matched, 0 otherwise.  WARN rules (private mail address, local user path, author
address) are printed but do not fail the run, unless --strict is given.
A line containing the marker `secretscan:allow` is ignored.  Matched values are masked in the output.
"""
import argparse
import re
import subprocess
import sys

SECRET_RULES = {
    'private-key':       r'-----BEGIN [A-Z ]*PRIVATE KEY-----',
    'aws-access-key':    r'\b(AKIA|ASIA)[0-9A-Z]{16}\b',
    'github-token':      r'\b(ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{30,}\b|github_pat_[A-Za-z0-9_]{30,}',
    'slack-token':       r'\bxox[abprs]-[A-Za-z0-9-]{10,}',
    'google-api-key':    r'\bAIza[0-9A-Za-z_-]{35}\b',
    'openai-style-key':  r'\bsk-[A-Za-z0-9]{32,}\b',
    'stripe-key':        r'\b[sr]k_(live|test)_[0-9A-Za-z]{20,}',
    'jwt':               r'\beyJ[A-Za-z0-9_-]{15,}\.eyJ[A-Za-z0-9_-]{15,}\.[A-Za-z0-9_-]{10,}',
    'url-with-password': r'[a-z][a-z0-9+.-]*://[^/\s:@]{2,}:[^/\s:@]{3,}@[^/\s]+',
    'azure-storage-key': r'AccountKey=[A-Za-z0-9+/=]{40,}',
    'generic-secret':    r'(?i)\b(password|passwd|pwd|secret|api[_-]?key|access[_-]?token|auth[_-]?token|client[_-]?secret)\b["\']?\s*[:=]\s*["\']([A-Za-z0-9/+_\-.!@#$%^&*]{8,})["\']',
    'unity-credentials': r'(?i)UNITY_(SERIAL|PASSWORD|EMAIL)\s*[:=]\s*\S{4,}',
}
WARN_RULES = {
    'private-mail-address': r'[A-Za-z0-9._%+-]+@(gmail|googlemail|hotmail|outlook|live|yahoo|gmx|web|icloud|protonmail|t-online)\.[a-z]{2,}',
    'local-user-path':      r'\b[A-Za-z]:\\+Users\\+(?!Public\b|Default\b|All Users\b|<)[A-Za-z0-9._-]{2,}',
}
FREEMAIL = re.compile(r'@(gmail|googlemail|hotmail|outlook|live|yahoo|gmx|web|icloud|protonmail|t-online)\.[a-z]{2,}$', re.I)
INTERNAL_HOST = re.compile(r'@[^.@]+$|\.(local|lan|office|internal|corp|home)$', re.I)
SKIP_EXT = ('.fbx', '.png', '.jpg', '.jpeg', '.gif', '.psd', '.dll', '.so', '.exe', '.zip', '.mp4', '.wav', '.tga',
            '.exr', '.hdr', '.tif', '.pdb', '.ttf', '.otf', '.meta')
ALLOW_MARK = 'secretscan:allow'


def mask(value):
    return f'{value[:3]}*** ({len(value)} chars)'


def main():
    ap = argparse.ArgumentParser()
    g = ap.add_mutually_exclusive_group(required=True)
    g.add_argument('--range')
    g.add_argument('--all', action='store_true')
    ap.add_argument('--strict', action='store_true', help='also fail on warnings')
    a = ap.parse_args()

    rev = ['--all'] if a.all else [a.range]
    cmd = ['git', 'log', *rev, '-p', '-U0', '--no-color', '--text', '--no-ext-diff',
           '--format=@@COMMIT %h %ae|%ce', '--'] + ['.'] + [f':!*{e}' for e in SKIP_EXT]
    p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    secrets, warns, authors = {}, {}, {}
    commit = file = None
    compiled = [(n, re.compile(r), True) for n, r in SECRET_RULES.items()] + \
               [(n, re.compile(r), False) for n, r in WARN_RULES.items()]
    for raw in p.stdout:
        line = raw.decode('utf-8', 'replace').rstrip('\r\n')
        if line.startswith('@@COMMIT '):
            _, commit, addrs = line.split(' ', 2)
            for addr in set(addrs.split('|')):
                if addr and not addr.endswith('noreply.github.com') and (FREEMAIL.search(addr) or INTERNAL_HOST.search(addr)):
                    authors.setdefault(commit, set()).add(addr)
            continue
        if line.startswith('+++ b/'):
            file = line[6:]
            continue
        if not line.startswith('+') or line.startswith('+++') or len(line) > 3000 or ALLOW_MARK in line:
            continue
        body = line[1:]
        for name, rx, is_secret in compiled:
            m = rx.search(body)
            if m:
                val = m.group(m.lastindex) if (name == 'generic-secret' and m.lastindex) else m.group(0)
                (secrets if is_secret else warns).setdefault((name, file), []).append((commit, mask(val)))
    err = p.stderr.read().decode('utf-8', 'replace').strip()
    if p.wait() != 0:
        print(f'git log failed: {err}', file=sys.stderr)
        return 2

    for (name, file), lst in secrets.items():
        print(f'SECRET {name:18} {file}  [{len(lst)}x, first in {lst[0][0]}]  e.g. {lst[0][1]}')
    for (name, file), lst in warns.items():
        print(f'WARN   {name:21} {file}  [{len(lst)}x, first in {lst[0][0]}]  e.g. {lst[0][1]}')
    for c, addrs in authors.items():
        print(f'WARN   author-address         commit {c}: {len(addrs)} private/internal address(es) in author or committer')
    print(f'Result: {len(secrets)} secret finding(s), {len(warns)} warning(s), {len(authors)} commit(s) with private author address')
    if secrets or (a.strict and (warns or authors)):
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
