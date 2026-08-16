import os
import glob
import re

project_root = r'C:\Users\Thoralf\IntelliJ Projekte\blind_date_app'

# Direct string replacements for common corrupted patterns
STRING_REPLACEMENTS = {
    # BOM
    '\ufeff': '',
    '\xef\xbb\xbf': '',
    # Common corrupted German umlauts and special chars
    'ÃƒÆ’Ã‚Â¶': 'ö',
    'ÃƒÆ’Ã‚Â¤': 'ä',
    'ÃƒÆ’Ã‚Â¼': 'ü',
    'ÃƒÆ’Ã‚Â¶': 'ö',
    'ÃƒÆ’Ã‚Â¤': 'ä',
    'ÃƒÆ’Ã‚Â¶': 'ö',
    'ÃƒÆ’Ã‚Â¤': 'ä',
    'ÃƒÆ’¼': 'ü',
    'ÃƒÂ¤': 'ä',
    'ÃƒÂ¶': 'ö',
    'ÃƒÂ¼': 'ü',
    'ÃƒÂ„': 'Ä',
    'ÃƒÂ–': 'Ö',
    'ÃƒÂœ': 'Ü',
    'ÃƒÂŸ': 'ß',
    'ÃƒÂ©': 'é',
    'ÃƒÂ¨': 'è',
    'ÃƒÂª': 'ê',
    'ÃƒÂ«': 'ë',
    'ÃƒÂ ': 'à',
    'ÃƒÂ¢': 'â',
    'ÃƒÂ§': 'ç',
    'ÃƒÂ±': 'ñ',
    'ÃƒÂº': 'ú',
    'ÃƒÂ»': 'û',
    'ÃƒÂ¹': 'ù',
    'ÃƒÂ¬': 'ì',
    'ÃƒÂ®': 'î',
    'ÃƒÂ¯': 'ï',
    'ÃƒÂ´': 'ô',
    'ÃƒÂµ': 'õ',
    'ÃƒÂ˜': 'Ø',
    'ÃƒÂ¸': 'ø',
    'ÃƒÂ…': 'Å',
    'ÃƒÂ¥': 'å',
    'ÃƒÂ¦': 'æ',
    'Å“': 'œ',
    'ÅŸ': 'ş',
    'Ä±': 'ı',
    'Ä°': 'İ',
    'Ä‘': 'đ',
    'Ä‡': 'ć',
    'ÄŒ': 'Č',
    'Ä': 'č',
    'Ä�': 'š',
    'Å¡': 'ž',
    'Â€': '€',
    'Â™': '™',
    'Â©': '©',
    'Â®': '®',
    'Â°': '°',
    'Â±': '±',
    'Â²': '²',
    'Â³': '³',
    'Â¼': '¼',
    'Â½': '½',
    'Â¾': '¾',
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
    'ÃƒÆ’Ã‚Â½': 'Å',
    'ÃƒÆ’Ã‚Â¿': 'ÿ',
    'ÃƒÆ’Ã‚Â½': 'Å',
    'ÃƒÆ’Ã‚Â¿': 'ÿ',
    # Common full words
    'wÃƒÆ’Ã‚Â¤hrend': 'während',
    'ÃƒÆ’Ã‚Âœberspringen': 'Überspringen',
    'ÃƒÆ’Ã‚Âœber': 'über',
    'ÃƒÆ’Ã‚Â¤hlen': 'ählen',
    'zurÃƒÆ’Ã‚Â¼ck': 'zurück',
    'ErklÃƒÆ’Ã‚Â¤': 'Erklä',
    'BegrÃƒÆ’¼ÃƒÆ’Ã‚Âÿt': 'Begrüßt',
    'PersÃƒÆ’Ã‚Â¶nlichkeit': 'Persönlichkeit',
    'fÃƒÆ’Ã‚Â¼hrt': 'führt',
    'PrÃƒÆ’Ã‚Â¤': 'Prä',
    'wÃƒÆ’Ã‚Â¤hrend': 'während',
    'PrivatsphÃƒÆ’Ã‚Â¤': 'Privatsphä',
    'EinfÃƒÆ’Ã‚Â¼hrung': 'Einführung',
    'auÃƒÆ’Ã‚Å¸erhalb': 'außerhalb',
    'geÃƒÆ’Ã‚Â¶ffnet': 'geöffnet',
    'gewÃƒÆ’Ã‚Â¤hltem': 'gewähltem',
    'EinschrÃƒÆ’Ã‚Â¤nkung': 'Einschränkung',
    'auf diesem GerÃƒÆ’Ã‚Â¤t': 'auf diesem Gerät',
    'MinderjÃƒÆ’Ã‚Â¤hriger': 'Minderjähriger',
    'AltersprÃƒÆ’¼fung': 'Altersprüfung',
    'ÃƒÆ’¼berall': 'überall',
    'ÃƒÆ’¼ber': 'über',
    'ÃƒÆ’¼berall': 'überall',
    'ÃƒÆ’¼berall': 'überall',
    # En-dash variants
    'ââ‚¬œ': '–',
    'ââ‚¬': '–',
    'â€šÂ¬': '–',
    'ââ‚¬Å¡': '–',
    'Ã¢â‚¬Å¡': '–',
    'ââ‚¬â„¢': '™',
    'â€šâ€¦': '…',
    'Ã¢â‚¬â€œ': '–',
    'ââ‚¬ï¿½': '–',
    'ââ‚¬Â ': '–',
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
            for wrong, correct in STRING_REPLACEMENTS.items():
                content = content.replace(wrong, correct)
            
            if content != original:
                with open(fp, 'w', encoding='utf-8', newline='\n') as f:
                    f.write(content)
                print(f"Fixed: {fp}")
                fixed_count += 1
        except Exception as e:
            print(f"Error: {fp}: {e}")

print(f"\nTotal files fixed: {fixed_count}")
