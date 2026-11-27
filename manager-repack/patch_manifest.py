#!/usr/bin/env python3
"""Manifest patch for the repacked manager.

Run from the upstream `manager/` directory (the workflow does `cd upstream/manager`).

* drops the custom Application class (`android:name=".Sys"`) so the app no longer
  advertises an Application subclass;
* registers AppInitProvider, which performs the same Koin/application initialisation
  before the first Activity starts.
"""
import re

MANIFEST = "app/src/main/AndroidManifest.xml"

PROVIDER = """        <provider
            android:name=".AppInitProvider"
            android:authorities="${applicationId}.init"
            android:exported="false" />
"""


def main() -> None:
    with open(MANIFEST, encoding="utf-8") as fh:
        text = fh.read()

    text = text.replace('\n        android:name=".Sys"', "")

    text, count = re.subn(
        r"(<application\b[^>]*>)",
        lambda m: m.group(1) + "\n" + PROVIDER,
        text,
        count=1,
    )
    assert count == 1, "application tag not found"

    with open(MANIFEST, "w", encoding="utf-8") as fh:
        fh.write(text)
    print("manifest patched: custom Application removed, AppInitProvider added")


if __name__ == "__main__":
    main()
