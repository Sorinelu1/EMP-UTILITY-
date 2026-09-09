from __future__ import annotations

import hashlib
import os
import re
import shutil
import stat
import struct
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path


ROOT = Path(__file__).resolve().parent
SOURCE = ROOT / "src"
OUTPUT = ROOT / "dist"
ZIP_PATH = OUTPUT / "EMP-UTILITY-v1.3-R4-CI-Windows.zip"
SIDE_PATH = OUTPUT / (ZIP_PATH.name + ".sha256")
MANIFEST = SOURCE / "MANIFEST_PACHET.sha256"
LOG_PATH = ROOT / "LOG_BUILD_R4.txt"
FIXED_TIME = (2026, 9, 2, 0, 0, 0)
PARTS_DIRECTORY = ROOT / "payload_parts"
PART_MAX_BYTES = 15_000_000


def digest(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


def cleanup() -> None:
    for path in sorted(SOURCE.rglob("*.pyc")):
        path.unlink()
    for path in sorted(SOURCE.rglob("__pycache__"), reverse=True):
        if path.is_dir() and not any(path.iterdir()):
            path.rmdir()


def validate_repository_payload() -> None:
    parts = sorted(PARTS_DIRECTORY.glob("EMP-UTILITY-SOURCE.zip.part*"))
    if not parts:
        raise SystemExit("BUILD FAIL: lipsesc partile arhivei sursa")
    expected_names = [f"EMP-UTILITY-SOURCE.zip.part{i:03d}"
                      for i in range(1, len(parts) + 1)]
    actual_names = [path.name for path in parts]
    if actual_names != expected_names:
        raise SystemExit(
            f"BUILD FAIL: partile nu sunt consecutive: {actual_names!r}"
        )
    oversized = [(path.name, path.stat().st_size) for path in parts
                 if path.stat().st_size >= PART_MAX_BYTES]
    if oversized:
        raise SystemExit(
            f"BUILD FAIL: parti de minimum 15 MB detectate: {oversized!r}"
        )

    source_hash_file = PARTS_DIRECTORY / "SOURCE_PAYLOAD.sha256"
    match = re.fullmatch(
        r"([0-9a-f]{64})  EMP-UTILITY-SOURCE\.zip\n?",
        source_hash_file.read_text(encoding="ascii"),
    )
    if not match:
        raise SystemExit("BUILD FAIL: SOURCE_PAYLOAD.sha256 invalid")
    source_hash = hashlib.sha256()
    for path in parts:
        with path.open("rb") as stream:
            for block in iter(lambda: stream.read(1024 * 1024), b""):
                source_hash.update(block)
    if source_hash.hexdigest() != match.group(1):
        raise SystemExit("BUILD FAIL: hash-ul payloadului reasamblat este gresit")

    part_manifest = PARTS_DIRECTORY / "PARTS_MANIFEST.sha256"
    lines = part_manifest.read_text(encoding="ascii").splitlines()
    expected_part_hashes = {}
    for line in lines:
        parsed = re.fullmatch(
            r"([0-9a-f]{64})  (EMP-UTILITY-SOURCE\.zip\.part\d{3})", line)
        if not parsed:
            raise SystemExit(f"BUILD FAIL: linie PARTS_MANIFEST invalida: {line!r}")
        expected_part_hashes[parsed.group(2)] = parsed.group(1)
    if set(expected_part_hashes) != set(actual_names):
        raise SystemExit("BUILD FAIL: PARTS_MANIFEST nu corespunde listei de parti")
    for path in parts:
        if digest(path) != expected_part_hashes[path.name]:
            raise SystemExit(f"BUILD FAIL: hash gresit pentru {path.name}")
    print(
        f"REPOSITORY_PAYLOAD_GATE_PASS parts={len(parts)} "
        f"max_bytes={max(path.stat().st_size for path in parts)}"
    )


def validate_python_sources() -> None:
    problems = []
    for path in sorted(SOURCE.rglob("*.py")):
        try:
            compile(path.read_bytes(), str(path), "exec")
        except Exception as exc:
            problems.append(f"{path.relative_to(SOURCE)}: {exc}")
    if problems:
        raise SystemExit("BUILD FAIL: Python invalid:\n" + "\n".join(problems))
    print(f"PYTHON_PARSE_GATE_PASS {len(list(SOURCE.rglob('*.py')))}")


def _pe_machine(path: Path) -> int:
    data = path.read_bytes()
    if data[:2] != b"MZ" or len(data) < 0x40:
        return 0
    offset = struct.unpack_from("<I", data, 0x3C)[0]
    if data[offset:offset + 4] != b"PE\0\0":
        return 0
    return struct.unpack_from("<H", data, offset + 4)[0]


def validate_runtime_payload() -> None:
    pth = SOURCE / "resurse/runtime/python/python311._pth"
    expected = ["python311.zip", ".", "Lib", "Lib\\site-packages", "import site"]
    actual = pth.read_text(encoding="ascii").splitlines()
    if actual != expected:
        raise SystemExit(f"BUILD FAIL: python311._pth invalid: {actual!r}")

    native = [
        SOURCE / "resurse/runtime/python/python.exe",
        SOURCE / "resurse/runtime/python/pythonw.exe",
        SOURCE / "resurse/runtime/tesseract/tesseract.exe",
        *(SOURCE / "resurse/runtime/python").glob("*.dll"),
        *(SOURCE / "resurse/runtime/python").glob("*.pyd"),
        *(SOURCE / "resurse/runtime/tesseract").glob("*.dll"),
    ]
    for path in native:
        rel = path.relative_to(SOURCE).as_posix()
        if _pe_machine(path) != 0x8664:
            raise SystemExit(f"BUILD FAIL: nu este PE AMD64 valid: {rel}")

    wheels = sorted((SOURCE / "resurse/biblioteci").glob("*.whl"))
    if len(wheels) != 16:
        raise SystemExit(f"BUILD FAIL: asteptat 16 wheel-uri, gasit {len(wheels)}")
    continut = {}
    for wheel in wheels:
        with zipfile.ZipFile(wheel) as archive:
            bad = archive.testzip()
            if bad:
                raise SystemExit(f"BUILD FAIL: wheel corupt {wheel.name}: {bad}")
            continut[wheel.name] = set(archive.namelist())
    typing = next((v for k, v in continut.items() if k.startswith("typing_extensions-")), set())
    docx = next((v for k, v in continut.items() if k.startswith("python_docx-")), set())
    if "typing_extensions.py" not in typing:
        raise SystemExit("BUILD FAIL: wheel-ul typing_extensions nu contine modulul")
    if "docx/__init__.py" not in docx:
        raise SystemExit("BUILD FAIL: wheel-ul python-docx nu contine pachetul docx")

    instalator = (SOURCE / "resurse/instalator/instaleaza_platforma.ps1").read_text(
        encoding="utf-8-sig")
    if instalator.find('"typing_extensions-*.whl"') > instalator.find('"python_docx-*.whl"'):
        raise SystemExit("BUILD FAIL: typing_extensions nu precede python-docx")
    if re.search(r"(?i)\bpip(?:\.exe)?\s+(install|download)\b", instalator):
        raise SystemExit("BUILD FAIL: instalatorul contine invocare pip")
    if "sitecustomize_emp_utility.py" not in instalator:
        raise SystemExit("BUILD FAIL: politica offline nu este instalata in runtime")
    print("RUNTIME_STATIC_GATE_PASS python311._pth PE_AMD64 wheels=16 offline=ENFORCED")


def validate_identity_and_entrypoint() -> None:
    bat = (SOURCE / "00_INSTALEAZA_SI_PORNESTE_EMP_UTILITY.bat").read_text(
        encoding="utf-8-sig")
    if "%SystemRoot%\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" not in bat:
        raise SystemExit("BUILD FAIL: bootstrapul nu fixeaza Windows PowerShell de sistem")
    if re.search(r"(?i)Platforma[- ]PTE", bat):
        raise SystemExit("BUILD FAIL: identitate publica veche in punctul de pornire")
    if not (SOURCE / "COMPATIBILITATE_INTERNA.md").is_file():
        raise SystemExit("BUILD FAIL: lipseste documentarea compatibilitatii interne")
    print("IDENTITY_ENTRYPOINT_GATE_PASS")


def validate_powershell() -> None:
    ps_files = sorted({*SOURCE.rglob("*.ps1"), *(ROOT / "ci").rglob("*.ps1")})
    if os.name == "nt":
        powershell = Path(os.environ.get("SystemRoot", r"C:\Windows")) / (
            "System32/WindowsPowerShell/v1.0/powershell.exe")
        gate = ROOT / "ci/Invoke-PowerShellParseGate.ps1"
        completed = subprocess.run(
            [str(powershell), "-NoLogo", "-NoProfile", "-NonInteractive",
             "-ExecutionPolicy", "Bypass", "-File", str(gate),
             "-Root", str(ROOT)], check=False)
        if completed.returncode:
            raise SystemExit("BUILD FAIL: parserul Windows PowerShell a raportat erori")
    else:
        try:
            from tree_sitter import Language, Parser
            import tree_sitter_powershell
        except ImportError as exc:
            raise SystemExit("BUILD FAIL: lipseste parserul PowerShell real") from exc
        parser = Parser(Language(tree_sitter_powershell.language()))
        problems = []
        for path in ps_files:
            data = path.read_bytes()
            tree = parser.parse(data)

            def inspect(node):
                if node.type == "ERROR" or node.is_missing:
                    problems.append(
                        (path.relative_to(ROOT).as_posix(), node.start_point,
                         data[node.start_byte:node.end_byte][:120])
                    )
                for child in node.children:
                    inspect(child)

            inspect(tree.root_node)
        if problems:
            for path, point, fragment in problems:
                print("POWERSHELL PARSE FAIL", path, point, fragment)
            raise SystemExit("BUILD FAIL: PowerShell nu poate fi parsat")
    for path in ps_files:
        text = path.read_text(encoding="utf-8-sig")
        if re.search(
            r"\$(?!env:|script:|global:|local:|private:|using:)"
            r"[A-Za-z_][A-Za-z0-9_]*:", text
        ):
            raise SystemExit(
                f"BUILD FAIL: interpolare PowerShell ambigua variabila+colon: {path}"
            )
        if re.search(r"foreach\s*\([^\r\n)]*\bin\s+(?!\()\w+-\w+", text,
                     flags=re.IGNORECASE):
            raise SystemExit(
                f"BUILD FAIL: expresie foreach negrupata in paranteze: {path}"
            )
    print(f"POWERSHELL_PARSE_GATE_PASS {len(ps_files)}")


def validate_clean_tree() -> None:
    forbidden = []
    for path in SOURCE.rglob("*"):
        if not path.is_file():
            continue
        name = path.name.lower()
        if (name.endswith((".partial", ".tmp", ".pyc")) or
                "__pycache__" in path.parts or
                (name.startswith(".") and name != ".gitignore")):
            forbidden.append(path.relative_to(SOURCE).as_posix())
    if forbidden:
        raise SystemExit("BUILD FAIL: fisiere temporare: " + ", ".join(forbidden))
    print("CLEAN_TREE_GATE_PASS")


def files(include_manifest: bool) -> list[Path]:
    result = []
    for path in SOURCE.rglob("*"):
        if not path.is_file():
            continue
        if not include_manifest and path == MANIFEST:
            continue
        result.append(path)
    return sorted(result, key=lambda p: p.relative_to(SOURCE).as_posix())


def write_manifest() -> None:
    lines = [f"{digest(path)}  {path.relative_to(SOURCE).as_posix()}"
             for path in files(include_manifest=False)]
    MANIFEST.write_text("\n".join(lines) + "\n", encoding="ascii", newline="\n")


def _write_zip(path_zip: Path) -> None:
    with zipfile.ZipFile(path_zip, "w", compression=zipfile.ZIP_DEFLATED,
                         compresslevel=9, allowZip64=True) as archive:
        for path in files(include_manifest=True):
            rel = path.relative_to(SOURCE).as_posix()
            info = zipfile.ZipInfo(rel, FIXED_TIME)
            info.compress_type = zipfile.ZIP_DEFLATED
            info.create_system = 3
            info.external_attr = (stat.S_IFREG | 0o644) << 16
            info.flag_bits |= 0x800
            archive.writestr(info, path.read_bytes(), compress_type=zipfile.ZIP_DEFLATED,
                             compresslevel=9)


def validate_zip(path_zip: Path) -> None:
    with zipfile.ZipFile(path_zip, "r") as archive:
        bad = archive.testzip()
        if bad is not None:
            raise SystemExit(f"BUILD FAIL: intrare ZIP corupta: {bad}")
        names = archive.namelist()
        if len(names) != len(set(names)):
            raise SystemExit("BUILD FAIL: intrari duplicate in ZIP")
        manifest_lines = archive.read("MANIFEST_PACHET.sha256").decode("ascii").splitlines()
        expected = {}
        for line in manifest_lines:
            match = re.fullmatch(r"([0-9a-f]{64})  (.+)", line)
            if not match:
                raise SystemExit(f"BUILD FAIL: linie manifest invalida: {line!r}")
            expected[match.group(2)] = match.group(1)
        actual = set(names) - {"MANIFEST_PACHET.sha256"}
        if actual != set(expected):
            raise SystemExit(
                f"BUILD FAIL: manifest/ZIP difera lipsa={sorted(set(expected)-actual)} "
                f"extra={sorted(actual-set(expected))}"
            )
        for name, wanted in expected.items():
            got = hashlib.sha256(archive.read(name)).hexdigest()
            if got != wanted:
                raise SystemExit(f"BUILD FAIL: hash manifest gresit: {name}")
    print(f"ZIP_MANIFEST_GATE_PASS {len(expected)}/{len(expected)}")


def build_zip() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)
    if ZIP_PATH.exists():
        ZIP_PATH.unlink()
    _write_zip(ZIP_PATH)
    validate_zip(ZIP_PATH)
    repro = ZIP_PATH.with_name(ZIP_PATH.name + ".repro.tmp")
    try:
        _write_zip(repro)
        if digest(repro) != digest(ZIP_PATH):
            raise SystemExit("BUILD FAIL: ZIP-ul nu este reproductibil byte-cu-byte")
    finally:
        if repro.exists():
            repro.unlink()
    print("REPRODUCIBLE_ZIP_GATE_PASS")
    sha = digest(ZIP_PATH)
    SIDE_PATH.write_text(f"{sha}  {ZIP_PATH.name}\n", encoding="ascii", newline="\n")
    print(f"{ZIP_PATH.name} {ZIP_PATH.stat().st_size} {sha}")


def main() -> None:
    validate_repository_payload()
    cleanup()
    validate_python_sources()
    validate_powershell()
    validate_runtime_payload()
    validate_identity_and_entrypoint()
    validate_clean_tree()
    write_manifest()
    build_zip()


class _Tee:
    def __init__(self, *streams):
        self.streams = streams

    def write(self, value):
        for stream in self.streams:
            stream.write(value)
        return len(value)

    def flush(self):
        for stream in self.streams:
            stream.flush()


if __name__ == "__main__":
    with LOG_PATH.open("w", encoding="utf-8", newline="\n") as log:
        stdout, stderr = sys.stdout, sys.stderr
        sys.stdout = _Tee(stdout, log)
        sys.stderr = _Tee(stderr, log)
        try:
            main()
        finally:
            sys.stdout.flush()
            sys.stderr.flush()
            sys.stdout, sys.stderr = stdout, stderr
