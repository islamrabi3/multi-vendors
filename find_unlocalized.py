import os
import re

# We want to find strings that are user-facing but were missed.
# Commonly, these are in:
# - showSnack(..., '...')
# - Text('...') (with interpolation or variables, like Text('Order #${order.id}'))
# - label: '...'
# - title: '...'
# - message: '...'
# - child: Text('...')
# - Dialog / AlertDialog content: Text('...')
# - List tiles, badges, buttons, etc.

# Let's search for quoted strings that have English letters and spaces,
# but aren't imports, route paths (starting with /), assets (ending in .png/jpg),
# or database column/table names (e.g. 'orders', 'banners', 'is_active').

def is_user_facing(s, line):
    s = s.strip()
    if not s:
        return False
    # Exclude package imports, route paths, assets, icons, etc.
    if s.startswith('package:') or s.startswith('dart:') or s.startswith('/') or s.endswith('.png') or s.endswith('.jpg') or s.endswith('.jpeg') or s.endswith('.svg') or s.endswith('.json'):
        return False
    if re.match(r'^[a-z_]+$', s):  # database columns/tables like 'delivery_fee'
        return False
    if s in ['id', 'email', 'password', 'signout', 'banner', 'coupon', 'percentage', 'fixed', 'open', 'closed', 'true', 'false', 'null']:
        return False
    if re.match(r'^[A-Z0-9_\-]+$', s): # env keys or constants like SUPABASE_ANON_KEY
        return False
    # If the line contains an import statement, ignore
    if 'import ' in line or 'part ' in line:
        return False
    # If the string contains spaces and english letters, or is a common English word
    if any(c.isalpha() for c in s) and (' ' in s or len(s) > 3):
        return True
    return False

# Find all occurrences of single or double quoted strings in dart files
def find_strings_in_file(filepath):
    with open(filepath, 'r', encoding='utf-8') as f:
        lines = f.readlines()
        
    results = []
    for line_num, line in enumerate(lines, 1):
        # find single quotes
        single_quotes = re.findall(r"'([^'\\]*(?:\\.[^'\\]*)*)'", line)
        for sq in single_quotes:
            if is_user_facing(sq, line):
                results.append((line_num, sq, line.strip()))
                
        # find double quotes
        double_quotes = re.findall(r'"([^"\\]*(?:\\.[^"\\]*)*)"', line)
        for dq in double_quotes:
            if is_user_facing(dq, line):
                results.append((line_num, dq, line.strip()))
                
    return results

def main():
    total_found = 0
    for root, _, files in os.walk('lib'):
        for file in files:
            if file.endswith('.dart') and 'app_localizations' not in file:
                filepath = os.path.join(root, file)
                res = find_strings_in_file(filepath)
                if res:
                    print(f"\n--- {filepath} ---")
                    for line_num, val, line in res:
                        print(f"  Line {line_num}: [{val}] -> {line}")
                        total_found += 1
    print(f"\nTotal potentially unlocalized strings found: {total_found}")

if __name__ == '__main__':
    main()
