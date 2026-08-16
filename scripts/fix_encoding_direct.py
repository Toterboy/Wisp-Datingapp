import os

# Direct string replacements for the most affected files
REPLACEMENTS = {
    'ï»¿': '',  # UTF-8 BOM
    'â\u201cœ': '–',  # en-dash variants
    'â\u201c': '',
    'ÃƒÂ¤': 'ä',
    'ÃƒÂ¶': 'ö',
    'ÃƒÂ¼': 'ü',
    'ÃƒÂ„': 'Ä',
    'ÃƒÂ–': 'Ö',
    'ÃƒÂœ': 'Ü',
    'ÃƒÂŸ': 'ß',
    'ÃƒÂ©': 'é',
    'ÃƒÂ¤hrend': 'während',
    'ÃƒÆ\'Ã‚Â¤': 'ä',
    'ÃƒÆ\'Ã‚Â¶': 'ö',
    'ÃƒÆ\'Ã‚Â¼': 'ü',
    'ÃƒÆ\'¼': 'ü',
    'ÃƒÂ¼ber': 'über',
    'ÃƒÂ¤hlen': 'ählen',
}

# Files to fix with their specific replacements
FILES_TO_FIX = [
    r'C:\Users\Thoralf\IntelliJ Projekte\blind_date_app\lib\screens\auth\login_screen.dart',
    r'C:\Users\Thoralf\IntelliJ Projekte\blind_date_app\lib\screens\welcome\welcome_screen.dart',
    r'C:\Users\Thoralf\IntelliJ Projekte\blind_date_app\lib\screens\onboarding\onboarding_screen.dart',
]

def fix_file(filepath, replacements):
    try:
        with open(filepath, 'rb') as f:
            raw = f.read()
        
        # Remove BOM
        if raw.startswith(b'\xef\xbb\xbf'):
            raw = raw[3:]
        
        # Decode
        try:
            content = raw.decode('utf-8')
        except UnicodeDecodeError:
            content = raw.decode('cp1252', errors='replace')
        
        original = content
        
        # Apply replacements
        for wrong, correct in replacements.items():
            content = content.replace(wrong, correct)
        
        # Additional specific fixes
        # Fix double-encoded sequences
        import re
        # Pattern: Ã followed by various byte sequences that represent umlauts
        content = re.sub(r'Ã[ÂÃ]?[¤ä¼¶ö]', lambda m: {
            'Ã¤': 'ä', 'Ã¶': 'ö', 'Ã¼': 'ü',
            'Ã': 'Ä', 'Ã': 'Ö', 'Ã': 'Ü', 'Ã': 'ß',
        }.get(m.group(0), m.group(0)), content)
        
        if content != original:
            with open(filepath, 'w', encoding='utf-8', newline='\n') as f:
                f.write(content)
            print(f"Fixed: {filepath}")
            return True
        else:
            print(f"No change needed: {filepath}")
            return False
    except Exception as e:
        print(f"Error processing {filepath}: {e}")
        return False

for fp in FILES_TO_FIX:
    if os.path.exists(fp):
        fix_file(fp, REPLACEMENTS)
    else:
        print(f"Not found: {fp}")
