#!/usr/bin/env python3
"""Local-only synthetic benchmark. Heuristics flag review items, not semantic correctness."""
import argparse
import json
import re
import subprocess
import urllib.request
from pathlib import Path

BASE = 'http://127.0.0.1:11434/api/'

class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        raise RuntimeError('Redirect refused: benchmark must stay local')


def request(endpoint, payload=None):
    body = None if payload is None else json.dumps(payload).encode()
    req = urllib.request.Request(BASE + endpoint, data=body, headers={'Content-Type': 'application/json'})
    with urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect()).open(req, timeout=600) as response:
        return json.load(response)


def audit(text, case):
    citations = [int(n) for n in re.findall(r'\[L(\d+)\]', text)]
    return {
        'invalid_citations': sorted(set(n for n in citations if n < 1 or n > len(case['lines']))),
        'no_citations': not citations,
        'missing_literal_anchors_for_review': [s for s in case['anchors'] if s.casefold() not in text.casefold()],
        'synthetic_secret_leaked': case['secret'] in text,
        'manual_review_required': True,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--model', required=True)
    parser.add_argument('--filter-cli', type=Path, help='Compiled context_filter.swift using the current CleanerCore')
    parser.add_argument('--grounded', action='store_true', help='Render cited source excerpts using the application core')
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    def sanitize(text):
        if args.filter_cli:
            return subprocess.run([str(args.filter_cli)], input=text, text=True, capture_output=True, check=True).stdout
        return text
    models = request('tags').get('models', [])
    eligible = [m['name'] for m in models if not m.get('remote_host') and not m.get('remote_model') and 'cloud' not in m['name'].lower()]
    if args.model not in eligible:
        raise RuntimeError('Choose an installed local model')
    details = request('show', {'model': args.model})
    if details.get('remote_host') or details.get('remote_model') or details.get('details', {}).get('format') != 'gguf':
        raise RuntimeError('Only local GGUF models are allowed')
    args.output.mkdir(parents=True, exist_ok=False, mode=0o700)
    cases = json.loads(Path(__file__).with_name('cases.json').read_text())
    # Read the app's exact prompt to avoid testing a divergent instruction.
    source = Path(__file__).resolve().parents[2] / 'Sources/CleanerCore/Agents.swift'
    system = source.read_text().split('public static let system = """', 1)[1].split('"""', 1)[0].strip()
    report = {'model': args.model, 'semantic_quality': 'requires human review', 'app_redaction': bool(args.filter_cli), 'grounded': args.grounded, 'cases': []}
    for case in cases:
        transcript = '\n'.join(f'[L{i}] {line}' for i, line in enumerate(case['lines'], 1))
        result = request('generate', {'model': args.model, 'system': system,
            'prompt': 'Agent: codex. Compression: Бережный. Extract handoff notes for part 1. Preserve source line citations.\n<transcript>\n' + sanitize(transcript) + '\n</transcript>',
            'stream': False, 'options': {'temperature': 0.1, 'num_ctx': 16384, 'num_predict': 4096}, 'keep_alive': '5m'})
        text = sanitize(result.get('response', ''))
        if result.get('error') or not text.strip():
            raise RuntimeError(result.get('error', 'Empty response'))
        if args.grounded:
            if not args.filter_cli: raise RuntimeError('--grounded requires --filter-cli')
            text = subprocess.run([str(args.filter_cli), '--ground'], input=json.dumps({'proposal': text, 'source': transcript}), text=True, capture_output=True, check=True).stdout
        output = args.output / (case['id'] + '.md')
        output.write_text(text); output.chmod(0o600)
        report['cases'].append({'id': case['id'], 'checks': audit(text, case),
            'duration_ns': result.get('total_duration'), 'eval_count': result.get('eval_count'),
            'manual_rubric': case['rubric']})
        report_file = args.output / 'report.json'
        report_file.write_text(json.dumps(report, ensure_ascii=False, indent=2)); report_file.chmod(0o600)
    print(args.output / 'report.json')

if __name__ == '__main__':
    main()
