import importlib.util
from pathlib import Path
import stat
import tempfile
import unittest


spec = importlib.util.spec_from_file_location(
    "emulator_env", Path(__file__).with_name("emulator-env.py")
)
emulator_env = importlib.util.module_from_spec(spec)
spec.loader.exec_module(emulator_env)


class EnvironmentTest(unittest.TestCase):
    def test_writes_private_environment_and_ca(self):
        with tempfile.TemporaryDirectory() as scratch:
            directory = Path(scratch)
            ca = directory / "ca.pem"
            ca.write_bytes(b"-----BEGIN CERTIFICATE-----\nexample\n")
            emulator_env.write_environment(
                {"emulator_runtime": {"value": {
                    "CONFIG": '[pg]\nurl = "${PG_PASSWORD}"\n',
                    "TOKEN": "example'token",
                }}}, ca, directory,
            )
            target = directory / ".env.emulator"
            self.assertEqual(stat.S_IMODE(target.stat().st_mode), 0o600)
            self.assertIn('${PG_PASSWORD}', target.read_text())
            self.assertIn("example\\'token", target.read_text())
            self.assertEqual((directory / ".emulator-ca.pem").read_bytes(), ca.read_bytes())

    def test_rejects_empty_and_real_aws_outputs(self):
        for outputs in [{}, {"emulator_runtime": {"value": None}},
                        {"emulator_runtime": {"value": {"TOKEN": ""}}}]:
            with self.subTest(outputs=outputs), self.assertRaises(ValueError):
                emulator_env.write_environment(outputs, Path("unused"), Path("unused"))

    def test_rejects_invalid_ca_without_writing_environment(self):
        with tempfile.TemporaryDirectory() as scratch:
            directory = Path(scratch)
            ca = directory / "ca.pem"
            ca.write_bytes(b"not a certificate")
            with self.assertRaises(ValueError):
                emulator_env.write_environment(
                    {"emulator_runtime": {"value": {"TOKEN": "example"}}}, ca, directory,
                )
            self.assertFalse((directory / ".env.emulator").exists())


if __name__ == "__main__":
    unittest.main()
