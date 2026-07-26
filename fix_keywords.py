import os
import json
import re

arb_files = ['lib/l10n/app_en.arb', 'lib/l10n/app_ar.arb']

replacements = {
    'continue': 'continueText',
    'new': 'newText'
}

for arb in arb_files:
    if os.path.exists(arb):
        with open(arb, 'r', encoding='utf-8') as f:
            data = json.load(f)
        
        new_data = {}
        for k, v in data.items():
            if k in replacements:
                new_data[replacements[k]] = v
            else:
                new_data[k] = v
                
        with open(arb, 'w', encoding='utf-8') as f:
            json.dump(new_data, f, indent=2, ensure_ascii=False)

def process_file(filepath):
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()

    new_content = content
    for old_k, new_k in replacements.items():
        # Match context.l10n.continue or context.l10n.new
        new_content = re.sub(rf'\bcontext\.l10n\.{old_k}\b', f'context.l10n.{new_k}', new_content)

    if new_content != content:
        with open(filepath, 'w', encoding='utf-8') as f:
            f.write(new_content)

for root, _, files in os.walk('lib'):
    for file in files:
        if file.endswith('.dart'):
            process_file(os.path.join(root, file))

print("Fixed keywords.")
