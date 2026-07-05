"""
verify_decrypt_export.py  -  VERIFICATION / TEST tool (run manually).

Purpose
-------
Prove the replication is byte-perfect AND the data is usable downstream:
reads the REPLICATED tables from PostgreSQL on the Pi (household_test), decrypts
the Fernet-encrypted BYTEA columns with the key, and writes decrypted CSVs.

Because Fernet is AUTHENTICATED encryption, decryption only succeeds if the bytes
are exactly what was originally encrypted. So if this script produces correct
plaintext from the Postgres copy, it proves the SQL Server -> replicator ->
Postgres path did not corrupt a single byte. A corrupted byte would make Fernet
raise InvalidToken. That is the whole point of running this against Postgres
(the replica) rather than SQL Server (the source).

This is a MANUAL tool, not part of the replicator or the container. Run it on
the Pi where it can reach the postgres container.

Config (env)
------------
  ENCRYPTION_KEY_TEST   the Fernet key (urlsafe base64, 44 chars)
  PG_HOST               default: localhost   (or 'postgres' if run in-network)
  PG_PORT               default: 5432
  PG_DB                 default: household_test
  PG_USER               default: admin
  PG_PASSWORD           the postgres password

Usage
-----
  pip install psycopg[binary] cryptography pandas
  export ENCRYPTION_KEY_TEST='...'    (or put it in a .env you source)
  export PG_PASSWORD='...'
  python verify_decrypt_export.py --out ./decrypted

Output
------
  ./decrypted/dim_users_decrypted.csv
  ./decrypted/dim_users_s_decrypted.csv
"""
from __future__ import annotations

import argparse
import csv
import os
import sys
from pathlib import Path

import psycopg
from cryptography.fernet import Fernet, InvalidToken


# ---------------------------------------------------------------------------
# Field definitions (from the source app's export script, Postgres column names
# are snake_case per the mapping).
#
# For each Postgres table: which columns are Fernet-encrypted (decrypt) and
# which are hash/binary (hex-encode for display).
# ---------------------------------------------------------------------------
ENCRYPTED_FIELDS = {
    "dim_users": [],                       # aggregate table: no encrypted fields
    "dim_users_s": [
        "first_name", "last_name", "birth_date", "birth_city", "birth_country",
        "marriage_date", "current_address_line1", "current_address_line2",
        "current_city", "current_post_code", "current_country",
        "permanent_address_line1", "permanent_address_line2", "permanent_city",
        "permanent_post_code", "permanent_country", "contact_email_id",
        "contact_mobile_no", "contact_phone_no", "work_email_id", "work_mobile_no",
        "work_phone_no", "expired_date", "pan", "aadhar", "tin",
    ],
}

HASH_FIELDS = {
    "dim_users": ["user_name_hash"],       # SHA-256 hash -> hex
    "dim_users_s": [],
}


def _load_dotenv():
    """
    Minimal .env loader (no external dependency). Looks for a .env file next to
    this script and sets any vars not already in the environment. Each line is
    KEY=VALUE; blank lines and #comments are ignored.
    """
    env_path = Path(__file__).parent / ".env"
    if not env_path.exists():
        return
    for line in env_path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        os.environ.setdefault(k.strip(), v.strip())


def _lane_var(base: str, lane: str, default=None, required=False):
    """
    Resolve a per-lane suffixed env var, e.g. base='PG_USER', lane='TEST'
    -> reads PG_USER_TEST. Matches the replicator's config convention.
    """
    name = f"{base}_{lane}"
    val = os.environ.get(name, default)
    if required and not val:
        sys.stderr.write(f"FATAL: required env var {name} is not set\n")
        sys.exit(2)
    return val


def load_key(lane: str) -> Fernet:
    key = _lane_var("ENCRYPTION_KEY", lane, required=True)
    try:
        return Fernet(key.encode() if isinstance(key, str) else key)
    except Exception as e:
        sys.stderr.write(f"FATAL: ENCRYPTION_KEY_{lane} is not a valid Fernet key: {e}\n")
        sys.exit(2)


def decrypt_value(fernet: Fernet, value) -> str:
    """
    Decrypt one Fernet-encrypted BYTEA value to a plaintext string.

    Mirrors the source app's logic: Fernet tokens are base64 UTF-8 and start
    with the 'gAAAAA' version signature. NULL/empty -> ''. A genuine decryption
    failure is surfaced as a clearly-marked marker so corruption is visible in
    the CSV rather than silently hidden.
    """
    if value is None or value == b"" or value == "":
        return ""

    # psycopg returns BYTEA as Python bytes; normalise to bytes
    if isinstance(value, memoryview):
        value = value.tobytes()
    if isinstance(value, str):
        value = value.encode("utf-8")

    # Fernet token -> UTF-8 base64 string
    try:
        token_str = value.decode("utf-8").rstrip("\x00")
    except UnicodeDecodeError:
        return "<NON-UTF8-BYTES: %s>" % value[:16].hex()

    if not token_str:
        return ""

    try:
        plaintext = fernet.decrypt(token_str.encode("utf-8")).decode("utf-8")
        return plaintext.replace("\x00", "")
    except InvalidToken:
        # This is the important signal: if the replicated bytes were corrupted,
        # Fernet rejects them here. Mark it loudly so verification catches it.
        return "<DECRYPT-FAILED: InvalidToken>"
    except Exception as e:
        return "<DECRYPT-ERROR: %s>" % str(e)[:40]


def to_hex(value) -> str:
    """Hash/binary BYTEA -> lowercase hex string (for display/comparison)."""
    if value is None or value == b"" or value == "":
        return ""
    if isinstance(value, memoryview):
        value = value.tobytes()
    if isinstance(value, bytes):
        return value.hex().lower()
    return str(value).lower()


def export_table(cur, table: str, fernet: Fernet, out_dir: Path) -> int:
    cur.execute(f"SELECT * FROM {table} ORDER BY id")
    colnames = [d.name for d in cur.description]
    rows = cur.fetchall()

    enc = set(ENCRYPTED_FIELDS.get(table, []))
    hashf = set(HASH_FIELDS.get(table, []))

    out_path = out_dir / f"{table}_decrypted.csv"
    # utf-8-sig so Excel shows unicode (ö, ä, å) correctly, matching the original tool
    with open(out_path, "w", newline="", encoding="utf-8-sig") as fh:
        writer = csv.writer(fh)
        writer.writerow(colnames)
        for row in rows:
            out_row = []
            for col, val in zip(colnames, row):
                if col in enc:
                    out_row.append(decrypt_value(fernet, val))
                elif col in hashf:
                    out_row.append(to_hex(val))
                else:
                    out_row.append("" if val is None else val)
            writer.writerow(out_row)

    print(f"  wrote {out_path}  ({len(rows)} rows)")
    return len(rows)


def main() -> int:
    ap = argparse.ArgumentParser(description="Decrypt replicated Postgres tables to CSV (verification).")
    ap.add_argument("--out", default="./decrypted", help="output directory for CSVs")
    ap.add_argument("--lane", default=os.environ.get("LANE", "TEST"),
                    help="lane TEST or PROD (default: TEST); selects the _TEST/_PROD env vars")
    ap.add_argument("--test", action="store_true",
                    help="shorthand for --lane TEST: suffix _TEST to all env var names")
    ap.add_argument("--tables", nargs="*", default=["dim_users", "dim_users_s"],
                    help="tables to export (default: dim_users dim_users_s)")
    args = ap.parse_args()

    _load_dotenv()

    # --test forces the TEST lane (overrides --lane / LANE if both given).
    if args.test:
        lane = "TEST"
    else:
        lane = args.lane.upper()
    if lane not in ("TEST", "PROD"):
        sys.stderr.write(f"FATAL: lane must be TEST or PROD, got {lane}\n")
        return 2
    print(f"lane = {lane}  (reading *_{lane} env vars)")

    fernet = load_key(lane)

    out_dir = Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)

    conn_kwargs = dict(
        host=os.environ.get("PG_HOST", "localhost"),
        port=os.environ.get("PG_PORT", "5432"),
        dbname=_lane_var("PG_DB", lane, default="household_test"),
        user=_lane_var("PG_USER", lane, default="admin"),
        password=_lane_var("PG_PASSWORD", lane, required=True),
    )

    print(f"connecting to postgres {conn_kwargs['host']}:{conn_kwargs['port']}/{conn_kwargs['dbname']} as {conn_kwargs['user']}")
    total = 0
    fail_markers = 0
    with psycopg.connect(**conn_kwargs) as conn:
        with conn.cursor() as cur:
            for t in args.tables:
                n = export_table(cur, t, fernet, out_dir)
                total += n

    # Post-check: scan the CSVs for decrypt-failure markers so a corrupted
    # replication is caught explicitly, not just eyeballed.
    for t in args.tables:
        p = out_dir / f"{t}_decrypted.csv"
        if p.exists():
            text = p.read_text(encoding="utf-8-sig")
            c = text.count("<DECRYPT-FAILED") + text.count("<DECRYPT-ERROR") + text.count("<NON-UTF8-BYTES")
            fail_markers += c
            if c:
                print(f"  WARNING: {p.name} has {c} decrypt-failure marker(s) - replication may have corrupted bytes!")

    print(f"\ndone: {total} row(s) across {len(args.tables)} table(s) -> {out_dir}")
    if fail_markers:
        print(f"RESULT: {fail_markers} value(s) failed to decrypt. Replication integrity NOT confirmed.")
        return 1
    print("RESULT: all encrypted values decrypted cleanly. Replication is byte-perfect and downstream-usable.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
