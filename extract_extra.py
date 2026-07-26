import os
import re
import json

def to_camel_case(text):
    clean = re.sub(r'[^a-zA-Z0-9\s]', '', text)
    words = clean.split()
    if not words:
        return "emptyString"
    camel = words[0].lower() + ''.join(w.capitalize() for w in words[1:])
    if not camel[0].isalpha():
        camel = "s" + camel
    return camel

# Load existing arb to avoid duplicate keys (and keep existing translations)
arb_path = 'lib/l10n/app_en.arb'
existing_en = {}
if os.path.exists(arb_path):
    with open(arb_path, 'r', encoding='utf-8') as f:
        existing_en = json.load(f)

extracted_dict = {}

def is_user_facing(s, line):
    s = s.strip()
    if not s:
        return False
    if '$' in s: # skip interpolation for safe regex replacement
        return False
    if s.startswith('package:') or s.startswith('dart:') or s.startswith('/') or s.endswith('.png') or s.endswith('.jpg') or s.endswith('.jpeg') or s.endswith('.svg') or s.endswith('.json'):
        return False
    if re.match(r'^[a-z_]+$', s):  # database columns/tables
        return False
    if s in ['id', 'email', 'password', 'signout', 'banner', 'coupon', 'percentage', 'fixed', 'open', 'closed', 'true', 'false', 'null']:
        return False
    if re.match(r'^[A-Z0-9_\-]+$', s):
        return False
    if 'import ' in line or 'part ' in line:
        return False
    if any(c.isalpha() for c in s) and (' ' in s or len(s) > 3):
        return True
    return False

def replace_in_file(filepath):
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
        
    original = content
    
    # We want to match:
    # 1. Text('string') or Text("string")
    # 2. label: 'string' or label: "string" (if it is a parameter of a widget, but to be safe let's restrict to common ones or just generic match if it is user facing)
    # 3. title: 'string' or title: "string" (excluding router paths, which we filtered in is_user_facing)
    # 4. message: 'string' or message: "string"
    # 5. showSnack(context, 'string')
    
    # Let's match patterns like:
    # (Text\(|label\s*:\s*|title\s*:\s*|message\s*:\s*|hintText\s*:\s*|labelText\s*:\s*|showSnack\(\s*context\s*,\s*|TextButton\(\s*child\s*:\s*Text\(\s*|ElevatedButton\(\s*child\s*:\s*Text\(\s*|FilledButton\(\s*child\s*:\s*Text\(\s*)
    
    patterns = [
        # Text('...')
        (r"(\bText\(\s*)'([^'\$]+)'", r"\1context.l10n.\bKEY\b"),
        (r'(\bText\(\s*)"([^"\$]+)"', r'\1context.l10n.\bKEY\b'),
        # label: '...'
        (r"(\blabel\s*:\s*)'([^'\$]+)'", r"\1context.l10n.\bKEY\b"),
        (r'(\blabel\s*:\s*)"([^"\$]+)"', r'\1context.l10n.\bKEY\b'),
        # title: '...'
        (r"(\btitle\s*:\s*)'([^'\$]+)'", r"\1context.l10n.\bKEY\b"),
        (r'(\btitle\s*:\s*)"([^"\$]+)"', r'\1context.l10n.\bKEY\b'),
        # message: '...'
        (r"(\bmessage\s*:\s*)'([^'\$]+)'", r"\1context.l10n.\bKEY\b"),
        (r'(\bmessage\s*:\s*)"([^"\$]+)"', r'\1context.l10n.\bKEY\b'),
        # showSnack(context, '...')
        (r"(showSnack\(\s*context\s*,\s*)'([^'\$]+)'", r"\1context.l10n.\bKEY\b"),
        (r'(showSnack\(\s*context\s*,\s*)"([^"\$]+)"', r'\1context.l10n.\bKEY\b'),
    ]
    
    new_content = content
    for pattern, repl in patterns:
        def replacer(match):
            prefix = match.group(1)
            text = match.group(2)
            if not is_user_facing(text, match.group(0)):
                return match.group(0)
            
            # Find if this string already has a key in existing_en
            key = None
            for k, v in existing_en.items():
                if v == text and k != '@@locale':
                    key = k
                    break
            
            if not key:
                key = to_camel_case(text)
                # Ensure key is unique
                counter = 1
                orig_key = key
                while key in existing_en or key in extracted_dict:
                    key = f"{orig_key}{counter}"
                    counter += 1
            
            extracted_dict[key] = text
            return repl.replace(r'\bKEY\b', key).replace(r'\1', prefix)
            
        new_content = re.sub(pattern, replacer, new_content)
        
    if new_content != original:
        # Import extension if needed
        if 'context.l10n' in new_content and 'l10n_extension.dart' not in new_content:
            last_import = new_content.rfind('import ')
            if last_import != -1:
                end_of_line = new_content.find('\n', last_import)
                new_content = new_content[:end_of_line+1] + "import 'package:multi_vendor/core/utils/l10n_extension.dart';\n" + new_content[end_of_line+1:]
        
        with open(filepath, 'w', encoding='utf-8') as f:
            f.write(new_content)
        print(f"Processed: {filepath}")

def main():
    for root, _, files in os.walk('lib'):
        for file in files:
            if file.endswith('.dart') and 'app_localizations' not in file:
                replace_in_file(os.path.join(root, file))
                
    # Save the new mapping to a temporary file so we can view and translate it
    with open('extracted_extra.json', 'w', encoding='utf-8') as f:
        json.dump(extracted_dict, f, indent=2, ensure_ascii=False)
        
    print(f"Extracted {len(extracted_dict)} new strings to extracted_extra.json")

if __name__ == '__main__':
    main()
