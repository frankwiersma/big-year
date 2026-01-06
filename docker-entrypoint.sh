#!/bin/sh
set -e

echo "Running Prisma migrations..."
node ./node_modules/prisma/build/index.js db push --skip-generate

echo "Starting application..."
exec node server.js
