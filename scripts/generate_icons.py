from PIL import Image, ImageDraw
import os

# Project root
project_root = r'C:\Users\Thoralf\IntelliJ Projekte\blind_date_app'
base_path = os.path.join(project_root, 'assets', 'images', 'wisp_icon_base.png')

# Load base icon
base = Image.open(base_path).convert('RGBA')

def make_icon(size, path):
    """Resize base icon to given size and save."""
    img = base.resize((size, size), Image.Resampling.LANCZOS)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path, 'PNG')
    print(f"Created {path} ({size}x{size})")

# Android launcher icons
for size, rel in [
    (48, r'android\app\src\main\res\mipmap-mdpi\ic_launcher.png'),
    (72, r'android\app\src\main\res\mipmap-hdpi\ic_launcher.png'),
    (96, r'android\app\src\main\res\mipmap-xhdpi\ic_launcher.png'),
    (144, r'android\app\src\main\res\mipmap-xxhdpi\ic_launcher.png'),
    (192, r'android\app\src\main\res\mipmap-xxxhdpi\ic_launcher.png'),
]:
    make_icon(size, os.path.join(project_root, rel))

# iOS App Icons
for s in [20, 29, 40, 60, 76]:
    make_icon(s, os.path.join(project_root, 'ios', 'Runner', 'Assets.xcassets', 'AppIcon.appiconset', f'Icon-App-{s}x{s}@1x.png'))
    make_icon(s*2, os.path.join(project_root, 'ios', 'Runner', 'Assets.xcassets', 'AppIcon.appiconset', f'Icon-App-{s}x{s}@2x.png'))
    if s in [60, 76]:
        make_icon(s*3, os.path.join(project_root, 'ios', 'Runner', 'Assets.xcassets', 'AppIcon.appiconset', f'Icon-App-{s}x{s}@3x.png'))
make_icon(1024, os.path.join(project_root, 'ios', 'Runner', 'Assets.xcassets', 'AppIcon.appiconset', 'Icon-App-1024x1024@1x.png'))
make_icon(167, os.path.join(project_root, 'ios', 'Runner', 'Assets.xcassets', 'AppIcon.appiconset', 'Icon-App-83.5x83.5@2x.png'))

# macOS App Icons
for s in [16, 32, 64, 128, 256, 512, 1024]:
    make_icon(s, os.path.join(project_root, 'macos', 'Runner', 'Assets.xcassets', 'AppIcon.appiconset', f'app_icon_{s}.png'))

# Linux icons
make_icon(128, os.path.join(project_root, 'linux', 'runner', 'resources', 'app_icon_128.png'))
make_icon(256, os.path.join(project_root, 'linux', 'runner', 'resources', 'app_icon_256.png'))
make_icon(512, os.path.join(project_root, 'linux', 'runner', 'resources', 'app_icon_512.png'))

# Web icons
make_icon(192, os.path.join(project_root, 'web', 'icons', 'Icon-192.png'))
make_icon(512, os.path.join(project_root, 'web', 'icons', 'Icon-512.png'))
make_icon(192, os.path.join(project_root, 'web', 'icons', 'Icon-maskable-192.png'))
make_icon(512, os.path.join(project_root, 'web', 'icons', 'Icon-maskable-512.png'))
make_icon(32, os.path.join(project_root, 'web', 'favicon.png'))

# Windows ICO with multiple resolutions
ico_sizes = [16, 32, 48, 64, 128, 256]
ico_images = [base.resize((s, s), Image.Resampling.LANCZOS) for s in ico_sizes]
ico_path = os.path.join(project_root, 'windows', 'runner', 'resources', 'app_icon.ico')
ico_images[0].save(ico_path, format='ICO', sizes=[(s, s) for s in ico_sizes])
print(f"Created {ico_path} (ICO with sizes: {ico_sizes})")

print("All icons generated successfully!")
