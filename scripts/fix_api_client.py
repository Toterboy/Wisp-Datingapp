import os

filepath = r'C:\Users\Thoralf\IntelliJ Projekte\blind_date_app\lib\services\api_client.dart'

with open(filepath, 'rb') as f:
    raw = f.read()

# Specific byte replacements for api_client.dart
REPLACEMENTS = {
    b'\xc3\xa2\xe2\x82\xac\xc2\x9c\xc3\xa2\xe2\x82\xac\xc5\x9c': b'\xe2\x80\x94\xe2\x80\x94 ',  # ——
    b'\xc3\xa2\xe2\x82\xac\xc5\x9c': b'\xe2\x80\x94',  # —
    b'\xc3\xa2\xe2\x82\xac\xc5\x93': b'\xe2\x80\x94',  # —
    b'\xc3\xa2\xe2\x82\xac\xc2\x9c': b'\xe2\x80\x94',  # —
    b'\xc3\xa2\xe2\x82\xac\xc2\x9c\xc3\xa2\xe2\x82\xac\xc5\x9c': b'\xe2\x80\x94\xe2\x80\x94 ',  # ——
}

original = raw
for pattern, replacement in REPLACEMENTS.items():
    raw = raw.replace(pattern, replacement)

if raw != original:
    with open(filepath, 'wb') as f:
        f.write(raw)
    print("Fixed api_client.dart")
else:
    print("No change needed")
