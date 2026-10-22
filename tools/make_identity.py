#!/usr/bin/env python3
"""Create the self-signed identity used to sign shortcuts.

Run once; the outputs are committed under Sources/ShortSign/Resources:

  key.dat        X9.63 raw ECDSA P-256 key (04 || X || Y || d), the format
                 libshortcutsign expects
  auth.plist     binary plist with SigningCertificateChain = [leaf, root]
  ShortSign.cer  root certificate (DER) for the user to install and trust
"""

import plistlib
from datetime import datetime, timedelta, timezone
from pathlib import Path

from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.x509.oid import NameOID, ObjectIdentifier

OUT = Path(__file__).resolve().parent.parent / "Sources/ShortSign/Resources"
OUT.mkdir(parents=True, exist_ok=True)

# Apple's Shortcuts signing marker. Real signing certificates carry it;
# mirrors 0xilis/shortcut-sign's self-signed tutorial.
SHORTCUT_SIGNING_OID = ObjectIdentifier("1.2.840.113635.100.18.1")


def name(cn: str) -> x509.Name:
    return x509.Name([
        x509.NameAttribute(NameOID.COUNTRY_NAME, "US"),
        x509.NameAttribute(NameOID.ORGANIZATION_NAME, "ShortSign"),
        x509.NameAttribute(NameOID.COMMON_NAME, cn),
    ])


now = datetime.now(timezone.utc)

root_key = ec.generate_private_key(ec.SECP256R1())
root_public = root_key.public_key()
root_ski = x509.SubjectKeyIdentifier.from_public_key(root_public)
root = (
    x509.CertificateBuilder()
    .subject_name(name("ShortSign Self-Signed Root"))
    .issuer_name(name("ShortSign Self-Signed Root"))
    .public_key(root_public)
    .serial_number(x509.random_serial_number())
    .not_valid_before(now - timedelta(days=1))
    .not_valid_after(now + timedelta(days=3650))
    .add_extension(x509.BasicConstraints(ca=True, path_length=None), critical=True)
    .add_extension(
        x509.KeyUsage(
            digital_signature=True,
            content_commitment=False,
            key_encipherment=False,
            data_encipherment=False,
            key_agreement=False,
            key_cert_sign=True,
            crl_sign=True,
            encipher_only=False,
            decipher_only=False,
        ),
        critical=True,
    )
    .add_extension(root_ski, critical=False)
    .add_extension(x509.AuthorityKeyIdentifier.from_issuer_public_key(root_public), critical=False)
    .add_extension(
        x509.UnrecognizedExtension(
            SHORTCUT_SIGNING_OID, b"\x0c\x15WithLoveFromShortSign"
        ),
        critical=False,
    )
    .sign(root_key, hashes.SHA256())
)

leaf_key = ec.generate_private_key(ec.SECP256R1())
leaf_public = leaf_key.public_key()
leaf = (
    x509.CertificateBuilder()
    .subject_name(name("ShortSign Shortcut Signing"))
    .issuer_name(root.subject)
    .public_key(leaf_public)
    .serial_number(x509.random_serial_number())
    .not_valid_before(now - timedelta(days=1))
    .not_valid_after(now + timedelta(days=3650))
    .add_extension(x509.BasicConstraints(ca=False, path_length=None), critical=True)
    .add_extension(
        x509.KeyUsage(
            digital_signature=True,
            content_commitment=False,
            key_encipherment=True,
            data_encipherment=False,
            key_agreement=False,
            key_cert_sign=False,
            crl_sign=False,
            encipher_only=False,
            decipher_only=False,
        ),
        critical=True,
    )
    .add_extension(
        x509.ExtendedKeyUsage([
            x509.oid.ExtendedKeyUsageOID.SERVER_AUTH,
            x509.oid.ExtendedKeyUsageOID.CLIENT_AUTH,
        ]),
        critical=False,
    )
    .add_extension(x509.SubjectKeyIdentifier.from_public_key(leaf_public), critical=False)
    .add_extension(x509.AuthorityKeyIdentifier.from_issuer_public_key(root_public), critical=False)
    .add_extension(
        x509.UnrecognizedExtension(
            SHORTCUT_SIGNING_OID, b"\x0c\x15WithLoveFromShortSign"
        ),
        critical=False,
    )
    .sign(root_key, hashes.SHA256())
)

numbers = leaf_key.private_numbers()
pub = numbers.public_numbers
key = (
    b"\x04"
    + pub.x.to_bytes(32, "big")
    + pub.y.to_bytes(32, "big")
    + numbers.private_value.to_bytes(32, "big")
)
(OUT / "key.dat").write_bytes(key)

auth = {
    "SigningCertificateChain": [
        leaf.public_bytes(serialization.Encoding.DER),
        root.public_bytes(serialization.Encoding.DER),
    ]
}
(OUT / "auth.plist").write_bytes(plistlib.dumps(auth, fmt=plistlib.FMT_BINARY))
(OUT / "ShortSign.cer").write_bytes(root.public_bytes(serialization.Encoding.DER))

print(f"wrote {OUT}")
