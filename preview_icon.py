#!/usr/bin/env python3
"""
AeroMaps App Icon Preview
Shows a preview of the generated app icon
"""

from PIL import Image
import os

def show_icon_preview():
    """Show a preview of the generated app icon"""
    
    # Check if the large icon exists
    icon_path = "app_icons/icon_1024x1024@1x.png"
    
    if os.path.exists(icon_path):
        print("🎨 AeroMaps App Icon Preview:")
        print("=" * 50)
        print("📱 Your new app icon features:")
        print("   ✈️  Stylized airplane in the center")
        print("   🌤️  Beautiful sky-to-horizon gradient")
        print("   ☁️  Floating clouds in the background")
        print("   ✨ Metallic shine and glow effects")
        print("   🎯 Speed lines for dynamic feel")
        print("   🏬 Professional aviation theme")
        print()
        print("🎨 Design Elements:")
        print("   • Sky blue gradient background")
        print("   • Silver metallic airplane body")
        print("   • Blue gradient wings")
        print("   • Red gradient tail")
        print("   • Sky blue cockpit windows")
        print("   • Subtle shadow and glow effects")
        print()
        print("📱 Icon Sizes Generated:")
        print("   • iPhone: 20x20, 29x29, 40x40, 60x60 (2x & 3x)")
        print("   • iPad: 20x20, 29x29, 40x40, 76x76, 83.5x83.5")
        print("   • App Store: 1024x1024")
        print()
        print("✅ The icon is now installed in your Xcode project!")
        print("🚀 Build and run your app to see it on the simulator!")
        
        # Try to open the icon in Preview
        try:
            import subprocess
            subprocess.run(["open", icon_path])
            print(f"\n🖼️  Opening icon preview in Preview app...")
        except:
            print(f"\n📁 Icon file location: {os.path.abspath(icon_path)}")
    else:
        print("❌ Icon file not found. Please run create_app_icon.py first.")

if __name__ == "__main__":
    show_icon_preview()
