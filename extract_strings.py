import os
import re
import json
import string

def to_camel_case(text):
    # Remove non-alphanumeric except spaces
    clean = re.sub(r'[^a-zA-Z0-9\s]', '', text)
    words = clean.split()
    if not words:
        return "emptyString"
    camel = words[0].lower() + ''.join(w.capitalize() for w in words[1:])
    # Ensure it starts with a letter
    if not camel[0].isalpha():
        camel = "s" + camel
    return camel

strings_dict = {}

def process_file(filepath):
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()

    # We need to find Text('...'), hintText: '...', labelText: '...'
    # Let's use a regex that finds single quoted strings that don't contain $ (no interpolation)
    # matching: Text('...') or Text("...")
    # matching: hintText: '...'
    # matching: label: '...' or label: Text('...')
    
    # regex for Text('string')
    pattern = r"(Text\(\s*)'([^'\$]+)'"
    def replacer(match):
        prefix = match.group(1)
        text = match.group(2)
        key = to_camel_case(text)
        if key not in strings_dict:
            strings_dict[key] = text
        return f"{prefix}context.l10n.{key}"
    
    new_content = re.sub(pattern, replacer, content)

    # regex for hintText: 'string'
    pattern2 = r"(hintText\s*:\s*)'([^'\$]+)'"
    def replacer2(match):
        prefix = match.group(1)
        text = match.group(2)
        key = to_camel_case(text)
        if key not in strings_dict:
            strings_dict[key] = text
        return f"{prefix}context.l10n.{key}"
    new_content = re.sub(pattern2, replacer2, new_content)

    # regex for labelText: 'string'
    pattern3 = r"(labelText\s*:\s*)'([^'\$]+)'"
    new_content = re.sub(pattern3, replacer2, new_content)

    # regex for tooltip: 'string'
    pattern4 = r"(tooltip\s*:\s*)'([^'\$]+)'"
    new_content = re.sub(pattern4, replacer2, new_content)

    # Also match Text("...")
    pattern5 = r'(Text\(\s*)"([^"\$]+)"'
    new_content = re.sub(pattern5, replacer, new_content)

    if new_content != content:
        # Also need to add import for localization if context.l10n is used
        # We assume context.l10n is defined as an extension in lib/core/utils/l10n_extension.dart
        # Let's add import if not present
        if 'context.l10n' in new_content and 'l10n_extension.dart' not in new_content:
            # find last import
            last_import = new_content.rfind('import ')
            if last_import != -1:
                end_of_line = new_content.find('\n', last_import)
                new_content = new_content[:end_of_line+1] + "import 'package:multi_vendor/core/utils/l10n_extension.dart';\n" + new_content[end_of_line+1:]
        
        with open(filepath, 'w', encoding='utf-8') as f:
            f.write(new_content)

for root, _, files in os.walk('lib'):
    for file in files:
        if file.endswith('.dart'):
            process_file(os.path.join(root, file))

# Write the arb file
os.makedirs('lib/l10n', exist_ok=True)
arb_dict = {"@@locale": "en"}
for k, v in strings_dict.items():
    arb_dict[k] = v

with open('lib/l10n/app_en.arb', 'w', encoding='utf-8') as f:
    json.dump(arb_dict, f, indent=2, ensure_ascii=False)

print(f"Extracted {len(strings_dict)} strings.")
