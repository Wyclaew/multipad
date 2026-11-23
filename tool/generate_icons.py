import os
import math
from PIL import Image, ImageDraw, ImageFilter

def create_multipad_master_logo(size=1024):
    """
    Renders the modern, futuristic MultiPad brand logo:
    - Deep obsidian/navy rounded container
    - Ambient cyan-indigo cyber glow
    - Sleek faceted shield with metallic gradient
    - Glowing neon vault padlock with biometric core
    """
    # 4x supersampling for ultra-crisp antialiasing
    scale = 2
    w = size * scale
    h = size * scale
    
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # Center and radii
    cx = w / 2
    cy = h / 2
    r_card = w * 0.45
    card_radius = int(w * 0.22)

    # 1. Background Squircle / Rounded Rect
    card_box = [cx - r_card, cy - r_card, cx + r_card, cy + r_card]
    
    # Gradient base for the card
    card_bg = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    card_draw = ImageDraw.Draw(card_bg)
    
    # Draw rounded rect mask
    card_draw.rounded_rectangle(card_box, radius=card_radius, fill=(15, 23, 42, 255))
    
    # Add subtle vertical gradient: #0b0f19 to #1e1b4b
    for y in range(int(cy - r_card), int(cy + r_card)):
        factor = (y - (cy - r_card)) / (2 * r_card)
        r = int(11 + factor * (20 - 11))
        g = int(15 + factor * (25 - 15))
        b = int(25 + factor * (45 - 25))
        card_draw.line([(cx - r_card, y), (cx + r_card, y)], fill=(r, g, b, 255))
        
    # Re-apply squircle mask
    mask = Image.new("L", (w, h), 0)
    ImageDraw.Draw(mask).rounded_rectangle(card_box, radius=card_radius, fill=255)
    
    # Ambient radial neon glow in center
    glow = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    glow_draw = ImageDraw.Draw(glow)
    for r in range(int(w * 0.42), 0, -4):
        alpha = int(45 * (1.0 - (r / (w * 0.42)) ** 1.5))
        glow_draw.ellipse(
            [cx - r, cy - r + int(w * 0.05), cx + r, cy + r + int(w * 0.05)],
            fill=(99, 102, 241, alpha)
        )
    glow_cyan = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    glow_cyan_draw = ImageDraw.Draw(glow_cyan)
    for r in range(int(w * 0.25), 0, -4):
        alpha = int(60 * (1.0 - (r / (w * 0.25)) ** 1.2))
        glow_cyan_draw.ellipse(
            [cx - r, cy - r, cx + r, cy + r],
            fill=(6, 182, 212, alpha)
        )

    card_bg = Image.alpha_composite(card_bg, glow)
    card_bg = Image.alpha_composite(card_bg, glow_cyan)

    # Squircle border: subtle gradient border
    border_img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    b_draw = ImageDraw.Draw(border_img)
    b_draw.rounded_rectangle(
        card_box,
        radius=card_radius,
        outline=(99, 102, 241, 140),
        width=int(w * 0.012)
    )

    # 2. Outer Shield Crest
    shield_top = cy - w * 0.28
    shield_bottom = cy + w * 0.32
    shield_w = w * 0.58
    half_sw = shield_w / 2

    # Shield vertices
    p_top_mid = (cx, shield_top + w * 0.04)
    p_top_left = (cx - half_sw, shield_top)
    p_top_right = (cx + half_sw, shield_top)
    p_mid_left = (cx - half_sw, cy + w * 0.05)
    p_mid_right = (cx + half_sw, cy + w * 0.05)
    p_bottom = (cx, shield_bottom)

    # Faceted shield: Left side & Right side for 3D metallic feel
    left_facet = [p_top_mid, p_top_left, p_mid_left, p_bottom]
    right_facet = [p_top_mid, p_top_right, p_mid_right, p_bottom]

    shield_layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    s_draw = ImageDraw.Draw(shield_layer)

    # Left facet: Lighter indigo/cyan gradient
    s_draw.polygon(left_facet, fill=(30, 41, 59, 230))
    # Right facet: Deeper slate/indigo gradient
    s_draw.polygon(right_facet, fill=(15, 23, 42, 240))

    # Shield borders with neon edge
    s_draw.line([p_top_left, p_top_mid, p_top_right, p_mid_right, p_bottom, p_mid_left, p_top_left],
                fill=(99, 102, 241, 220), width=int(w * 0.015))
    s_draw.line([p_top_mid, p_bottom], fill=(6, 182, 212, 160), width=int(w * 0.008))

    # 3. Vault Padlock Core
    # Shackle
    shackle_layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    sh_draw = ImageDraw.Draw(shackle_layer)
    shackle_r = w * 0.11
    shackle_center_y = cy - w * 0.04
    shackle_box = [cx - shackle_r, shackle_center_y - shackle_r,
                   cx + shackle_r, shackle_center_y + shackle_r]
    sh_draw.arc(shackle_box, start=180, end=0, fill=(6, 182, 212, 255), width=int(w * 0.038))
    # Shackle vertical legs
    sh_draw.line([(cx - shackle_r, shackle_center_y), (cx - shackle_r, cy + w * 0.03)],
                 fill=(6, 182, 212, 255), width=int(w * 0.038))
    sh_draw.line([(cx + shackle_r, shackle_center_y), (cx + shackle_r, cy + w * 0.03)],
                 fill=(6, 182, 212, 255), width=int(w * 0.038))

    # Padlock Body: Rounded rectangle with glowing cyan/indigo border
    body_w = w * 0.28
    body_h = w * 0.22
    body_box = [cx - body_w / 2, cy - w * 0.01, cx + body_w / 2, cy - w * 0.01 + body_h]
    
    padlock_layer = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    p_draw = ImageDraw.Draw(padlock_layer)
    p_draw.rounded_rectangle(body_box, radius=int(w * 0.04), fill=(24, 24, 43, 255),
                             outline=(99, 102, 241, 255), width=int(w * 0.012))

    # Glowing Keyhole & Biometric ring
    keyhole_cy = cy + w * 0.075
    keyhole_r = w * 0.032
    p_draw.ellipse([cx - keyhole_r, keyhole_cy - keyhole_r,
                    cx + keyhole_r, keyhole_cy + keyhole_r],
                   fill=(6, 182, 212, 255))
    
    # Keyhole bottom slot
    slot_w = w * 0.02
    slot_h = w * 0.045
    p_draw.polygon([
        (cx - slot_w / 2, keyhole_cy),
        (cx + slot_w / 2, keyhole_cy),
        (cx + slot_w * 0.75, keyhole_cy + slot_h),
        (cx - slot_w * 0.75, keyhole_cy + slot_h)
    ], fill=(6, 182, 212, 255))

    # Shimmering biometric center dot
    p_draw.ellipse([cx - keyhole_r * 0.4, keyhole_cy - keyhole_r * 0.4,
                    cx + keyhole_r * 0.4, keyhole_cy + keyhole_r * 0.4],
                   fill=(255, 255, 255, 240))

    # Composite all layers onto card_bg
    final_card = Image.composite(card_bg, Image.new("RGBA", (w, h), (0, 0, 0, 0)), mask)
    final_card = Image.alpha_composite(final_card, border_img)
    final_card = Image.alpha_composite(final_card, shield_layer)
    final_card = Image.alpha_composite(final_card, shackle_layer)
    final_card = Image.alpha_composite(final_card, padlock_layer)

    # Downsample using LANCZOS for pristine quality
    result = final_card.resize((size, size), Image.Resampling.LANCZOS)
    return result

def create_monochrome_qs_tile(size=96):
    """
    Renders clean monochrome vector/white icon for Android Quick Settings Tile.
    """
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    
    cx = size / 2
    cy = size / 2
    
    # Shield outline
    shield_top = cy - size * 0.38
    shield_bottom = cy + size * 0.38
    sw = size * 0.72
    half_sw = sw / 2
    
    p_top_mid = (cx, shield_top + size * 0.05)
    p_top_left = (cx - half_sw, shield_top)
    p_top_right = (cx + half_sw, shield_top)
    p_mid_left = (cx - half_sw, cy + size * 0.08)
    p_mid_right = (cx + half_sw, cy + size * 0.08)
    p_bottom = (cx, shield_bottom)

    points = [p_top_left, p_top_mid, p_top_right, p_mid_right, p_bottom, p_mid_left]
    draw.polygon(points, fill=None, outline=(255, 255, 255, 240))
    draw.line(points + [p_top_left], fill=(255, 255, 255, 255), width=max(2, int(size * 0.06)))
    
    # Padlock core in center
    body_w = size * 0.32
    body_h = size * 0.25
    body_box = [cx - body_w / 2, cy - size * 0.02, cx + body_w / 2, cy - size * 0.02 + body_h]
    draw.rounded_rectangle(body_box, radius=int(size * 0.05), fill=(255, 255, 255, 255))
    
    # Shackle
    shackle_r = size * 0.12
    shackle_box = [cx - shackle_r, cy - size * 0.15 - shackle_r,
                   cx + shackle_r, cy - size * 0.15 + shackle_r]
    draw.arc(shackle_box, start=180, end=0, fill=(255, 255, 255, 255), width=max(2, int(size * 0.05)))
    
    # Cutout keyhole (transparent)
    key_cy = cy + size * 0.09
    key_r = size * 0.04
    draw.ellipse([cx - key_r, key_cy - key_r, cx + key_r, key_cy + key_r], fill=(0, 0, 0, 255))
    draw.rectangle([cx - key_r * 0.5, key_cy, cx + key_r * 0.5, key_cy + key_r * 1.6], fill=(0, 0, 0, 255))
    
    return img

def main():
    print("Generating master MultiPad brand logo (1024x1024)...")
    master_logo = create_multipad_master_logo(1024)
    os.makedirs("assets/images", exist_ok=True)
    master_logo.save("assets/images/multipad_logo.png", "PNG")
    
    # 512x512
    logo_512 = master_logo.resize((512, 512), Image.Resampling.LANCZOS)
    logo_512.save("assets/images/multipad_logo_512.png", "PNG")

    # 1. Android Mipmap Icons
    android_sizes = {
        "android/app/src/main/res/mipmap-mdpi/ic_launcher.png": 48,
        "android/app/src/main/res/mipmap-hdpi/ic_launcher.png": 72,
        "android/app/src/main/res/mipmap-xhdpi/ic_launcher.png": 96,
        "android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png": 144,
        "android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png": 192,
    }
    for path, sz in android_sizes.items():
        os.makedirs(os.path.dirname(path), exist_ok=True)
        master_logo.resize((sz, sz), Image.Resampling.LANCZOS).save(path, "PNG")
        print(f"Saved Android icon: {path} ({sz}x{sz})")

    # Android Quick Settings Tile Icon
    qs_icon = create_monochrome_qs_tile(96)
    os.makedirs("android/app/src/main/res/drawable", exist_ok=True)
    qs_icon.save("android/app/src/main/res/drawable/ic_qs_tile.png", "PNG")
    print("Saved Android Quick Settings tile icon: android/app/src/main/res/drawable/ic_qs_tile.png")

    # 2. macOS AppIcon AppIconSet
    macos_sizes = {
        "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_16.png": 16,
        "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_32.png": 32,
        "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_64.png": 64,
        "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_128.png": 128,
        "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_256.png": 256,
        "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_512.png": 512,
        "macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_1024.png": 1024,
    }
    for path, sz in macos_sizes.items():
        os.makedirs(os.path.dirname(path), exist_ok=True)
        master_logo.resize((sz, sz), Image.Resampling.LANCZOS).save(path, "PNG")
        print(f"Saved macOS icon: {path} ({sz}x{sz})")

    # 3. Windows Multi-Resolution ICO
    ico_path = "windows/runner/resources/app_icon.ico"
    os.makedirs(os.path.dirname(ico_path), exist_ok=True)
    ico_sizes = [(16, 16), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)]
    master_logo.save(ico_path, format="ICO", sizes=ico_sizes)
    print(f"Saved Windows ICO: {ico_path}")

    # 4. Browser Extension Icons
    ext_sizes = {
        "extension/icons/icon-16.png": 16,
        "extension/icons/icon-48.png": 48,
        "extension/icons/icon-128.png": 128,
    }
    for path, sz in ext_sizes.items():
        os.makedirs(os.path.dirname(path), exist_ok=True)
        master_logo.resize((sz, sz), Image.Resampling.LANCZOS).save(path, "PNG")
        print(f"Saved Extension icon: {path} ({sz}x{sz})")

    print("All platform icons successfully generated!")

if __name__ == "__main__":
    main()
