import os
import re

files = [
    r'C:\Users\Thoralf\IntelliJ Projekte\blind_date_app\lib\services\api_client.dart',
    r'C:\Users\Thoralf\IntelliJ Projekte\blind_date_app\lib\services\chat_service.dart',
    r'C:\Users\Thoralf\IntelliJ Projekte\blind_date_app\lib\services\mock_data_service.dart',
    r'C:\Users\Thoralf\IntelliJ Projekte\blind_date_app\lib\services\dating_hour_service.dart',
    r'C:\Users\Thoralf\IntelliJ Projekte\blind_date_app\lib\services\encryption_service.dart',
    r'C:\Users\Thoralf\IntelliJ Projekte\blind_date_app\lib\services\photo_moderation_service.dart',
    r'C:\Users\Thoralf\IntelliJ Projekte\blind_date_app\lib\services\webrtc_service.dart',
    r'C:\Users\Thoralf\IntelliJ Projekte\blind_date_app\lib\services\server_time_service.dart',
    r'C:\Users\Thoralf\IntelliJ Projekte\blind_date_app\lib\utils\cert_pinning.dart',
    r'C:\Users\Thoralf\IntelliJ Projekte\blind_date_app\lib\screens\verification\verification_flow.dart',
    r'C:\Users\Thoralf\IntelliJ Projekte\blind_date_app\lib\screens\swipe\random_chat_screen.dart',
    r'C:\Users\Thoralf\IntelliJ Projekte\blind_date_app\lib\screens\onboarding\personality_test_screen.dart',
]

# Aggressive pattern: remove corrupted sequences
# These are the specific corrupted byte patterns we see
CORRUPTED_PATTERNS = [
    # Double-encoded em-dash sequences
    (re.compile(r'â–ï¿½â–â–ï¿½â–â–ï¿½â–â–ï¿½â–â–ï¿½â–â–ï¿½â–â–ï¿½â–â–ï¿½â–â–ï¿½â–â–ï¿½â–â–ï¿½â–â–ï¿½â–â–ï¿½â–â–ï¿½â–â–ï¿½â–â–ï¿½â–â–ï¿½â–â–ï¿½â–â–ï¿½â–â–ï¿½â–â–ï¿½â–â–ï¿½â–â–ï¿½â–â–ï¿½â–â–ï¿½â–â–ï¿½â–â–ï¿½â–â–ï¿½â–â–ï¿½â–â–ï¿½â–â–ï¿½â–â–ï¿½â–â–ï¿½â–â–ï¿½â–â–ï¿½â–â–ï¿½â–â–ï¿½â–â–ï¿½â–â–ï¿½â–â–ï¿½â–â–ï¿½â–â–ï¿½â–â–ï¿½â–â–ï¿½â–â–ï¿½â–â–ï¿½â–â–ï¿½â–â–ï¿½â–â–ï¿½â–â–ï¿½â–'), ''),
    (re.compile(r'â–ï¿½â–â–ï¿½â–'), '───'),
    (re.compile(r'â–ï¿½â–'), '──'),
    (re.compile(r'â–'), '─'),
    (re.compile(r'Ã¢â€“Ã¯Â¿Â½Ã¢â€“Ã¢â€“Ã¯Â¿Â½Ã¢â€“'), '───'),
    (re.compile(r'Ã¢â€“Ã¯Â¿Â½Ã¢â€“'), '──'),
    (re.compile(r'Ã¢â€"'), '──'),
    (re.compile(r'Ã¢â‚¬â€œ'), '–'),
    (re.compile(r'Ã¢â‚¬Å¡'), '–'),
    (re.compile(r'Ãƒâ€šÃ‚Â¦'), '...'),
    (re.compile(r'Ãƒâ€šÃ‚Â§'), '§'),
    (re.compile(r'ÃƒÆ’ÅÂ¸t'), 'ßt'),
    (re.compile(r'ÃƒÆ’ÅÂ¸'), 'ü'),
    (re.compile(r'stöÃƒÆ’ÅÂ¸t'), 'stört'),
    (re.compile(r'schlieÃƒÆ’ÅÂ¸t'), 'schließt'),
    (re.compile(r'VerstoÃƒÆ’ÅÂ¸'), 'Verstoß'),
    (re.compile(r'abschlieÃƒÆ’ÅÂ¸t'), 'abschließt'),
    (re.compile(r'ordnungsgemÃƒÆ’ÅÂ¸'), 'ordnungsgemäß'),
    (re.compile(r'ÃƒÆ’––ffnen'), 'öffnen'),
    (re.compile(r'ÃƒÆ’œ'), 'ü'),
    (re.compile(r'ÃƒÆ’–Å¾nderung'), 'Änderung'),
    (re.compile(r'ÃƒÆ’–Å'), 'Ä'),
    (re.compile(r'ÃƒÆ’œbung'), 'übung'),
    (re.compile(r'ÃƒÆ’œberschreibt'), 'überschreibt'),
    (re.compile(r'ÃƒÆ’œberspringen'), 'Überspringen'),
    (re.compile(r'ÃƒÆ’–Å¾ndern'), 'Ändern'),
    (re.compile(r'Ãƒâ€šÃ‚Â'), ''),
    (re.compile(r'Ãƒâ€š'), ''),
    (re.compile(r'Ã¢â‚¬'), '–'),
    (re.compile(r'â€"'), '—'),
    (re.compile(r'â€"'), '—'),
    (re.compile(r'â€"'), '—'),
    # Emoji mangling
    (re.compile(r'Ãƒ°ÅÂ¸Ã‚ï¿½Ã†â€™Ã‚ï¿½â€žÂ¢â€žïÃ‚Â¸Ã‚ï¿½'), '😊🎉'),
    (re.compile(r'Ãƒ°ÅÂ¸Å½Ã‚Â¨'), '🎨'),
    (re.compile(r'Ãƒ°ÅÂ¸â‚¬â„¢Ã‚Â«'), '😉'),
    (re.compile(r'Ãƒ°ÅÂ¸ËœÅÂ'), '😊'),
    (re.compile(r'Ãƒ°ÅÂ¸Ëœ–Â¹'), '🙂'),
    (re.compile(r'Ãƒ°ÅÂ¸ÅÂ '), '😊'),
    (re.compile(r'Ãƒ°ÅÂ¸â‚¬ï¿½Ã‚ï¿½'), '😊'),
    (re.compile(r'Ãƒ°ÅÂ¸ËœÃ‚ï¿½'), '😊'),
    (re.compile(r'Ãƒ°ÅÂ¸–Ëœ–Â¹'), '🙂'),
    (re.compile(r'Ãƒ°ÅÂ¸–â„¢–Â¢'), '😊'),
    (re.compile(r'Ãƒ°ÅÂ¸–ï¿½Ã‚ï¿½'), '😊'),
    (re.compile(r'ÃƒÆ’Ã‚Â¶nlichkeit'), 'önlichkeit'),
    # Remove any remaining trailing corrupted bytes on lines
    (re.compile(r'[ÃÂâ€šÅ¸œÆ’¼–¿½]+$'), ''),
    (re.compile(r'â€™'), "'"),
    (re.compile(r'â€¦'), '...'),
    (re.compile(r'Ã°Å¸ËœÅ'), '😊'),
    (re.compile(r'âËœâ€¢'), '☕'),
]

fixed = 0
for fp in files:
    if not os.path.exists(fp):
        continue
    with open(fp, 'r', encoding='utf-8', errors='replace') as f:
        content = f.read()
    original = content
    for pattern, replacement in CORRUPTED_PATTERNS:
        content = pattern.sub(replacement, content)
    if content != original:
        with open(fp, 'w', encoding='utf-8', newline='\n') as f:
            f.write(content)
        print(f"Fixed: {fp}")
        fixed += 1

print(f"Total fixed: {fixed}")
