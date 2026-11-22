"""Download the dashboard's vendored JavaScript and verify it against pinned hashes.

Stdlib only, so it runs before any environment exists (in the image's build
stage, in CI, and from `just telemetry-vendor`). Files whose SHA-256 already
matches are left alone, so a second run needs no network.
"""

from __future__ import annotations

import base64
import hashlib
import io
import sys
import tarfile
import urllib.request
from pathlib import Path

VENDOR_DIR = Path(__file__).resolve().parent.parent / "src" / "telemetry_collector" / "static" / "vendor"

# To update: change the version, then take `integrity` from
# https://registry.npmjs.org/chart.js/<version> and the file hashes from the
# extracted tarball (`shasum -a 256`).
CHARTJS_VERSION = "4.6.1"
CHARTJS_URL = f"https://registry.npmjs.org/chart.js/-/chart.js-{CHARTJS_VERSION}.tgz"
CHARTJS_INTEGRITY = "sha512-hJyniucsFmq//EvXYvJ6c6mahPoI3kaxdjVH8awTaJ/fDNWeSqqqArixMJWkWNN6fcYvPU3HneSANFNYtRi61g=="
# Tarball member -> (path under VENDOR_DIR, SHA-256).
CHARTJS_FILES = {
    "package/dist/chart.umd.min.js": (
        "chartjs/chart.umd.min.js",
        "87364cc2b2a76a6684929e7d6b80b18a897794db38400caff1fcf1791c6925d2",
    ),
    "package/LICENSE.md": (
        "chartjs/LICENSE.md",
        "41a84aa2caba645f966a18d9c2056b73e6d3a81d80bc0046bc0011a2634d4cce",
    ),
}


def _sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _up_to_date() -> bool:
    for target, digest in CHARTJS_FILES.values():
        path = VENDOR_DIR / target
        if not path.is_file() or _sha256(path.read_bytes()) != digest:
            return False
    return True


def main() -> int:
    if _up_to_date():
        print(f"Chart.js {CHARTJS_VERSION}: up to date")
        return 0

    with urllib.request.urlopen(CHARTJS_URL, timeout=60) as response:  # noqa: S310 (fixed https URL)
        tarball = response.read()
    algorithm, expected = CHARTJS_INTEGRITY.split("-", 1)
    if base64.b64encode(hashlib.new(algorithm, tarball).digest()).decode() != expected:
        print(f"Chart.js {CHARTJS_VERSION}: tarball does not match its pinned integrity", file=sys.stderr)
        return 1

    with tarfile.open(fileobj=io.BytesIO(tarball), mode="r:gz") as archive:
        for member, (target, digest) in CHARTJS_FILES.items():
            extracted = archive.extractfile(member)
            if extracted is None:
                print(f"Chart.js {CHARTJS_VERSION}: {member} missing from the tarball", file=sys.stderr)
                return 1
            data = extracted.read()
            if _sha256(data) != digest:
                print(f"Chart.js {CHARTJS_VERSION}: {member} does not match its pinned SHA-256", file=sys.stderr)
                return 1
            path = VENDOR_DIR / target
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)

    print(f"Chart.js {CHARTJS_VERSION}: downloaded and verified")
    return 0


if __name__ == "__main__":
    sys.exit(main())
