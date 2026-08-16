import os

filepath = r'C:\Users\Thoralf\IntelliJ Projekte\blind_date_app\lib\screens\onboarding\onboarding_screen.dart'

# Read raw bytes
with open(filepath, 'rb') as f:
    raw = f.read()

# Remove BOM
if raw.startswith(b'\xef\xbb\xbf'):
    raw = raw[3:]

# Decode as UTF-8
content = raw.decode('utf-8')

# Specific string replacements for known mojibake
replacements = {
    'Onboarding mit Blind-Mode-ErklÃƒÆ’Ã‚Â¤rung': 'Onboarding mit Blind-Mode-Erklärung',
    'ergÃƒÆ’Ã‚Â¤nzbaren': 'ergänzbaren',
    'ÃƒÆ’¼berspringbar': 'überspringbar',
    'SpÃƒÆ’Ã‚Â¤ter': 'Später',
    'ausfÃƒÆ’¼llen': 'ausfüllen',
    'nÃƒÆ’Ã‚Â¤chsten': 'nächsten',
    'PersÃƒÆ’Ã‚Â¶nlichkeitstest': 'Persönlichkeitstest',
    'ZurÃƒÆ’¼ck': 'Zurück',
    'ÃƒÆ’œberspringen': 'Überspringen',
    'PersÃƒÆ’Ã‚Â¶nlichkeit vor Aussehen': 'Persönlichkeit vor Aussehen',
    'nur Name, Alter, Bio und Interessen âââ€šÂ¬ââ‚¬œ keine Fotos': 'nur Name, Alter, Bio und Interessen – keine Fotos',
    'Deine PrivatsphÃƒÆ’Ã‚Â¤re zÃƒÆ’Ã‚Â¤hlt': 'Deine Privatsphäre zählt',
    'beide gematcht habt. Keine unnÃƒÆ’Ã‚Â¶tigen Berechtigungen.': 'beide gematcht habt. Keine unnötigen Berechtigungen.',
    'und weniger oberflÃƒÆ’Ã‚Â¤chlich': 'und weniger oberflächlich',
    'Bitte wÃƒÆ’Ã‚Â¤hlen': 'Bitte wählen',
    'Baden-WÃƒÆ’¼rttemberg': 'Baden-Württemberg',
    'ThÃƒÆ’¼ringen': 'Thüringen',
    'ErzÃƒÆ’Ã‚Â¤hl etwas ÃƒÆ’¼ber dich': 'Erzähl etwas über dich',
    'hochgeladen. Du kannst das spÃƒÆ’Ã‚Â¤ter ergÃƒÆ’Ã‚Â¤nzen': 'hochgeladen. Du kannst das später ergänzen',
    'âââ€šÂ¬ââ‚¬œ': '–',
    'MinderjÃƒÆ’Ã‚Â¤hriger': 'Minderjähriger',
    'PrivatsphÃƒÆ’Ã‚Â¤re': 'Privatsphäre',
}

for wrong, correct in replacements.items():
    content = content.replace(wrong, correct)

# Write back as UTF-8
with open(filepath, 'w', encoding='utf-8', newline='\n') as f:
    f.write(content)

print("Fixed onboarding_screen.dart")
