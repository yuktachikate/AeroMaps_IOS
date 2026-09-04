#!/usr/bin/env python3
"""
AeroMaps App Icon Installer
Automatically installs the generated app icons into the Xcode project
"""

import os
import shutil
import json

def install_app_icons():
    """Install the generated app icons into the Xcode project"""
    
    # Paths
    icons_dir = "app_icons"
    app_icon_dir = "AeroMaps/Assets.xcassets/AppIcon.appiconset"
    
    # Mapping of icon files to their Xcode slots
    icon_mapping = {
        "icon_20x20@1x.png": "20x20@1x",
        "icon_20x20@2x.png": "20x20@2x", 
        "icon_20x20@3x.png": "20x20@3x",
        "icon_29x29@1x.png": "29x29@1x",
        "icon_29x29@2x.png": "29x29@2x",
        "icon_29x29@3x.png": "29x29@3x",
        "icon_40x40@1x.png": "40x40@1x",
        "icon_40x40@2x.png": "40x40@2x",
        "icon_40x40@3x.png": "40x40@3x",
        "icon_60x60@2x.png": "60x60@2x",
        "icon_60x60@3x.png": "60x60@3x",
        "icon_76x76@2x.png": "76x76@2x",
        "icon_83.5x83.5@2x.png": "83.5x83.5@2x",
        "icon_1024x1024@1x.png": "1024x1024@1x"
    }
    
    # Read the current Contents.json
    contents_path = os.path.join(app_icon_dir, "Contents.json")
    with open(contents_path, 'r') as f:
        contents = json.load(f)
    
    print("🚀 Installing AeroMaps app icons...")
    
    # Copy icons and update Contents.json
    for icon_file, slot_name in icon_mapping.items():
        source_path = os.path.join(icons_dir, icon_file)
        dest_path = os.path.join(app_icon_dir, icon_file)
        
        if os.path.exists(source_path):
            # Copy the icon file
            shutil.copy2(source_path, dest_path)
            print(f"  ✅ Installed {icon_file}")
            
            # Update Contents.json to reference the icon
            for image in contents["images"]:
                if image.get("size") == slot_name.split("@")[0] and image.get("scale") == slot_name.split("@")[1]:
                    image["filename"] = icon_file
                    break
        else:
            print(f"  ❌ Missing {icon_file}")
    
    # Write updated Contents.json
    with open(contents_path, 'w') as f:
        json.dump(contents, f, indent=2)
    
    print("✅ App icons installed successfully!")
    print("\n🎯 Next steps:")
    print("1. Build your Xcode project")
    print("2. Run the app to see the new icon")
    print("3. The icon will appear on your device/simulator")

if __name__ == "__main__":
    install_app_icons()
