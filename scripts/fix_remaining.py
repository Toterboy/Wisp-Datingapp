import os
import glob

project_root = r'C:\Users\Thoralf\IntelliJ Projekte\blind_date_app'

# Additional replacements for remaining corrupted strings
REPLACEMENTS = {
    # Remaining en-dash variants
    'ââ–': '–',
    'ââ€': '–',
    'â€šÂ¬': '–',
    'ââ‚¬': '',
    'â€šÂ¬': '–',
    'ââ–': '–',
    # Emoji mangling patterns
    'Ãƒ°ÅÂ¸Åâ€™ÅÂ¸': '😊',
    'Ãƒ°ÅÂ¸â‚¬â„¢Ã‚Â«': '😉',
    'Ãƒ°ÅÂ¸Å¾â–': '🙂',
    'Ãƒ°ÅÂ¸Ã‹œÅÂ ': '😊',
    'Ãƒ°ÅÂ¸Ã‚ï¿½â–': '😊',
    'Ãƒ°ÅÂ¸â‚¬ï¿½Ã‚ï¿½': '😊',
    'Ãƒ°ÅÂ¸â‚¬ËœÃ‚ï¿½': '😊',
    'Ãƒ°ÅÂ¸Å¾â–šÂ¬': '🙂',
    # Other patterns
    'ÃƒÆ’œ': 'ü',
    'ÃƒÆ’–Å': 'Ä',
    'ÃƒÆ’–Å¾': 'Ä',
    'ÃƒÆ’œbung': 'übung',
    'ÃƒÆ’–Å' : 'Ä',
    'ÃƒÆ’–Å¾nderung': 'Änderung',
    'ÃƒÆ’–Å' : 'Ä',
    'ÃƒÆ’–Å¾nderungen': 'Änderungen',
    'ÃƒÆ’œberschreibt': 'überschreibt',
    # Remaining patterns
    'ÃƒÆ’Ã‚Â¶nlichkeit': 'önlichkeit',
    'ÃƒÆ’Ã‚Â¤': 'ä',
    'ÃƒÆ’Ã‚Â¶': 'ö',
    'ÃƒÆ’Ã‚Â¼': 'ü',
    'ÃƒÆ’Ã‚Â„': 'Ä',
    'ÃƒÆ’Ã‚Â–': 'Ö',
    'ÃƒÆ’Ã‚Âœ': 'Ü',
    'ÃƒÆ’Ã‚ÂŸ': 'ß',
    'ÃƒÆ’Ã‚Â©': 'é',
    'ÃƒÆ’Ã‚Â¨': 'è',
    'ÃƒÆ’Ã‚Âª': 'ê',
    'ÃƒÆ’Ã‚Â«': 'ë',
    'ÃƒÆ’Ã‚Â ': 'à',
    'ÃƒÆ’Ã‚Â¢': 'â',
    'ÃƒÆ’Ã‚Â§': 'ç',
    'ÃƒÆ’Ã‚Â±': 'ñ',
    'ÃƒÆ’Ã‚Âº': 'ú',
    'ÃƒÆ’Ã‚Â»': 'û',
    'ÃƒÆ’Ã‚Â¹': 'ù',
    'ÃƒÆ’Ã‚Â¬': 'ì',
    'ÃƒÆ’Ã‚Â®': 'î',
    'ÃƒÆ’Ã‚Â¯': 'ï',
    'ÃƒÆ’Ã‚Â´': 'ô',
    'ÃƒÆ’Ã‚Âµ': 'õ',
    'ÃƒÆ’Ã‚Â˜': 'Ø',
    'ÃƒÆ’Ã‚Â¸': 'ø',
    'ÃƒÆ’Ã‚Â…': 'Å',
    'ÃƒÆ’Ã‚Â¥': 'å',
    'ÃƒÆ’Ã‚Â¦': 'æ',
    'ÃƒÆ’Ã‚Â¡': 'á',
    'ÃƒÆ’Ã‚Â­': 'í',
    'ÃƒÆ’Ã‚Â³': 'ó',
    'ÃƒÆ’Ã‚Â½': 'Ý',
    'ÃƒÆ’Ã‚Â½': 'ý',
    'ÃƒÆ’Ã‚Â¿': 'ÿ',
}

patterns = [
    os.path.join(project_root, 'lib', '**', '*.dart'),
    os.path.join(project_root, 'test', '**', '*.dart'),
]

fixed_count = 0
for pattern in patterns:
    for fp in glob.glob(pattern, recursive=True):
        try:
            with open(fp, 'r', encoding='utf-8', errors='replace') as f:
                content = f.read()
            
            original = content
            for wrong, correct in REPLACEMENTS.items():
                content = content.replace(wrong, correct)
            
            if content != original:
                with open(fp, 'w', encoding='utf-8', newline='\n') as f:
                    f.write(content)
                print(f"Fixed: {fp}")
                fixed_count += 1
        except Exception as e:
            print(f"Error: {fp}: {e}")

print(f"\nTotal files fixed: {fixed_count}")
