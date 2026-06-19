#!/usr/bin/env node
/**
 * Generates a prisma-client-js client to populate @prisma/client at node_modules.
 * Creates a temp schema dir, copies model files, generates with prisma-client-js.
 */
const { spawnSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const root = path.join(__dirname, '..');
const schemaDir = path.join(root, 'prisma/schema');
const tempDir = fs.mkdtempSync(path.join(root, '.prisma-clientjs-'));

try {
  // Copy model files
  for (const file of fs.readdirSync(schemaDir).filter(f => f.endsWith('.prisma') && f !== 'schema.prisma')) {
    fs.copyFileSync(path.join(schemaDir, file), path.join(tempDir, file));
  }

  // Write prisma-client-js generator schema
  fs.writeFileSync(path.join(tempDir, 'schema.prisma'), `generator client {
  provider        = "prisma-client-js"
  previewFeatures = ["postgresqlExtensions"]
}

datasource db {
  provider   = "postgresql"
  extensions = [pgcrypto]
}
`);

  const result = spawnSync('sh', ['-lc', `bunx prisma generate --schema="${tempDir}"`], {
    cwd: root,
    encoding: 'utf8',
    env: process.env,
  });

  if (result.stdout) process.stdout.write(result.stdout);
  if (result.stderr) process.stderr.write(result.stderr);
  if (result.status !== 0) {
    throw new Error(`Prisma generate exited with status ${result.status ?? 'unknown'}`);
  }
} finally {
  fs.rmSync(tempDir, { recursive: true, force: true });
}
