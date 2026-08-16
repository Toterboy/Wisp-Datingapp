import os
import glob

project_root = r'C:\Users\Thoralf\IntelliJ Projekte\blind_date_app'

# Byte-level replacements
REPLACEMENTS = {
    b'\xef\xbb\xbf': b'',  # UTF-8 BOM
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
    # En-dash variants
    b'\xc3\xa2\xe2\x82\xac\xc2\x9c': b'\xe2\x80\x93',  # –
    b'\xc3\xa2\xe2\x82\xac\xc5\x9c': b'\xe2\x80\x93',  # –
    b'\xc3\xa2\xe2\x82\xac\xc5\x93': b'\xe2\x80\x93',  # –
    b'\xc3\xa2\xe2\x82\xac\xc2\x9c\xc3\xa2\xe2\x82\xac\xc5\x9c': b'\xe2\x80\x93',  # –
    # BOM variants
    b'\xc3\xaf\xc3\x82\xc2\xbb\xc3\x82\xc2\xbf': b'',
    b'\xc3\xaf\xc3\x82\xc2\xbf': b'',
}

patterns = [
    os.path.join(project_root, 'lib', '**', '*.dart'),
    os.path.join(project_root, 'test', '**', '*.dart'),
]

fixed_count = 0
for pattern in patterns:
    for fp in glob.glob(pattern, recursive=True):
        try:
            with open(fp, 'rb') as f:
                raw = f.read()
            
            original = raw
            for pattern, replacement in REPLACEMENTS.items():
                raw = raw.replace(pattern, replacement)
            
            if raw != original:
                with open(fp, 'wb') as f:
                    f.write(raw)
                print(f"Fixed: {fp}")
                fixed_count += 1
        except Exception as e:
            print(f"Error: {fp}: {e}")

print(f"\nTotal files fixed: {fixed_count}")
