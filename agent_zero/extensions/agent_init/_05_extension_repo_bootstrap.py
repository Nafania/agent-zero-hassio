"""Bootstrap Agent Zero extensions from one or more Git repositories.

Reads Home Assistant addon options from ``/data/options.json`` and supports:
- multiple extension repositories
- idempotent clone/pull at startup
- optional installer auto-execution
- optional auto-run startup commands from manifest

Configuration keys (addon options):
- extension_repositories: list[str]
- extensions_auto_install: bool
- extensions_auto_run_installers: bool
- extensions_auto_run_commands: bool

Repository conventions:
- Optional manifest file: ``agent0-extension.json``
- Optional installer scripts (auto-detected if manifest does not define one):
  - install_agent0_extension.sh
  - install_agent0_telegram_ext.sh
  - install.sh
- Fallback auto-install copy from ``python/extensions`` to ``/a0/python/extensions``
"""

from __future__ import annotations

import json
import shutil
import subprocess
import threading
from pathlib import Path
from typing import Any
from urllib.parse import urlparse

try:
	from python.helpers.extension import Extension  # pyright: ignore[reportMissingImports]
except Exception:  # pragma: no cover - local fallback outside Agent Zero runtime
	class Extension:  # type: ignore[override]
		def __init__(self, agent=None, **kwargs):
			self.agent = agent


OPTIONS_FILE = Path("/data/options.json")
AGENT0_ROOT = Path("/a0")
REPOS_ROOT = Path("/a0/usr/extensions/repos")
MANIFEST_NAME = "agent0-extension.json"
DEFAULT_EXTENSION_PATHS = ["python/extensions"]
KNOWN_INSTALL_SCRIPTS = [
	"install_agent0_extension.sh",
	"install_agent0_telegram_ext.sh",
	"install.sh",
]


def _log(message: str) -> None:
	print(f"[ext-repo-bootstrap] {message}")


def _read_options() -> dict[str, Any]:
	if not OPTIONS_FILE.exists():
		return {}
	try:
		raw = OPTIONS_FILE.read_text(encoding="utf-8")
		data = json.loads(raw) if raw else {}
		return data if isinstance(data, dict) else {}
	except Exception as exc:
		_log(f"Unable to read options file ({OPTIONS_FILE}): {exc}")
		return {}


def _to_bool(value: Any, default: bool) -> bool:
	if isinstance(value, bool):
		return value
	if isinstance(value, str):
		normalized = value.strip().lower()
		if normalized in {"1", "true", "yes", "on"}:
			return True
		if normalized in {"0", "false", "no", "off"}:
			return False
	return default


def _parse_repositories(value: Any) -> list[str]:
	if isinstance(value, list):
		repos = [str(x).strip() for x in value if str(x).strip()]
		return list(dict.fromkeys(repos))

	if isinstance(value, str):
		normalized = value.replace("\n", ",").replace(";", ",")
		parts = [x.strip() for x in normalized.split(",") if x.strip()]
		return list(dict.fromkeys(parts))

	return []


def _slug_from_url(url: str) -> str:
	parsed = urlparse(url)
	candidate = (parsed.path or "").strip("/")
	if candidate.endswith(".git"):
		candidate = candidate[:-4]
	name = candidate.rsplit("/", 1)[-1].strip().lower() if candidate else "extension"
	safe = "".join(ch if ch.isalnum() or ch in {"-", "_"} else "-" for ch in name)
	return safe or "extension"


def _run(command: list[str], cwd: Path | None = None, shell: bool = False) -> tuple[int, str]:
	try:
		completed = subprocess.run(
			command if not shell else " ".join(command),
			cwd=str(cwd) if cwd else None,
			shell=shell,
			capture_output=True,
			text=True,
			check=False,
		)
		output = (completed.stdout or "") + (completed.stderr or "")
		return completed.returncode, output.strip()
	except Exception as exc:
		return 1, str(exc)


def _clone_or_update_repo(repo_url: str, repo_path: Path) -> bool:
	repo_path.parent.mkdir(parents=True, exist_ok=True)
	if (repo_path / ".git").exists():
		code, out = _run(["git", "-C", str(repo_path), "pull", "--ff-only"])
		if code != 0:
			_log(f"git pull failed for {repo_url}: {out}")
			return False
		_log(f"Updated repository: {repo_url}")
		return True

	code, out = _run(["git", "clone", "--depth", "1", repo_url, str(repo_path)])
	if code != 0:
		_log(f"git clone failed for {repo_url}: {out}")
		return False

	_log(f"Cloned repository: {repo_url}")
	return True


def _load_manifest(repo_path: Path) -> dict[str, Any]:
	manifest_path = repo_path / MANIFEST_NAME
	if not manifest_path.exists():
		return {}
	try:
		raw = manifest_path.read_text(encoding="utf-8")
		data = json.loads(raw) if raw else {}
		if isinstance(data, dict):
			return data
	except Exception as exc:
		_log(f"Invalid manifest in {manifest_path}: {exc}")
	return {}


def _copy_if_changed(src: Path, dst: Path) -> None:
	dst.parent.mkdir(parents=True, exist_ok=True)
	if dst.exists():
		try:
			if src.read_bytes() == dst.read_bytes():
				return
		except Exception:
			pass
	shutil.copy2(src, dst)


def _copy_extensions_tree(repo_path: Path, relative_paths: list[str]) -> int:
	copied = 0
	for rel in relative_paths:
		source_root = repo_path / rel
		if not source_root.exists() or not source_root.is_dir():
			continue

		for src in source_root.rglob("*.py"):
			rel_file = src.relative_to(source_root)
			dst = AGENT0_ROOT / "python" / "extensions" / rel_file
			_copy_if_changed(src, dst)
			copied += 1
	return copied


def _maybe_run_install_script(repo_path: Path, manifest: dict[str, Any], auto_run_installers: bool) -> bool:
	if not auto_run_installers:
		_log(f"Installer auto-run disabled for {repo_path.name}")
		return False

	script_name = ""
	manifest_script = manifest.get("install_script")
	if isinstance(manifest_script, str) and manifest_script.strip():
		script_name = manifest_script.strip()
	else:
		for candidate in KNOWN_INSTALL_SCRIPTS:
			if (repo_path / candidate).exists():
				script_name = candidate
				break

	if not script_name:
		return False

	script_path = repo_path / script_name
	if not script_path.exists():
		_log(f"Installer script declared but missing: {script_path}")
		return False

	script_path.chmod(script_path.stat().st_mode | 0o111)

	args = ["/a0"]
	manifest_args = manifest.get("install_args")
	if isinstance(manifest_args, list) and manifest_args:
		args = [str(x) for x in manifest_args]

	code, out = _run([str(script_path), *args], cwd=repo_path)
	if code != 0:
		_log(f"Installer failed ({script_name}) for {repo_path.name}: {out}")
		return False

	_log(f"Installer executed ({script_name}) for {repo_path.name}")
	if out:
		_log(out)
	return True


def _maybe_run_auto_commands(repo_path: Path, manifest: dict[str, Any], auto_run_commands: bool) -> None:
	if not auto_run_commands:
		return

	commands = manifest.get("auto_run")
	if not isinstance(commands, list):
		return

	for idx, raw_cmd in enumerate(commands, start=1):
		if not isinstance(raw_cmd, str) or not raw_cmd.strip():
			continue
		cmd = raw_cmd.strip()
		code, out = _run([cmd], cwd=repo_path, shell=True)
		if code != 0:
			_log(f"auto_run command #{idx} failed for {repo_path.name}: {cmd} -> {out}")
		else:
			_log(f"auto_run command #{idx} executed for {repo_path.name}: {cmd}")
			if out:
				_log(out)


def _process_repository(repo_url: str, auto_install: bool, auto_run_installers: bool, auto_run_commands: bool) -> None:
	repo_name = _slug_from_url(repo_url)
	repo_path = REPOS_ROOT / repo_name

	if not _clone_or_update_repo(repo_url, repo_path):
		return

	manifest = _load_manifest(repo_path)

	installer_executed = _maybe_run_install_script(
		repo_path=repo_path,
		manifest=manifest,
		auto_run_installers=auto_run_installers,
	)

	if auto_install and not installer_executed:
		extension_paths = manifest.get("extension_paths")
		if isinstance(extension_paths, list) and extension_paths:
			rel_paths = [str(x).strip() for x in extension_paths if str(x).strip()]
		else:
			rel_paths = DEFAULT_EXTENSION_PATHS

		copied = _copy_extensions_tree(repo_path=repo_path, relative_paths=rel_paths)
		if copied > 0:
			_log(f"Copied {copied} extension file(s) from {repo_name}")
		else:
			_log(f"No extension files copied from {repo_name} (check extension_paths)")

	_maybe_run_auto_commands(
		repo_path=repo_path,
		manifest=manifest,
		auto_run_commands=auto_run_commands,
	)


class ExtensionRepositoryBootstrapExtension(Extension):
	_started = False
	_lock = threading.Lock()

	async def execute(self, **kwargs) -> Any:
		if getattr(self.agent, "number", 0) != 0:
			return None

		with ExtensionRepositoryBootstrapExtension._lock:
			if ExtensionRepositoryBootstrapExtension._started:
				return None
			ExtensionRepositoryBootstrapExtension._started = True

		options = _read_options()
		repositories = _parse_repositories(options.get("extension_repositories"))
		auto_install = _to_bool(options.get("extensions_auto_install"), True)
		auto_run_installers = _to_bool(options.get("extensions_auto_run_installers"), True)
		auto_run_commands = _to_bool(options.get("extensions_auto_run_commands"), False)

		if not repositories:
			_log("No extension repositories configured")
			return None

		_log(
			f"Starting extension bootstrap: repos={len(repositories)} "
			f"auto_install={auto_install} "
			f"auto_run_installers={auto_run_installers} "
			f"auto_run_commands={auto_run_commands}"
		)

		for repo_url in repositories:
			cleaned = repo_url.strip()
			if not cleaned:
				continue
			if not cleaned.startswith(("https://", "http://", "git@")):
				_log(f"Skipping invalid repository URL: {cleaned}")
				continue
			_process_repository(
				repo_url=cleaned,
				auto_install=auto_install,
				auto_run_installers=auto_run_installers,
				auto_run_commands=auto_run_commands,
			)

		_log("Extension bootstrap completed")
		return None
