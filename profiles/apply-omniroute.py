"""Apply the versioned Desktop profile while preserving its local API key."""
import json
import os
from pathlib import Path
import tempfile

library = Path.home() / "Library/Application Support/Claude-3p/configLibrary"
metadata = json.loads((library / "_meta.json").read_text())
entries = [e for e in metadata["entries"] if e["name"] == "OmniRoute"]
if len(entries) != 1:
    raise SystemExit("Create exactly one OmniRoute profile in Claude first.")
target = library / (entries[0]["id"] + ".json")
current = json.loads(target.read_text())
settings = json.loads(Path(__file__).with_name("omniroute.json").read_text())
allowed = {
    "inferenceGatewayBaseUrl",
    "modelDiscoveryEnabled",
    "inferenceProvider",
    "inferenceCredentialKind",
    "inferenceModels",
}
if set(settings) != allowed:
    raise SystemExit("Profile template must contain only the expected non-secret settings.")
if current.get("inferenceGatewayApiKey") and (
    current.get("inferenceGatewayBaseUrl", "").rstrip("/")
    != settings["inferenceGatewayBaseUrl"].rstrip("/")
):
    raise SystemExit("Remove the existing API key before switching gateway URLs.")
updated = dict(current, **settings)
fd, temporary = tempfile.mkstemp(prefix=".omniroute-", dir=library)
try:
    with os.fdopen(fd, "w") as stream:
        json.dump(updated, stream, ensure_ascii=False, indent=2)
        stream.write("\n")
    os.replace(temporary, target)
finally:
    if os.path.exists(temporary):
        os.unlink(temporary)
print("OmniRoute settings applied; local credentials preserved. Reapply the profile in Claude.")
