#!/usr/bin/env python3
"""Export the selected emulator Terraform workspace for Docker Compose."""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile


def write_environment(outputs, ca, directory):
    runtime = outputs.get("emulator_runtime", {}).get("value")
    if not runtime:
        raise ValueError("Apply Terraform with aws_emulator=true in this workspace first.")
    if not all(isinstance(value, str) and value for value in runtime.values()):
        raise ValueError("Emulator outputs contain empty or invalid values.")
    certificate = ca.read_bytes()
    if b"-----BEGIN CERTIFICATE-----" not in certificate:
        raise ValueError("AWS_CA_BUNDLE must point to the emulator CA PEM file.")
    content = "".join(
        key + "='" + value.replace("'", "\\'") + "'\n"
        for key, value in sorted(runtime.items())
    )
    for name, data in [
        (".emulator-ca.pem", certificate),
        (".env.emulator", content.encode()),
    ]:
        with tempfile.NamedTemporaryFile(dir=directory, delete=False) as target:
            try:
                target.write(data)
                target.close()
                os.replace(target.name, directory / name)
            finally:
                Path(target.name).unlink(missing_ok=True)


def main():
    directory = Path(__file__).resolve().parent
    try:
        ca = Path(os.environ["AWS_CA_BUNDLE"])
        result = subprocess.run(
            ["terraform", "output", "-json"],
            cwd=directory / "terraform",
            check=True,
            capture_output=True,
            text=True,
        )
        write_environment(json.loads(result.stdout), ca, directory)
    except (KeyError, OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"Cannot generate emulator environment: {error}", file=sys.stderr)
        return 1
    print("Created .env.emulator (mode 0600) and .emulator-ca.pem; do not publish them.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
