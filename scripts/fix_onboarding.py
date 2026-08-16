import os

# Byte-level replacements specific to the patterns found
REPLACEMENTS = {
    # BOM
    b'\xef\xbb\xbf': b'',
    # Specific mojibake patterns found in onboarding_screen.dart
    b'\xc3\x83\xc2\xa4': b'\xc3\xa4',  # ä
    b'\xc3\x83\xc2\xf6': b'\xc3\xb6',  # ö
    b'\xc3\x83\xc2\xfc': b'\xc3\xbc',  # ü
    b'\xc3\x83\xc2\x84': b'\xc3\x84',  # Ä
    b'\xc3\x83\xc2\x96': b'\xc3\x96',  # Ö
    b'\xc3\x83\xc2\x9c': b'\xc3\x9c',  # Ü
    b'\xc3\x83\xc2\x9f': b'\xc3\x9f',  # ß
    b'\xc3\x83\xc2\xa9': b'\xc3\xa9',  # é
    b'\xc3\x83\xc2\xa8': b'\xc3\xa8',  # è
    b'\xc3\x83\xc2\xaa': b'\xc3\xaa',  # ê
    b'\xc3\x83\xc2\xab': b'\xc3\xab',  # ë
    b'\xc3\x83\xc2\xa0': b'\xc3\xa0',  # à
    b'\xc3\x83\xc2\xa2': b'\xc3\xa2',  # â
    b'\xc3\x83\xc2\xa7': b'\xc3\xa7',  # ç
    b'\xc3\x83\xc2\xb1': b'\xc3\xb1',  # ñ
    b'\xc3\x83\xc2\xba': b'\xc3\xba',  # ú
    b'\xc3\x83\xc2\xbb': b'\xc3\xbb',  # û
    b'\xc3\x83\xc2\xb9': b'\xc3\xb9',  # ù
    # Specific mangled sequences
    b'\xc3\xa2\xe2\x82\xac\xc2\x9c\xc3\xa2\xe2\x82\xac\xc5\x9c': b'\xe2\x80\x93',  # en-dash
    b'\xc3\xa2\xe2\x82\xac\xc5\x9c': b'\xe2\x80\x93',  # en-dash variant
    b'\xc3\xa2\xe2\x82\xac\xc5\x93': b'\xe2\x80\x93',  # en-dash variant
    b'\xc3\xaf\xc3\x82\xc2\xbb\xc3\x82\xc2\xbf': b'',  # BOM variant 1
    b'\xc3\xaf\xc3\x82\xc2\xbf': b'',  # BOM variant 2
    # Triple-encoded specific strings
    b'\xc3\x83\xc2\xbc': b'\xc3\xbc',  # ü (again)
}

filepath = r'C:\Users\Thoralf\IntelliJ Projekte\blind_date_app\lib\screens\onboarding\onboarding_screen.dart'

try:
    with open(filepath, 'rb') as f:
        raw = f.read()
    
    original = raw
    for pattern, replacement in REPLACEMENTS.items():
        raw = raw.replace(pattern, replacement)
    
    if raw != original:
        with open(filepath, 'wb') as f:
            f.write(raw)
        print(f"Fixed: {filepath}")
    else:
        print("No change needed")
except Exception as e:
    print(f"Error: {e}")
