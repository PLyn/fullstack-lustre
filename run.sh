#!/bin/bash

# Exit on error
set -e

# Store the root directory
ROOT_DIR="$(pwd)"

echo "Cleaning static directory..."
rm -rf "$ROOT_DIR/server/priv/static"/*

echo "Building client..."
cd "$ROOT_DIR/client"
gleam run -m lustre/dev build --outdir=../server/priv/static

echo "Starting server..."
cd "$ROOT_DIR/server"
gleam run
