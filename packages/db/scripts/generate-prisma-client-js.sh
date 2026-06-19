#!/bin/sh
set -eu

root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
schema_dir="$root/prisma/schema"
tmp_dir="$(mktemp -d "$root/.prisma-clientjs-XXXXXX")"

cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

find "$schema_dir" -name '*.prisma' ! -name 'schema.prisma' -exec cp {} "$tmp_dir"/ \;

cat > "$tmp_dir/schema.prisma" <<'EOF'
generator client {
  provider        = "prisma-client-js"
  previewFeatures = ["postgresqlExtensions"]
}

datasource db {
  provider   = "postgresql"
  extensions = [pgcrypto]
}
EOF

cd "$root"
bunx prisma generate --schema="$tmp_dir"
