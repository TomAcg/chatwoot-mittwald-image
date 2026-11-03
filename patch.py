#!/usr/bin/env python3
"""Fetch config/llm.yml and config/llm_models.json for a Chatwoot release and apply the Mittwald patches.

Usage: python3 patch.py v4.19.1
Writes llm.yml and llm_models.json next to this script.
"""
import re
import sys
import urllib.request
from pathlib import Path

MODEL = 'gpt-oss-120b'
# Features that need vision, audio or embeddings stay on their upstream models.
SKIP_FEATURES = {'pdf_faq_generation', 'audio_transcription', 'call_announcement', 'help_center_search'}
MODEL_BLOCK = f"""  {MODEL}:
    provider: openai
    display_name: 'GPT-OSS 120B (Mittwald)'
    credit_multiplier: 1
"""
HERE = Path(__file__).resolve().parent


def fetch(tag, name):
    url = f'https://raw.githubusercontent.com/chatwoot/chatwoot/{tag}/config/{name}'
    with urllib.request.urlopen(url) as response:
        return response.read().decode()


def patch_feature(block):
    start = block.index('[', block.index('models:'))
    end = block.index(']', start)
    models = block[start:end]
    if '\n' in models:
        indent = re.search(r'\n( +)\S', models).group(1)
        models = models.rstrip() + f'\n{indent}{MODEL},\n' + ' ' * (len(indent) - 2)
    else:
        models = models + f', {MODEL}'
    block = block[:start] + models + block[end:]
    return re.sub(r'^(    default: ).*$', rf'\g<1>{MODEL}', block, count=1, flags=re.M)


def patch_llm_yml(text):
    head, features = text.split('\nfeatures:\n', 1)
    head = head.rstrip('\n') + '\n' + MODEL_BLOCK
    # Split before each two-space feature key, keeping comments attached to the following feature.
    blocks = re.split(r'(?m)^(?=(?:  #.*\n)*  [a-z_]+:\n)', features)
    patched = []
    for block in blocks:
        key = re.search(r'(?m)^  ([a-z_]+):$', block)
        if key and key.group(1) not in SKIP_FEATURES:
            block = patch_feature(block)
        patched.append(block)
    return head + '\nfeatures:\n' + ''.join(patched)


def patch_llm_models(text):
    old = f'"id": "{MODEL}",\n    "name": "{MODEL}",\n    "provider": "azure",'
    if text.count(old) != 1:
        sys.exit(f'llm_models.json: expected exactly one azure entry for {MODEL}')
    return text.replace(old, old.replace('"azure"', '"openai"'))


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    tag = sys.argv[1]
    (HERE / 'llm.yml').write_text(patch_llm_yml(fetch(tag, 'llm.yml')))
    (HERE / 'llm_models.json').write_text(patch_llm_models(fetch(tag, 'llm_models.json')))
    print(f'Patched llm.yml and llm_models.json from {tag}')


if __name__ == '__main__':
    main()
