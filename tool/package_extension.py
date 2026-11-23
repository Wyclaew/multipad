import os
import zipfile

def package_extension():
    ext_dir = os.path.abspath("extension")
    output_xpi = os.path.join(ext_dir, "multipad-firefox.xpi")
    output_zip = os.path.join(ext_dir, "multipad-extension.zip")

    files_to_pack = [
        "manifest.json",
        "background.js",
        "content.js",
        "popup.html",
        "popup.css",
        "popup.js",
    ]

    for out_path in [output_xpi, output_zip]:
        with zipfile.ZipFile(out_path, 'w', zipfile.ZIP_DEFLATED) as zf:
            for f in files_to_pack:
                src = os.path.join(ext_dir, f)
                if os.path.exists(src):
                    zf.write(src, arcname=f)
            
            # Pack icons directory
            icons_dir = os.path.join(ext_dir, "icons")
            if os.path.exists(icons_dir):
                for icon in os.listdir(icons_dir):
                    if icon.endswith(".png"):
                        src = os.path.join(icons_dir, icon)
                        zf.write(src, arcname=f"icons/{icon}")

        print(f"Created package: {out_path} ({os.path.getsize(out_path)} bytes)")

if __name__ == "__main__":
    package_extension()
