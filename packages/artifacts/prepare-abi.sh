#!/usr/bin/env bash

set -e  # Exit on error

# Define directories
CONTRACTS_FOLDER="../contracts"
JSON_ABI_FOLDER="./src/abi"
TARGET_ABI_FILE="./src/abi.ts"

# Move into contracts package and install dependencies
cd $CONTRACTS_FOLDER

yarn install && yarn build

# Move back to artifacts package
cd - > /dev/null

# Ensure the output directory exists
rm -Rf $JSON_ABI_FOLDER
mkdir -p $JSON_ABI_FOLDER

# Extract the abi field into new JSON files
for SRC_CONTRACT in $(ls $CONTRACTS_FOLDER/src/*.sol )
do
    FILE=$(basename $(echo $SRC_CONTRACT))
    cat $CONTRACTS_FOLDER/artifacts/src/$FILE/${FILE%".sol"}.json | jq ".abi" > $JSON_ABI_FOLDER/${FILE%".sol"}.json
done

# Write the main ABI file
rm -f $TARGET_ABI_FILE
for ABI_FILE in $(ls $JSON_ABI_FOLDER)
do
    CONTRACT_NAME=${ABI_FILE%".json"}
    echo "Importing $CONTRACT_NAME from $TARGET_ABI_FILE"

    echo "import * as ${CONTRACT_NAME}ABI from \"./abi/$ABI_FILE\";" >> $TARGET_ABI_FILE
    echo "export {${CONTRACT_NAME}ABI}" >> $TARGET_ABI_FILE
    echo "" >> $TARGET_ABI_FILE
done

echo "ABI prepared: $JSON_ABI_FOLDER"
