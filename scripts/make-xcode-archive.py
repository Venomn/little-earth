#!/usr/bin/env python3
"""Wrap a verified signed SwiftPM app for Xcode's account-backed notary export."""
import datetime
import pathlib
import plistlib
import re
import subprocess
import sys

app = pathlib.Path(sys.argv[1]).resolve(strict=True)
destination = pathlib.Path(sys.argv[2]).resolve(strict=True)
subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
signature = subprocess.run(["codesign", "-dv", "--verbose=4", str(app)],
                           capture_output=True, text=True, check=True).stderr
identity = re.search(r"^Authority=(Developer ID Application: .+)$", signature, re.M)
team = re.search(r"^TeamIdentifier=([A-Z0-9]{10})$", signature, re.M)
if not identity or not team or "runtime" not in signature:
    raise SystemExit("A valid Developer ID app with hardened runtime is required.")
info = plistlib.loads((app / "Contents/Info.plist").read_bytes())
if info.get("CFBundleIdentifier") != "com.littleearth.companion":
    raise SystemExit("Unexpected application identity.")
architectures = subprocess.check_output(
    ["lipo", "-archs", str(app / "Contents/MacOS" / info["CFBundleExecutable"])], text=True).split()
archive = destination / "Little Earth.xcarchive"
products = archive / "Products/Applications"
products.mkdir(parents=True, exist_ok=False)
subprocess.run(["ditto", "--norsrc", str(app), str(products / app.name)], check=True)
metadata = {
    "ArchiveVersion": 2,
    "CreationDate": datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None),
    "Name": "Little Earth", "SchemeName": "LittleEarth",
    "ApplicationProperties": {
        "ApplicationPath": "Applications/" + app.name,
        "CFBundleIdentifier": info["CFBundleIdentifier"],
        "CFBundleShortVersionString": info["CFBundleShortVersionString"],
        "CFBundleVersion": info["CFBundleVersion"],
        "SigningIdentity": identity[1], "Team": team[1], "Architectures": architectures,
    },
}
(archive / "Info.plist").write_bytes(plistlib.dumps(metadata))
(destination / "ExportOptions.plist").write_bytes(plistlib.dumps({
    "method": "developer-id", "destination": "upload", "signingStyle": "manual",
    "signingCertificate": identity[1], "teamID": team[1],
}))
print(archive)
