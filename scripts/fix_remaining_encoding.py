import os

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

REPLACEMENTS = {
    'â”€â”€â”€': '───',
    'â”€â”€': '──',
    'â”€': '─',
    'Ã¢â€“Ã¯Â¿Â½Ã¢â€“Ã¢â€“Ã¯Â¿Â½Ã¢â€“': '───',
    'Ã¢â€“Ã¯Â¿Â½Ã¢â€“': '──',
    'Ã¢â€“': '─',
    'â€“': '–',
    'â€"': '—',
    'â€šÂ¬': '–',
    'Ãƒ°ÅÂ¸Ã‚ï¿½Ã†â€™Ã‚ï¿½â€žÂ¢â€žïÃ‚Â¸Ã‚ï¿½': '😊🎉',
    'Ãƒ°ÅÂ¸Å½Ã‚Â¨': '🎨',
    'Ãƒ°ÅÂ¸â‚¬â„¢Ã‚Â«': '😉',
    'Ãƒ°ÅÂ¸ËœÅÂ': '😊',
    'Ãƒ°ÅÂ¸Ëœ–Â¹': '🙂',
    'Ãƒ°ÅÂ¸ÅÂ ': '😊',
    'Ãƒ°ÅÂ¸â‚¬ï¿½Ã‚ï¿½': '😊',
    'Ãƒ°ÅÂ¸ËœÃ‚ï¿½': '😊',
    'Ãƒ°ÅÂ¸–Ëœ–Â¹': '🙂',
    'Ãƒ°ÅÂ¸–â„¢–Â¢': '😊',
    'Ãƒ°ÅÂ¸–ï¿½Ã‚ï¿½': '😊',
    'ââ‚¬Å¡': '–',
    'Ã¢â‚¬â€œ': '–',
    'Ã¢â‚¬Å¡': '–',
    'ââ‚¬': '',
    'Ãƒâ€šÃ‚Â§': '§',
    'ÃƒÆ’ÅÂ¸': 'ü',
    'ÃƒÆ’––ffnen': 'öffnen',
    'stöÃƒÆ’ÅÂ¸t': 'stört',
    'schlieÃƒÆ’ÅÂ¸t': 'schließt',
    'VerstoÃƒÆ’ÅÂ¸': 'Verstoß',
    'abschlieÃƒÆ’ÅÂ¸t': 'abschließt',
    'ordnungsgemÃƒÆ’ÅÂ¸': 'ordnungsgemäß',
    'Ãƒâ€šÃ‚Â¦': '…',
    'â€™': "'",
    'â€¦': '...',
    'Ã°Å¸ËœÅ': '😊',
    'âËœâ€¢': '☕',
    'Ãƒâ€šÃ‚Â': '',
    'Ãƒâ€š': '',
}

fixed = 0
for fp in files:
    if not os.path.exists(fp):
        continue
    with open(fp, 'r', encoding='utf-8', errors='replace') as f:
        content = f.read()
    original = content
    for wrong, correct in REPLACEMENTS.items():
        content = content.replace(wrong, correct)
    if content != original:
        with open(fp, 'w', encoding='utf-8', newline='\n') as f:
            f.write(content)
        print(f"Fixed: {fp}")
        fixed += 1

print(f"Total fixed: {fixed}")
