#!/usr/bin/env python3
"""Offline regressions for developer scripts; requires Python 3, not Xcode."""
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class DeveloperToolsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="miho-tools-")
        self.addCleanup(self.temp.cleanup)
        self.work = Path(self.temp.name)
        self.bin = self.work / "bin"
        self.bin.mkdir()
        self.env = dict(os.environ, PATH=str(self.bin) + os.pathsep + os.environ["PATH"])

    def shell(self, script, **env):
        return subprocess.run(["bash", "-c", script], cwd=self.work,
                              env=dict(self.env, **env), capture_output=True, text=True)

    def mock_curl(self, payload, status=0):
        target = self.bin / "curl"
        target.write_text('#!/bin/bash\nwhile [[ "$1" != --output ]]; do shift; done\n'
                          'cp "$PAYLOAD" "$2"\nexit ' + str(status) + '\n')
        target.chmod(0o755)
        self.env["PAYLOAD"] = str(payload)

    def download(self, digest):
        return self.shell('source "$HELPER"; download_verified https://example.invalid/model "$DIGEST" "$OUTPUT"',
                          HELPER=str(ROOT / "scripts/download-verified.sh"), DIGEST=digest,
                          OUTPUT=str(self.work / "model.onnx"))

    def test_verified_download_publishes_complete_file(self):
        payload = self.work / "payload"
        payload.write_bytes(b"verified model")
        self.mock_curl(payload)
        result = self.download(hashlib.sha256(payload.read_bytes()).hexdigest())
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual((self.work / "model.onnx").read_bytes(), payload.read_bytes())
        self.assertEqual(list(self.work.glob("*.download.*")), [])

    def test_bad_hash_preserves_existing_model(self):
        payload = self.work / "payload"
        payload.write_bytes(b"bad model")
        self.mock_curl(payload)
        (self.work / "model.onnx").write_bytes(b"previous")
        result = self.download("0" * 64)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("SHA-256 mismatch", result.stderr)
        self.assertEqual((self.work / "model.onnx").read_bytes(), b"previous")
        self.assertEqual(list(self.work.glob("*.download.*")), [])

    def test_failed_transfer_cleans_partial_download(self):
        payload = self.work / "payload"
        payload.write_bytes(b"partial")
        self.mock_curl(payload, status=28)
        result = self.download("0" * 64)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Download failed", result.stderr)
        self.assertFalse((self.work / "model.onnx").exists())
        self.assertEqual(list(self.work.glob("*.download.*")), [])

    def test_missing_xctest_fails_before_download(self):
        scripts = self.work / "scripts"
        scripts.mkdir()
        for name in ["test.sh", "toolchain.sh"]:
            shutil.copy2(ROOT / "scripts" / name, scripts / name)
        prepare = scripts / "prepare-audio-models.sh"
        prepare.write_text('#!/bin/bash\ntouch download-started\n')
        prepare.chmod(0o755)
        result = self.shell('bash scripts/test.sh', DEVELOPER_DIR=str(self.work / "absent"))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Tests require full Xcode", result.stderr)
        self.assertFalse((self.work / "download-started").exists())

    def test_xctest_guard_accepts_framework(self):
        developer = self.work / "Developer"
        (developer / "Platforms/MacOSX.platform/Developer/Library/Frameworks/XCTest.framework").mkdir(parents=True)
        result = self.shell('source "$TOOLS"; require_xctest', TOOLS=str(ROOT / "scripts/toolchain.sh"),
                            DEVELOPER_DIR=str(developer))
        self.assertEqual(result.returncode, 0, result.stderr)

    def app_path(self, value):
        return self.shell('source "$HELPER"; resolve_app_path', HELPER=str(ROOT / "scripts/app-path.sh"),
                          MIHO_APP_PATH=value)

    def test_relative_app_path_preserves_spaces(self):
        result = self.app_path("staged output/Miho.app")
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout.strip(), str(self.work.resolve() / "staged output/Miho.app"))

    def test_absolute_app_path_is_preserved(self):
        path = str(self.work / "output/Miho.app")
        self.assertEqual(self.app_path(path).stdout.strip(), path)

    def test_invalid_app_path_is_rejected(self):
        result = self.app_path("output")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("must end in .app", result.stderr)

    def sdk_setup(self, complete):
        scripts = self.work / "scripts"
        scripts.mkdir()
        shutil.copy2(ROOT / "scripts/download-verified.sh", scripts)
        model = self.work / "Vendor/models/hop128.onnx"
        model.parent.mkdir(parents=True)
        model.write_bytes(b"fixture model")
        old = self.work / "Vendor/onnxruntime/keep.txt"
        old.parent.mkdir()
        old.write_text("previous cache")
        archive = self.work / "sdk.tgz"
        files = ["include/onnxruntime_cxx_api.h", "ThirdPartyNotices.txt"]
        if complete:
            files.append("lib/libonnxruntime.1.26.0.dylib")
        with tarfile.open(archive, "w:gz") as tar:
            for name in files:
                source = self.work / "fixture" / name
                source.parent.mkdir(parents=True, exist_ok=True)
                source.write_text("SDK fixture")
                tar.add(source, arcname="package/runtime/" + name)
        source = (ROOT / "scripts/prepare-audio-models.sh").read_text()
        source = source.replace("77164d6a581fafb2a31f53fd8ffde44c07cf618472952a4cdba14e68dda3b8b9",
                                hashlib.sha256(model.read_bytes()).hexdigest())
        source = source.replace("7a1280bbb1701ea514f71828765237e7896e0f2e1cd332f1f70dbd5c3e33aca3",
                                hashlib.sha256(archive.read_bytes()).hexdigest())
        (scripts / "prepare-audio-models.sh").write_text(source)
        self.mock_curl(archive)
        uname = self.bin / "uname"
        uname.write_text('#!/bin/bash\nprintf "arm64\\n"\n')
        uname.chmod(0o755)

    def test_incomplete_sdk_preserves_old_cache(self):
        self.sdk_setup(False)
        result = self.shell('bash scripts/prepare-audio-models.sh')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Incomplete SDK archive", result.stderr)
        self.assertEqual((self.work / "Vendor/onnxruntime/keep.txt").read_text(), "previous cache")
        self.assertEqual(list((self.work / "Vendor").glob("onnxruntime-stage.*")), [])

    def test_complete_sdk_replaces_cache_after_validation(self):
        self.sdk_setup(True)
        result = self.shell('bash scripts/prepare-audio-models.sh')
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.work / "Vendor/onnxruntime/lib/libonnxruntime.1.26.0.dylib").is_file())
        self.assertFalse((self.work / "Vendor/onnxruntime/keep.txt").exists())
        self.assertEqual(list((self.work / "Vendor").glob("onnxruntime-previous.*")), [])
        self.assertEqual(list((self.work / "Vendor").glob("onnxruntime-stage.*")), [])


if __name__ == "__main__":
    unittest.main(verbosity=2)
