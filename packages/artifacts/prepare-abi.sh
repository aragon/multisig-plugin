#!/usr/bin/env bash

set -e  # Exit on error

# Define directories
CONTRACTS_FOLDER="../contracts"
SOURCE_ABI_FILE="$CONTRACTS_FOLDER/artifacts/abi.ts"
TARGET_ABI_FOLDER="./src"

# Move into contracts package and install dependencies
cd $CONTRACTS_FOLDER

yarn install

yarn build

yarn prepare-abi

if [ ! -f "$SOURCE_ABI_FILE" ]; then
    echo "Error: $SOURCE_ABI_FILE not found."
    exit 1
fi

# Move back to artifacts package
cd -

# Ensure the output directory exists
mkdir -p "$TARGET_ABI_FOLDER"

# Copy the generated ABIs to the output directory
cp "$SOURCE_ABI_FILE" "$TARGET_ABI_FOLDER/abi.ts"

echo "ABI prepared: $TARGET_ABI_FOLDER/abi.ts"
