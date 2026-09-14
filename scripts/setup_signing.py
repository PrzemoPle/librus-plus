#!/usr/bin/env python3
"""
Jednorazowa konfiguracja podpisywania pod TestFlight — uruchamiasz TY, na swoim Macu.

Co robi (przez App Store Connect API, Twoim kluczem):
  1. generuje klucz prywatny + CSR i zakłada certyfikat „Apple Distribution”,
  2. rejestruje App ID (bundle id), jeśli go nie ma,
  3. zakłada profil provisioning typu App Store,
  4. wgrywa sekrety do repo na GitHubie (gh secret set) — klucz API, certyfikat .p12
     z hasłem, profil,
  5. sprawdza, czy w App Store Connect istnieje już rekord aplikacji (tego API
     nie potrafi założyć — jeśli brak, wypisze instrukcję).

Nic nie jest wypisywane na ekran poza statusem. Klucz i .p12 zostają lokalnie w
~/Library/Application Support/dzienniczek-signing/ (żeby ponowne uruchomienie
użyło tego samego certyfikatu zamiast zakładać kolejny — Apple pozwala na kilka).

Wymagania: macOS z `openssl` i zalogowanym `gh` (GitHub CLI). Python 3.9+.
Klucz API musi mieć rolę **Admin** — zakładanie certyfikatów i profili tego wymaga
(HTTP 403 przy pierwszym zapytaniu = za słaba rola).

Użycie:
  python3 scripts/setup_signing.py \\
      --key ~/Downloads/AuthKey_ABC123DEFG.p8 \\
      --key-id ABC123DEFG \\
      --issuer-id 12345678-1234-1234-1234-123456789012

Opcjonalnie: --bundle-id, --team-id, --repo, --profile-name (domyślne poniżej).
"""
from __future__ import annotations

import argparse
import base64
import json
import os
import secrets
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

API = "https://api.appstoreconnect.apple.com"
DEFAULT_BUNDLE_ID = "pl.plewinscy.dzienniczek"
DEFAULT_TEAM_ID = "94MSU24AZ7"
DEFAULT_REPO = "PrzemoPle/librus-plus"
DEFAULT_PROFILE_NAME = "Dzienniczek App Store"
STATE_DIR = Path.home() / "Library" / "Application Support" / "dzienniczek-signing"


# ---------------------------------------------------------------- helpers

def die(message: str) -> None:
    print(f"\nBŁĄD: {message}", file=sys.stderr)
    sys.exit(1)


def step(message: str) -> None:
    print(f"→ {message}")


def run(cmd: list[str], **kwargs) -> subprocess.CompletedProcess:
    result = subprocess.run(cmd, capture_output=True, text=kwargs.pop("text", True), **kwargs)
    if result.returncode != 0:
        die(f"polecenie {' '.join(cmd[:2])} nie powiodło się:\n{result.stderr}")
    return result


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def der_to_raw_signature(der: bytes) -> bytes:
    """ECDSA DER (SEQUENCE of two INTEGERs) → 64-byte r||s, as JWT ES256 wants."""
    if der[0] != 0x30:
        die("nieoczekiwany format podpisu ECDSA")
    index = 2
    parts = []
    for _ in range(2):
        if der[index] != 0x02:
            die("nieoczekiwany format podpisu ECDSA (INTEGER)")
        length = der[index + 1]
        value = der[index + 2 : index + 2 + length].lstrip(b"\x00")
        parts.append(value.rjust(32, b"\x00"))
        index += 2 + length
    return b"".join(parts)


class AppStoreConnect:
    def __init__(self, key_path: Path, key_id: str, issuer_id: str):
        self.key_path = key_path
        self.key_id = key_id
        self.issuer_id = issuer_id
        self._token = ""
        self._token_expiry = 0.0

    def token(self) -> str:
        now = int(time.time())
        if self._token and now < self._token_expiry - 60:
            return self._token
        header = {"alg": "ES256", "kid": self.key_id, "typ": "JWT"}
        payload = {"iss": self.issuer_id, "iat": now, "exp": now + 15 * 60, "aud": "appstoreconnect-v1"}
        signing_input = b64url(json.dumps(header, separators=(",", ":")).encode()) + "." + \
            b64url(json.dumps(payload, separators=(",", ":")).encode())
        signed = subprocess.run(
            ["openssl", "dgst", "-sha256", "-sign", str(self.key_path)],
            input=signing_input.encode(), capture_output=True,
        )
        if signed.returncode != 0:
            die(f"openssl nie podpisał tokenu — czy to na pewno plik .p8 z App Store Connect?\n{signed.stderr.decode()}")
        self._token = signing_input + "." + b64url(der_to_raw_signature(signed.stdout))
        self._token_expiry = now + 15 * 60
        return self._token

    def request(self, method: str, path: str, body: dict | None = None,
                allow_404: bool = False) -> dict:
        """One API call. Dies with a readable message on any HTTP error, except a
        404 when `allow_404` is set — then returns an empty dict."""
        data = json.dumps(body).encode() if body is not None else None
        req = urllib.request.Request(API + path, data=data, method=method)
        req.add_header("Authorization", f"Bearer {self.token()}")
        req.add_header("Accept", "application/json")
        if data is not None:
            req.add_header("Content-Type", "application/json")
        try:
            with urllib.request.urlopen(req, timeout=60) as resp:
                raw = resp.read()
                return json.loads(raw) if raw else {}
        except urllib.error.HTTPError as exc:
            if exc.code == 404 and allow_404:
                return {}
            detail = exc.read().decode(errors="replace")
            try:
                errors = json.loads(detail).get("errors", [])
                detail = "; ".join(f"{e.get('title')}: {e.get('detail')}" for e in errors) or detail
            except json.JSONDecodeError:
                pass
            die(f"App Store Connect API {method} {path} → HTTP {exc.code}: {detail}")


# ---------------------------------------------------------------- steps

def ensure_tools() -> None:
    for tool in ("openssl", "gh", "security"):
        if shutil.which(tool) is None:
            die(f"brak narzędzia `{tool}` w PATH")
    auth = subprocess.run(["gh", "auth", "status"], capture_output=True, text=True)
    if auth.returncode != 0:
        die("GitHub CLI nie jest zalogowane — uruchom najpierw: gh auth login")


def ensure_private_key(state: Path) -> Path:
    key = state / "distribution.key"
    if key.exists():
        step("klucz prywatny certyfikatu już istnieje — używam go")
        return key
    step("generuję klucz prywatny certyfikatu (RSA 2048)")
    run(["openssl", "genrsa", "-out", str(key), "2048"])
    os.chmod(key, 0o600)
    return key


def ensure_certificate(asc: AppStoreConnect, state: Path, key: Path) -> tuple[str, Path]:
    """Returns (certificate id, path to DER .cer). Reuses a certificate created by an
    earlier run (its serial is remembered next to the key)."""
    cer = state / "distribution.cer"
    meta = state / "certificate.json"
    if cer.exists() and meta.exists():
        cert_id = json.loads(meta.read_text())["id"]
        existing = asc.request("GET", f"/v1/certificates/{cert_id}", allow_404=True)
        if existing.get("data"):
            step(f"certyfikat Apple Distribution już istnieje (id {cert_id}) — używam go")
            return cert_id, cer
        step("zapamiętany certyfikat zniknął z konta Apple — zakładam nowy")

    step("tworzę CSR i zakładam certyfikat „Apple Distribution”")
    csr = state / "distribution.csr"
    run(["openssl", "req", "-new", "-key", str(key), "-out", str(csr),
         "-subj", "/CN=Dzienniczek TestFlight/O=Przemyslaw Plewinski/C=PL"])
    csr_pem = csr.read_text()
    created = asc.request("POST", "/v1/certificates", {
        "data": {"type": "certificates",
                 "attributes": {"certificateType": "DISTRIBUTION", "csrContent": csr_pem}}
    })
    cert_id = created["data"]["id"]
    cer.write_bytes(base64.b64decode(created["data"]["attributes"]["certificateContent"]))
    meta.write_text(json.dumps({"id": cert_id, "created": time.strftime("%Y-%m-%d")}))
    # A .p12 from an earlier run would still hold the previous certificate.
    for stale in ("distribution.p12", "distribution.pem", "p12-password.txt"):
        (state / stale).unlink(missing_ok=True)
    step(f"certyfikat założony (id {cert_id})")
    return cert_id, cer


def build_p12(state: Path, key: Path, cer: Path) -> tuple[Path, str]:
    p12 = state / "distribution.p12"
    password_file = state / "p12-password.txt"
    if p12.exists() and password_file.exists():
        return p12, password_file.read_text().strip()
    step("pakuję certyfikat i klucz do .p12")
    pem = state / "distribution.pem"
    run(["openssl", "x509", "-inform", "DER", "-in", str(cer), "-out", str(pem)])
    password = secrets.token_urlsafe(24)
    # Password goes through the environment so it never shows up in `ps`.
    env = {**os.environ, "P12_PASSWORD": password}
    # OpenSSL 3 needs -legacy for the classic PKCS#12 ciphers; macOS's own LibreSSL
    # has no such flag and already emits them, so fall back without it.
    result = subprocess.run(
        ["openssl", "pkcs12", "-export", "-legacy", "-inkey", str(key), "-in", str(pem),
         "-out", str(p12), "-passout", "env:P12_PASSWORD"], capture_output=True, text=True, env=env)
    if result.returncode != 0:
        run(["openssl", "pkcs12", "-export", "-inkey", str(key), "-in", str(pem),
             "-out", str(p12), "-passout", "env:P12_PASSWORD"], env=env)
    password_file.write_text(password)
    os.chmod(p12, 0o600)
    os.chmod(password_file, 0o600)
    return p12, password


def ensure_bundle_id(asc: AppStoreConnect, bundle_id: str) -> str:
    listed = asc.request("GET", f"/v1/bundleIds?filter[identifier]={bundle_id}&limit=200")
    for item in listed.get("data", []):
        if item["attributes"]["identifier"] == bundle_id:
            step(f"App ID {bundle_id} już zarejestrowany")
            return item["id"]
    step(f"rejestruję App ID {bundle_id}")
    created = asc.request("POST", "/v1/bundleIds", {
        "data": {"type": "bundleIds",
                 "attributes": {"identifier": bundle_id, "name": "Dzienniczek", "platform": "IOS"}}
    })
    return created["data"]["id"]


def ensure_profile(asc: AppStoreConnect, state: Path, name: str, bundle_id_res: str, cert_id: str) -> Path:
    """Always (re)creates the App Store profile so it is guaranteed to include the
    certificate we just secured. Old profiles with the same name are removed."""
    listed = asc.request("GET", f"/v1/profiles?filter[name]={urllib.parse.quote(name)}&limit=200")
    for item in listed.get("data", []):
        if item["attributes"]["name"] == name:
            step(f"usuwam poprzedni profil „{name}”")
            asc.request("DELETE", f"/v1/profiles/{item['id']}")
    step(f"zakładam profil App Store „{name}”")
    created = asc.request("POST", "/v1/profiles", {
        "data": {
            "type": "profiles",
            "attributes": {"name": name, "profileType": "IOS_APP_STORE"},
            "relationships": {
                "bundleId": {"data": {"type": "bundleIds", "id": bundle_id_res}},
                "certificates": {"data": [{"type": "certificates", "id": cert_id}]},
            },
        }
    })
    profile = state / "appstore.mobileprovision"
    profile.write_bytes(base64.b64decode(created["data"]["attributes"]["profileContent"]))
    return profile


def set_secret(repo: str, name: str, value: str) -> None:
    result = subprocess.run(["gh", "secret", "set", name, "--repo", repo], input=value,
                            capture_output=True, text=True)
    if result.returncode != 0:
        die(f"gh secret set {name} nie powiodło się:\n{result.stderr}")


def upload_secrets(repo: str, key_path: Path, key_id: str, issuer_id: str,
                   p12: Path, p12_password: str, profile: Path) -> None:
    step(f"wgrywam sekrety do {repo}")
    set_secret(repo, "ASC_KEY_ID", key_id)
    set_secret(repo, "ASC_ISSUER_ID", issuer_id)
    set_secret(repo, "ASC_PRIVATE_KEY", key_path.read_text())
    set_secret(repo, "DIST_CERT_P12", base64.b64encode(p12.read_bytes()).decode())
    set_secret(repo, "DIST_CERT_PASSWORD", p12_password)
    set_secret(repo, "DIST_PROFILE", base64.b64encode(profile.read_bytes()).decode())


def check_app_record(asc: AppStoreConnect, bundle_id: str) -> bool:
    apps = asc.request("GET", f"/v1/apps?filter[bundleId]={bundle_id}")
    return any(a["attributes"].get("bundleId") == bundle_id for a in apps.get("data", []))


# ---------------------------------------------------------------- main

def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--key", required=True, help="plik AuthKey_XXXX.p8 z App Store Connect")
    parser.add_argument("--key-id", required=True)
    parser.add_argument("--issuer-id", required=True)
    parser.add_argument("--bundle-id", default=DEFAULT_BUNDLE_ID)
    parser.add_argument("--team-id", default=DEFAULT_TEAM_ID)
    parser.add_argument("--repo", default=DEFAULT_REPO)
    parser.add_argument("--profile-name", default=DEFAULT_PROFILE_NAME)
    args = parser.parse_args()

    key_path = Path(args.key).expanduser()
    if not key_path.exists():
        die(f"nie znaleziono pliku klucza: {key_path}")

    ensure_tools()
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    os.chmod(STATE_DIR, 0o700)

    asc = AppStoreConnect(key_path, args.key_id, args.issuer_id)
    asc.request("GET", "/v1/users?limit=1")  # fail fast on a bad key
    step("klucz API działa")

    private_key = ensure_private_key(STATE_DIR)
    cert_id, cer = ensure_certificate(asc, STATE_DIR, private_key)
    p12, p12_password = build_p12(STATE_DIR, private_key, cer)
    bundle_res = ensure_bundle_id(asc, args.bundle_id)
    profile = ensure_profile(asc, STATE_DIR, args.profile_name, bundle_res, cert_id)
    upload_secrets(args.repo, key_path, args.key_id, args.issuer_id, p12, p12_password, profile)

    print("\nGotowe. Sekrety są w repo, certyfikat i profil na koncie Apple.")
    if check_app_record(asc, args.bundle_id):
        print(f"Rekord aplikacji dla {args.bundle_id} istnieje w App Store Connect.")
    else:
        print(f"""
JESZCZE JEDNO (ręcznie, API tego nie potrafi): załóż rekord aplikacji.
  1. https://appstoreconnect.apple.com → Moje aplikacje → „+” → Nowa aplikacja
  2. Platforma: iOS · Nazwa: dowolna, unikalna w App Store (np. „Dzienniczek Plewińskich”)
     · Język: polski · Bundle ID: {args.bundle_id} · SKU: dzienniczek
  3. Zapisz. Nic więcej nie wypełniaj — do TestFlight to wystarczy.
Potem: git tag v1.0.0 && git push origin v1.0.0 — workflow „testflight” zbuduje i wyśle build.""")


if __name__ == "__main__":
    main()
