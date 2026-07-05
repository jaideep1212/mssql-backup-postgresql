"""
seed_testtbl.py  -  populate dbo.TestTbl with known, verifiable test rows.

Option-1 seeding: EncField is filled with data ENCRYPTED HERE using the same
Fernet key the source app uses (ENCRYPTION_KEY_TEST). Because we start from a
KNOWN plaintext, the end-to-end test can assert the exact round-trip:

    "Hello World"  --encrypt-->  bytes in TestTbl.EncField
        --replicate-->  bytes in test_tbl.enc_field
        --decrypt-->  "Hello World"   (must match)

Also writes the expected plaintext values to expected_testtbl.json next to this
script, so the verification step can compare decrypted output against them.

Covers, across the rows, the type/edge cases that catch mapping bugs:
  - unicode text (ö, ä, å)
  - a real 64-byte hash, and tricky binary bytes (0x00, 0xFF)
  - datetime with sub-second precision
  - decimal with exact fractional digits (float-rounding trap)
  - bit 1 and 0
  - a fully-NULL row (NULL handling per type)

Run on a machine that can reach SQL Server (port open), e.g. the Pi with the
firewall open, or the laptop. Reads DB + key config from the same .env style.

    export ENCRYPTION_KEY_TEST='...'
    export MSSQL_HOST=192.168.1.99 MSSQL_PORT=1433
    export MSSQL_USER_TEST=svcreader   # or a login that can INSERT into TestTbl
    export MSSQL_PASSWORD_TEST='...'
    export MSSQL_DB_TEST=LocalTestDB
    python seed_testtbl.py
"""
from __future__ import annotations
import hashlib
import json
import os
import sys
from datetime import datetime
from decimal import Decimal
from pathlib import Path

import pyodbc
from cryptography.fernet import Fernet


def _env(name, default=None, required=False):
    v = os.environ.get(name, default)
    if required and not v:
        sys.stderr.write(f"FATAL: {name} not set\n")
        sys.exit(2)
    return v


def connstr() -> str:
    host = _env("MSSQL_HOST", required=True)
    port = _env("MSSQL_PORT", "1433")
    db = _env("MSSQL_DB_TEST", "LocalTestDB")
    user = _env("MSSQL_USER_TEST", required=True)
    pwd = _env("MSSQL_PASSWORD_TEST", required=True)
    return (
        "DRIVER={ODBC Driver 18 for SQL Server};"
        f"SERVER={host},{port};DATABASE={db};UID={user};PWD={pwd};"
        "Encrypt=no;TrustServerCertificate=yes;"
    )


def main() -> int:
    key = _env("ENCRYPTION_KEY_TEST", required=True)
    f = Fernet(key.encode() if isinstance(key, str) else key)

    # ---- Define the test rows with KNOWN plaintext for the encrypted field ----
    # (text, enc_plaintext, hash_input, date, decimal, int, bool)
    rows = [
        ("Simple ASCII",      "Hello World",              b"hash-input-1",
         datetime(2024, 3, 15, 12, 34, 56, 789000), Decimal("12345.6789"), 42, True),
        ("Unicode Bjork",     "Björk Ödegård åäö",        b"hash-input-2",
         datetime(2020, 1, 1, 0, 0, 0, 1000),       Decimal("0.0001"),      0,  False),
        ("Empty enc",         "",                          b"",
         datetime(1999, 12, 31, 23, 59, 59, 997000), Decimal("-999.9999"), -7, True),
    ]

    expected = []   # what each row's enc_field must decrypt back to

    conn = pyodbc.connect(connstr())
    cur = conn.cursor()

    # clear existing test rows for a clean seed
    cur.execute("DELETE FROM dbo.TestTbl;")

    for i, (text, enc_plain, hash_in, dt, dec, iv, bv) in enumerate(rows, start=1):
        # encrypt the known plaintext with the Fernet key -> bytes for EncField
        enc_bytes = f.encrypt(enc_plain.encode("utf-8")) if enc_plain != "" else b""
        # a real SHA-256 hash for HashField (64 hex chars = 32 bytes; use 64 bytes via sha512 to fill VARBINARY(64))
        hash_bytes = hashlib.sha512(hash_in).digest() if hash_in else b""  # 64 bytes

        cur.execute(
            """
            INSERT INTO dbo.TestTbl
                (TextField, HashField, EncField, DateField, DecimalField, IntField, BoolField)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            """,
            text, hash_bytes, enc_bytes, dt, dec, iv, bv,
        )
        expected.append({
            "row": i,
            "text_field": text,
            "enc_plaintext": enc_plain,          # what enc_field must decrypt to
            "hash_hex": hash_bytes.hex(),         # what hash_field must hex to
            "decimal": str(dec),
            "int": iv,
            "bool": bv,
        })

    # a fully-NULL row (NULL handling)
    cur.execute(
        "INSERT INTO dbo.TestTbl (TextField, HashField, EncField, DateField, DecimalField, IntField, BoolField) "
        "VALUES (NULL, NULL, NULL, NULL, NULL, NULL, NULL);"
    )
    expected.append({"row": len(rows) + 1, "text_field": None, "enc_plaintext": "",
                     "hash_hex": "", "decimal": None, "int": None, "bool": None})

    conn.commit()

    # write the expected values for the verification step
    exp_path = Path(__file__).parent / "expected_testtbl.json"
    exp_path.write_text(json.dumps(expected, indent=2, ensure_ascii=False))

    # show what got inserted
    cur.execute("SELECT ID, TextField, DATALENGTH(EncField) AS enc_len FROM dbo.TestTbl ORDER BY ID;")
    print("Seeded dbo.TestTbl:")
    for r in cur.fetchall():
        print(f"  ID={r[0]}  text={r[1]!r}  enc_bytes={r[2]}")
    print(f"\nExpected values written to {exp_path}")
    print("Next: insert an outbox row for dbo.TestTbl and trigger a cycle.")

    conn.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
