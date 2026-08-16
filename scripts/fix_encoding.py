import os
import glob

# Specific replacements for known mojibake patterns
# These are the actual strings found in the files
REPLACEMENTS = {
    # BOM
    '\ufeff': '',  # UTF-8 BOM
    # Common mojibake patterns
    'â\x9c\x9c\xc3\xa2\xe2\x82\xac\xc5\x93': '–',  # en-dash variant
    'â\x9c\x9c\xc3\xa2\xe2\x82\xac\xc5\x9c': '–',  # another en-dash variant
    'â\x9c\x9c\xe2\x82\xac\xc5\x9c': '–',
    'â\x9c\x9c': '',
    '\xc3\xa2\xe2\x82\xac\xc5\x9c': '',
    '\xc3\xa2\xe2\x82\xac\xc5\x93': '–',
    '\xc3\x83\xc2\xa4': 'ä',
    '\xc3\x83\xc2\xf6': 'ö',
    '\xc3\x83\xc2\xfc': 'ü',
    '\xc3\x83\xc2\x84': 'Ä',
    '\xc3\x83\xc2\x96': 'Ö',
    '\xc3\x83\xc2\x9c': 'Ü',
    '\xc3\x83\xc2\x9f': 'ß',
    '\xc3\x83\xc2\xa9': 'é',
    '\xc3\x83\xc2\xa8': 'è',
    '\xc3\x83\xc2\xaa': 'ê',
    '\xc3\x83\xc2\xab': 'ë',
    '\xc3\x83\xc2\xa0': 'à',
    '\xc3\x83\xc2\xa2': 'â',
    '\xc3\x83\xc2\xa7': 'ç',
    '\xc3\x83\xc2\xb1': 'ñ',
    '\xc3\x83\xc2\xba': 'ú',
    '\xc3\x83\xc2\xbb': 'û',
    '\xc3\x83\xc2\xb9': 'ù',
    # triple-encoded patterns
    'Ã\x83\x82\xa4': 'ä',
    'Ã\x83\x82\xf6': 'ö',
    'Ã\x83\x82\xfc': 'ü',
    'Ã\x83\x82\x84': 'Ä',
    'Ã\x83\x82\x96': 'Ö',
    'Ã\x83\x82\x9c': 'Ü',
    'Ã\x83\x82\x9f': 'ß',
    'Ã\x83\x82\xa9': 'é',
    'Ã\x83\x82\xa8': 'è',
    'Ã\x83\x82\xaa': 'ê',
    'Ã\x83\x82\xab': 'ë',
    'Ã\x83\x82\xa0': 'à',
    'Ã\x83\x82\xa2': 'â',
    'Ã\x83\x82\xa7': 'ç',
    'Ã\x83\x82\xb1': 'ñ',
    'Ã\x83\x82\xba': 'ú',
    'Ã\x83\x82\xbb': 'û',
    'Ã\x83\x82\xb9': 'ù',
    # Common word patterns (most reliable)
    'wÃ\x83\x82\xa4hrend': 'während',
    'Ã\x83\x82\xbcberspringen': 'Überspringen',
    'Ã\x83\x82\xa4ber': 'über',
    'Ã\x83\x82\xa4hlen': 'ählen',
    'zurÃ\x83\x82\xbc': 'zurück',
    'ErklÃ\x83\x82\xa4': 'Erklä',
    'BegrÃ\x83\x82\xbc': 'Begrü',
    'PersÃ\x83\x82\xb6': 'Persö',
    'fÃ\x83\x82\xbchrt': 'führt',
    'PrÃ\x83\x82\xa4': 'Prä',
    'wÃ\x83\x82\xa4hrend': 'während',
    'PrivatsphÃ\x83\x82\xa4': 'Privatsphä',
}

def fix_encoding(content):
    for wrong, correct in REPLACEMENTS.items():
        content = content.replace(wrong, correct)
    return content

def process_file(filepath):
    try:
        with open(filepath, 'rb') as f:
            raw = f.read()
        
        # Remove BOM if present
        if raw.startswith(b'\xef\xbb\xbf'):
            raw = raw[3:]
        
        # Try UTF-8 first
        try:
            content = raw.decode('utf-8')
        except UnicodeDecodeError:
            content = raw.decode('cp1252', errors='replace')
        
        fixed = fix_encoding(content)
        
        if fixed != content:
            with open(filepath, 'w', encoding='utf-8', newline='\n') as f:
                f.write(fixed)
            print(f"Fixed: {filepath}")
            return True
        return False
    except Exception as e:
        print(f"Error: {filepath}: {e}")
        return False

project_root = r'C:\Users\Thoralf\IntelliJ Projekte\blind_date_app'
patterns = [
    os.path.join(project_root, 'lib', '**', '*.dart'),
    os.path.join(project_root, 'test', '**', '*.dart'),
]

count = 0
for pattern in patterns:
    for fp in glob.glob(pattern, recursive=True):
        if process_file(fp):
            count += 1

print(f"Total fixed: {count}")
