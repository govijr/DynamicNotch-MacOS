#!/usr/bin/env python3
"""Validate public appcasts and Storage errors; never rewrite signed XML."""
import argparse
import base64
import fnmatch
import json
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

SPARKLE = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"


def feed_items(path):
    data = Path(path).read_bytes()
    if b"<!DOCTYPE" in data.upper():
        raise ValueError("Appcasts with a DTD are not accepted")
    root = ET.fromstring(data)
    channel = root.find("channel")
    if root.tag != "rss" or channel is None:
        raise ValueError("Appcast must be an RSS feed with a channel")
    return channel.findall("item")


def item_build(item):
    value = item.findtext(SPARKLE + "version")
    if value is None:
        enclosure = item.find("enclosure")
        if enclosure is not None:
            value = enclosure.get(SPARKLE + "version")
    if value is None or not re.fullmatch(r"[1-9][0-9]*", value.strip()):
        raise ValueError("Appcast needs positive integer builds; adapt for other existing version schemes")
    return int(value)


def highest_build(path):
    return max((item_build(item) for item in feed_items(path)), default=0)


def assert_next(path, build):
    current = highest_build(path)
    if build <= current:
        raise ValueError(f"Build {build} must be greater than published build {current}")


def verify_item(path, build, url, size):
    matches = [item for item in feed_items(path) if item_build(item) == build]
    if len(matches) != 1:
        raise ValueError("Appcast must contain exactly one item for the new build")
    enclosure = matches[0].find("enclosure")
    if enclosure is None or enclosure.get("url") != url:
        raise ValueError("Appcast enclosure URL does not match the versioned ZIP")
    if enclosure.get("length") != str(size):
        raise ValueError("Appcast enclosure length does not match the ZIP")
    signature = enclosure.get(SPARKLE + "edSignature", "")
    try:
        decoded = base64.b64decode(signature, validate=True)
    except ValueError as exc:
        raise ValueError("Invalid EdDSA signature encoding") from exc
    if len(decoded) != 64:
        raise ValueError("Appcast enclosure is missing an EdDSA signature")
    return signature


def check_bucket(path, name, zip_size, dmg_size, feed_size):
    bucket = json.loads(Path(path).read_text())
    if not isinstance(bucket, dict) or bucket.get("id") != name or bucket.get("public") is not True:
        raise ValueError("The configured bucket must exist and be publicly readable")
    limit = bucket.get("file_size_limit")
    allowed = bucket.get("allowed_mime_types")
    artifacts = (("ZIP", zip_size, "application/zip"),
                 ("DMG", dmg_size, "application/x-apple-diskimage"),
                 ("appcast", feed_size, "application/xml"))
    for label, size, mime in artifacts:
        if limit is not None and size > int(limit):
            raise ValueError(f"{label} exceeds the bucket file size limit")
        if allowed is not None and not any(fnmatch.fnmatchcase(mime, pattern) for pattern in allowed):
            raise ValueError(f"The bucket does not allow {mime}")


def missing_object(path):
    payload = json.loads(Path(path).read_text())
    if not isinstance(payload, dict):
        raise ValueError("Storage error response must be a JSON object")
    return str(payload.get("statusCode")) == "404" and payload.get("code") == "NoSuchKey"


def storage_key_type():
    key = sys.stdin.read()
    if not key or any(character.isspace() for character in key):
        raise ValueError("Provide SUPABASE_STORAGE_KEY without whitespace")
    if re.fullmatch(r"sb_secret_[A-Za-z0-9_-]+", key):
        return "secret"
    parts = key.split(".")
    if len(parts) != 3:
        raise ValueError("Publishing requires a Supabase secret key or legacy service_role JWT")
    try:
        payload = json.loads(base64.urlsafe_b64decode(parts[1] + "=" * (-len(parts[1]) % 4)))
    except (ValueError, UnicodeDecodeError) as exc:
        raise ValueError("Publishing key is not a valid legacy JWT payload") from exc
    if not isinstance(payload, dict) or payload.get("role") != "service_role":
        raise ValueError("A publishable/anon/user key cannot be used for release publishing")
    return "legacy"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    for name in ("max-build", "missing-object"):
        commands.add_parser(name).add_argument("path")
    check = commands.add_parser("assert-next")
    check.add_argument("path")
    check.add_argument("build", type=int)
    verify = commands.add_parser("verify")
    verify.add_argument("path")
    verify.add_argument("build", type=int)
    verify.add_argument("url")
    verify.add_argument("size", type=int)
    verify.add_argument("--print-signature", action="store_true")
    bucket = commands.add_parser("bucket-check")
    bucket.add_argument("path")
    bucket.add_argument("name")
    bucket.add_argument("zip_size", type=int)
    bucket.add_argument("dmg_size", type=int)
    bucket.add_argument("feed_size", type=int)
    commands.add_parser("key-type")
    args = parser.parse_args()
    if hasattr(args, "build") and args.build <= 0:
        raise ValueError("Build must be positive")
    if args.command == "max-build":
        print(highest_build(args.path))
    elif args.command == "assert-next":
        assert_next(args.path, args.build)
    elif args.command == "verify":
        signature = verify_item(args.path, args.build, args.url, args.size)
        if args.print_signature:
            print(signature)
    elif args.command == "bucket-check":
        check_bucket(args.path, args.name, args.zip_size, args.dmg_size, args.feed_size)
    elif args.command == "missing-object":
        return 0 if missing_object(args.path) else 1
    else:
        print(storage_key_type())
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (ValueError, OSError, ET.ParseError) as error:
        print(f"error: {error}", file=sys.stderr)
        sys.exit(2)
