#!/usr/bin/env python3
"""
AeroMaps App Icon Generator
Creates a cool aviation-themed app icon with multiple sizes
"""

from PIL import Image, ImageDraw, ImageFilter, ImageEnhance
import math
import os

def create_aeromaps_icon(size):
    """Create the main app icon at specified size"""
    # Create a new image with a gradient background
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    
    # Create a beautiful gradient background (sky to horizon)
    for y in range(size):
        # Sky gradient: deep blue to lighter blue
        if y < size * 0.6:
            # Sky gradient
            ratio = y / (size * 0.6)
            r = int(25 + (135 - 25) * ratio)  # 25 to 135
            g = int(50 + (206 - 50) * ratio)  # 50 to 206
            b = int(100 + (235 - 100) * ratio)  # 100 to 235
        else:
            # Horizon gradient
            ratio = (y - size * 0.6) / (size * 0.4)
            r = int(135 + (255 - 135) * ratio)  # 135 to 255
            g = int(206 + (255 - 206) * ratio)  # 206 to 255
            b = int(235 + (255 - 235) * ratio)  # 235 to 255
        
        draw.line([(0, y), (size, y)], fill=(r, g, b, 255))
    
    # Add some clouds in the background
    cloud_centers = [
        (size * 0.2, size * 0.3),
        (size * 0.8, size * 0.25),
        (size * 0.4, size * 0.4),
        (size * 0.7, size * 0.35)
    ]
    
    for center_x, center_y in cloud_centers:
        # Draw cloud with multiple circles
        cloud_radius = size * 0.08
        for offset_x, offset_y in [(0, 0), (-0.5, 0), (0.5, 0), (0, -0.3), (0, 0.3)]:
            x = center_x + offset_x * cloud_radius
            y = center_y + offset_y * cloud_radius
            draw.ellipse([x - cloud_radius * 0.6, y - cloud_radius * 0.6, 
                         x + cloud_radius * 0.6, y + cloud_radius * 0.6], 
                        fill=(255, 255, 255, 180))
    
    # Create a stylized airplane in the center
    plane_center_x = size * 0.5
    plane_center_y = size * 0.55
    
    # Airplane body (main fuselage)
    body_width = size * 0.25
    body_height = size * 0.08
    body_left = plane_center_x - body_width / 2
    body_top = plane_center_y - body_height / 2
    body_right = plane_center_x + body_width / 2
    body_bottom = plane_center_y + body_height / 2
    
    # Draw airplane body with gradient
    for i in range(int(body_height)):
        ratio = i / body_height
        # Silver to white gradient
        r = int(192 + (255 - 192) * ratio)
        g = int(192 + (255 - 192) * ratio)
        b = int(192 + (255 - 192) * ratio)
        draw.rectangle([body_left, body_top + i, body_right, body_top + i + 1], 
                      fill=(r, g, b, 255))
    
    # Add metallic shine to body
    shine_width = body_width * 0.3
    shine_height = body_height * 0.4
    shine_left = plane_center_x - shine_width / 2
    shine_top = body_top + body_height * 0.1
    draw.rectangle([shine_left, shine_top, shine_left + shine_width, shine_top + shine_height], 
                  fill=(255, 255, 255, 200))
    
    # Wings
    wing_width = size * 0.4
    wing_height = size * 0.04
    wing_left = plane_center_x - wing_width / 2
    wing_top = plane_center_y - wing_height / 2
    wing_right = plane_center_x + wing_width / 2
    wing_bottom = plane_center_y + wing_height / 2
    
    # Draw wings with gradient
    for i in range(int(wing_height)):
        ratio = i / wing_height
        # Blue to white gradient
        r = int(30 + (255 - 30) * ratio)
        g = int(144 + (255 - 144) * ratio)
        b = int(255 + (255 - 255) * ratio)
        draw.rectangle([wing_left, wing_top + i, wing_right, wing_top + i + 1], 
                      fill=(r, g, b, 255))
    
    # Tail
    tail_width = size * 0.08
    tail_height = size * 0.12
    tail_left = plane_center_x - tail_width / 2
    tail_top = plane_center_y - body_height / 2 - tail_height
    tail_right = plane_center_x + tail_width / 2
    tail_bottom = plane_center_y - body_height / 2
    
    # Draw tail with gradient
    for i in range(int(tail_height)):
        ratio = i / tail_height
        # Red to white gradient
        r = int(220 + (255 - 220) * ratio)
        g = int(20 + (255 - 20) * ratio)
        b = int(60 + (255 - 60) * ratio)
        draw.rectangle([tail_left, tail_top + i, tail_right, tail_top + i + 1], 
                      fill=(r, g, b, 255))
    
    # Windows (cockpit and passenger windows)
    window_color = (135, 206, 235, 255)  # Sky blue
    
    # Cockpit window
    cockpit_width = size * 0.06
    cockpit_height = size * 0.04
    cockpit_left = plane_center_x - cockpit_width / 2
    cockpit_top = plane_center_y - body_height / 2 - cockpit_height
    draw.ellipse([cockpit_left, cockpit_top, cockpit_left + cockpit_width, cockpit_top + cockpit_height], 
                fill=window_color)
    
    # Passenger windows
    for i in range(3):
        window_x = plane_center_x - size * 0.06 + i * size * 0.04
        window_y = plane_center_y - body_height / 2
        window_size = size * 0.02
        draw.ellipse([window_x - window_size, window_y - window_size, 
                     window_x + window_size, window_y + window_size], 
                    fill=window_color)
    
    # Add a subtle shadow under the plane
    shadow_offset = size * 0.02
    shadow_width = wing_width * 1.2
    shadow_height = size * 0.03
    shadow_left = plane_center_x - shadow_width / 2
    shadow_top = plane_center_y + body_height / 2 + shadow_offset
    shadow_right = plane_center_x + shadow_width / 2
    shadow_bottom = shadow_top + shadow_height
    
    # Create shadow with gradient
    for i in range(int(shadow_height)):
        alpha = int(100 * (1 - i / shadow_height))  # Fade out
        draw.rectangle([shadow_left, shadow_top + i, shadow_right, shadow_top + i + 1], 
                      fill=(0, 0, 0, alpha))
    
    # Add some speed lines behind the plane
    for i in range(5):
        line_x = plane_center_x - body_width / 2 - size * 0.05 - i * size * 0.02
        line_y = plane_center_y + (i - 2) * size * 0.01
        line_length = size * 0.08
        draw.line([(line_x, line_y), (line_x - line_length, line_y)], 
                 fill=(255, 255, 255, 150), width=max(1, size // 100))
    
    # Add a subtle glow effect around the plane
    glow_radius = size * 0.15
    glow_img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    glow_draw = ImageDraw.Draw(glow_img)
    glow_draw.ellipse([plane_center_x - glow_radius, plane_center_y - glow_radius,
                      plane_center_x + glow_radius, plane_center_y + glow_radius], 
                     fill=(135, 206, 235, 30))
    
    # Apply blur to glow
    glow_img = glow_img.filter(ImageFilter.GaussianBlur(radius=size * 0.02))
    img = Image.alpha_composite(img, glow_img)
    
    return img

def generate_all_sizes():
    """Generate all required app icon sizes"""
    sizes = {
        # iPhone
        "20x20@2x": 40,
        "20x20@3x": 60,
        "29x29@2x": 58,
        "29x29@3x": 87,
        "40x40@2x": 80,
        "40x40@3x": 120,
        "60x60@2x": 120,
        "60x60@3x": 180,
        # iPad
        "20x20@1x": 20,
        "20x20@2x": 40,
        "29x29@1x": 29,
        "29x29@2x": 58,
        "40x40@1x": 40,
        "40x40@2x": 80,
        "76x76@2x": 152,
        "83.5x83.5@2x": 167,
        # App Store
        "1024x1024@1x": 1024
    }
    
    # Create output directory
    output_dir = "app_icons"
    os.makedirs(output_dir, exist_ok=True)
    
    print("🎨 Creating AeroMaps app icons...")
    
    for name, size in sizes.items():
        print(f"  Creating {name} ({size}x{size})...")
        icon = create_aeromaps_icon(size)
        filename = f"{output_dir}/icon_{name}.png"
        icon.save(filename, "PNG")
    
    print(f"✅ All app icons created in '{output_dir}' directory!")
    print("\n📱 To use these icons:")
    print("1. Open your Xcode project")
    print("2. Select Assets.xcassets > AppIcon")
    print("3. Drag and drop each icon to its corresponding slot")
    print("4. Build and run your app!")

if __name__ == "__main__":
    generate_all_sizes()
