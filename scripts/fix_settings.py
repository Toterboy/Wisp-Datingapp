import os

filepath = r'C:\Users\Thoralf\IntelliJ Projekte\blind_date_app\lib\screens\settings\settings_screen.dart'

with open(filepath, 'rb') as f:
    raw = f.read()

# Remove BOM
if raw.startswith(b'\xef\xbb\xbf'):
    raw = raw[3:]

content = raw.decode('utf-8')

replacements = {
    'EinfÃƒÆ’Ã‚Â¼hrung': 'Einführung',
    'auÃƒÆ’ÅÂ¸erhalb': 'außerhalb',
    'ZurÃƒÆ’¼ck': 'Zurück',
    'geÃƒÆ’Ã‚Â¶ffnet': 'geöffnet',
    'PersÃƒÆ’Ã‚Â¶nlichkeit vor Aussehen': 'Persönlichkeit vor Aussehen',
    'PersÃƒÆ’Ã‚Â¶nlichkeit vor Aussehen aktivieren': 'Persönlichkeit vor Aussehen aktivieren',
    'PrÃƒÆ’Ã‚Â¤ferenzen': 'Präferenzen',
    'fÃƒÆ’¼r U20': 'für U20',
    'nicht ÃƒÆ’Ã‚Â¤nderbar': 'nicht änderbar',
    'Geschlechts-PrÃƒÆ’Ã‚Â¤ferenz': 'Geschlechts-Präferenz',
    'Suchradius definieren ÃƒÆ’¼ber': 'Suchradius definieren über',
    'gewÃƒÆ’Ã‚Â¤hltem': 'gewähltem',
    'Baden-WÃƒÆ’¼rttemberg': 'Baden-Württemberg',
    'ThÃƒÆ’¼ringen': 'Thüringen',
    'EinschrÃƒÆ’Ã‚Â¤nkung âââ€šÂ¬ââ‚¬œ': 'Einschränkung –',
    'PrivatsphÃƒÆ’Ã‚Â¤re': 'Privatsphäre',
    'auf diesem GerÃƒÆ’Ã‚Â¤t': 'auf diesem Gerät',
    'AltersprÃƒÆ’¼fung': 'Altersprüfung',
    'ÃƒÆ’¼berall': 'überall',
}

for wrong, correct in replacements.items():
    content = content.replace(wrong, correct)

with open(filepath, 'w', encoding='utf-8', newline='\n') as f:
    f.write(content)

print("Fixed settings_screen.dart")
