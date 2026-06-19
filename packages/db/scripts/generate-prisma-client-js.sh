#!/bin/sh
set -eu

root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
schema_dir="$root/prisma/schema"
tmp_dir="$(mktemp -d "$root/.prisma-clientjs-XXXXXX")"
config_file="$root/prisma.config.ts"
config_backup="$root/prisma.config.ts.clientjs-bak"

cleanup() {
  rm -rf "$tmp_dir"
  if [ -f "$config_backup" ]; then
    mv "$config_backup" "$config_file"
  fi
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

if [ -f "$config_file" ]; then
  mv "$config_file" "$config_backup"
fi

cat > "$config_file" <<'EOF'
export default {
  datasource: {
    url: process.env.DATABASE_URL!,
  },
};
EOF

cd "$root"
bunx prisma generate --schema="$tmp_dir"
