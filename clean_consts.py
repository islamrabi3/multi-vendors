import os
import re

def find_matching_bracket(text, start_idx, open_char, close_char):
    depth = 0
    in_string = False
    string_char = None
    escaped = False
    in_line_comment = False
    in_block_comment = False
    
    i = start_idx
    while i < len(text):
        char = text[i]
        
        if in_line_comment:
            if char == '\n':
                in_line_comment = False
            i += 1
            continue
            
        if in_block_comment:
            if char == '*' and i + 1 < len(text) and text[i+1] == '/':
                in_block_comment = False
                i += 2
            else:
                i += 1
            continue
            
        if escaped:
            escaped = False
            i += 1
            continue
            
        if char == '\\':
            escaped = True
            i += 1
            continue
            
        if in_string:
            if char == string_char:
                in_string = False
            i += 1
            continue
            
        # Check for comments
        if char == '/' and i + 1 < len(text):
            if text[i+1] == '/':
                in_line_comment = True
                i += 2
                continue
            elif text[i+1] == '*':
                in_block_comment = True
                i += 2
                continue
                
        if char in ["'", '"']:
            in_string = True
            string_char = char
            i += 1
            continue
            
        if char == open_char:
            depth += 1
        elif char == close_char:
            depth -= 1
            if depth == 0:
                return i
        i += 1
                
    return -1

def clean_file_consts(content):
    changed = True
    passes = 0
    while changed and passes < 20: # raised pass limit to 20 just in case
        changed = False
        passes += 1
        
        pos = 0
        while True:
            match = re.search(r'\bconst\b', content[pos:])
            if not match:
                break
                
            const_start = pos + match.start()
            const_end = pos + match.end()
            
            rest = content[const_end:]
            ws_match = re.match(r'^\s*(?:<[^>]+>)?\s*', rest)
            if not ws_match:
                pos = const_end
                continue
                
            next_start_idx = const_end + ws_match.end()
            if next_start_idx >= len(content):
                pos = const_end
                continue
                
            open_char = content[next_start_idx]
            close_char = None
            
            if open_char == '[':
                close_char = ']'
            elif open_char == '{':
                close_char = '}'
            else:
                # Constructor call: name(
                ident_match = re.match(r'^[a-zA-Z0-9_\.]+\s*\(', content[next_start_idx:])
                if ident_match:
                    open_char_idx = next_start_idx + ident_match.end() - 1
                    open_char = '('
                    close_char = ')'
                    next_start_idx = open_char_idx
                else:
                    pos = const_end
                    continue
            
            matching_idx = find_matching_bracket(content, next_start_idx, open_char, close_char)
            if matching_idx != -1:
                inner_text = content[next_start_idx:matching_idx+1]
                if 'context.l10n' in inner_text:
                    content = content[:const_start] + content[const_end:].lstrip()
                    changed = True
                    break
            
            pos = const_end
            
    return content

def main():
    for root, _, files in os.walk('lib'):
        for file in files:
            if file.endswith('.dart'):
                filepath = os.path.join(root, file)
                with open(filepath, 'r', encoding='utf-8') as f:
                    content = f.read()
                
                cleaned = clean_file_consts(content)
                if cleaned != content:
                    with open(filepath, 'w', encoding='utf-8') as f:
                        f.write(cleaned)
                    print(f"Cleaned consts from {filepath}")

if __name__ == '__main__':
    main()
