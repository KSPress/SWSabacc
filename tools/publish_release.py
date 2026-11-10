#!/usr/bin/env python3
"""Upload verified local builds to GitHub Releases. Draft by default.

Uses the existing GitHub credential helper; never logs or stores its token.
  python -I tools/publish_release.py [--publish]
Build and test first. Commit/push the corresponding source before publishing.
"""
import argparse
import hashlib
import json
import os
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REPO = "KSPress/SWSabacc"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--publish", action="store_true", help="Publish after all uploads complete")
    args = parser.parse_args()
    manifest_path = ROOT / "build/android/sabacc-update.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    apk = ROOT / "build/android/swu_sabacc.apk"
    with apk.open("rb") as stream:
        digest = hashlib.sha256()
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    if apk.stat().st_size != manifest["size"] or digest.hexdigest() != manifest["sha256"]:
        sys.exit("APK does not match update.json; rebuild before releasing.")
    tag = "v" + manifest["version_name"]
    expected_url = f"https://github.com/{REPO}/releases/download/{tag}/swu_sabacc.apk"
    if manifest["apk_url"] != expected_url:
        sys.exit("Manifest URL does not match this release.")
    files = [apk, manifest_path, ROOT / "build/SWSabacc-windows.zip",
             ROOT / "build/android/update.json", ROOT / "build/android/swu_kyber.apk"]
    for path in files:
        if not path.is_file():
            sys.exit(f"Missing release file: {path.name}")
    legacy = json.loads((ROOT / "build/android/update.json").read_text(encoding="utf-8"))
    legacy_url = f"https://github.com/KSPress/SWU-Kyber/releases/download/{tag}/swu_kyber.apk"
    if legacy != dict(manifest, apk_url=legacy_url):
        sys.exit("Legacy updater bridge does not match the new manifest.")
    with (ROOT / "build/android/swu_kyber.apk").open("rb") as stream:
        legacy_digest = hashlib.sha256()
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            legacy_digest.update(chunk)
    if legacy_digest.hexdigest() != manifest["sha256"]:
        sys.exit("Legacy APK alias differs from the tested APK.")
    git = lambda *a: subprocess.run(["git", "-C", str(ROOT), *a], check=True, capture_output=True, text=True).stdout.strip()
    if git("status", "--porcelain", "--untracked-files=no"):
        sys.exit("Commit the tested source changes before releasing.")
    revision = git("rev-parse", "HEAD")
    env = dict(os.environ, GIT_TERMINAL_PROMPT="0", GCM_INTERACTIVE="Never")
    credential = subprocess.run(["git", "credential", "fill"], input="protocol=https\nhost=github.com\n\n",
                                capture_output=True, text=True, env=env, timeout=30)
    fields = dict(line.split("=", 1) for line in credential.stdout.splitlines() if "=" in line)
    token = fields.get("password")
    if credential.returncode or not token:
        sys.exit("No saved GitHub credential is available.")

    def api(path, method="GET", data=None, content_type="application/json"):
        url = path if path.startswith("https://uploads.github.com/") else "https://api.github.com" + path
        payload = json.dumps(data).encode() if isinstance(data, dict) else data
        request = urllib.request.Request(url, data=payload, method=method, headers={
            "Authorization": "Bearer " + token, "Accept": "application/vnd.github+json",
            "User-Agent": "SWSabacc-release", "X-GitHub-Api-Version": "2022-11-28", "Content-Type": content_type})
        with urllib.request.urlopen(request, timeout=300) as response:
            return json.load(response)

    api(f"/repos/{REPO}/commits/{revision}")  # refuse a release with unpublished source
    try:
        release = api(f"/repos/{REPO}/releases/tags/{tag}")
    except urllib.error.HTTPError as error:
        if error.code != 404:
            raise
        notes = (ROOT / "docs/RELEASE_NOTES.md").read_text(encoding="utf-8")
        release = api(f"/repos/{REPO}/releases", "POST", {
            "tag_name": tag, "target_commitish": revision, "name": f"SWU Sabacc {tag}",
            "body": notes, "draft": True, "prerelease": False})
    if not release["draft"]:
        sys.exit("This release is already published; use a new version instead of replacing it.")
    existing = {item["name"]: item for item in release["assets"]}
    for path in files:
        if path.name in existing:
            item = existing[path.name]
            with path.open("rb") as stream:
                local_digest = hashlib.sha256(stream.read()).hexdigest()
            if item.get("digest") != "sha256:" + local_digest:
                sys.exit(f"Existing draft asset differs: {path.name}; resolve it before publishing.")
            print("Already uploaded:", path.name, flush=True)
            continue
        url = release["upload_url"].split("{", 1)[0] + "?name=" + urllib.parse.quote(path.name)
        print("Uploading:", path.name, path.stat().st_size, "bytes", flush=True)
        kind = "application/vnd.android.package-archive" if path.suffix == ".apk" else "application/octet-stream"
        api(url, "POST", path.read_bytes(), kind)
    if args.publish:
        release = api(f"/repos/{REPO}/releases/{release['id']}", "PATCH", {"draft": False, "make_latest": "true"})
    print("Published:" if args.publish else "Draft ready:", release["html_url"], flush=True)


if __name__ == "__main__":
    try:
        main()
    except urllib.error.HTTPError as error:
        sys.exit(f"GitHub API returned HTTP {error.code}; any partial release remains a draft.")
