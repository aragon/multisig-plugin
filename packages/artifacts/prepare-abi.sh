#!/usr/bin/env bash

# Exit on error
set -e

# Constants
CONTRACTS_FOLDER="../contracts"
TARGET_ABI_FILE="./src/abi.ts"

# Move into contracts package and install dependencies
cd $CONTRACTS_FOLDER

yarn install && yarn build

# Move back to artifacts package
cd - > /dev/null

# Wipe the destination file
echo > $TARGET_ABI_FILE

# Extract the abi field and create a TS file
for SRC_CONTRACT_FILE in $(ls $CONTRACTS_FOLDER/src/*.sol )
do
    SRC_FILE_NAME=$(basename $(echo $SRC_CONTRACT_FILE))
    SRC_FILE_PATH=$CONTRACTS_FOLDER/artifacts/src/$SRC_FILE_NAME/${SRC_FILE_NAME%".sol"}.json
    
    ABI=$(node -e "console.log(JSON.stringify(JSON.parse(fs.readFileSync(\"$SRC_FILE_PATH\").toString()).abi))")
    CONTRACT_NAME=${SRC_FILE_NAME%".sol"}

    echo "const ${CONTRACT_NAME}ABI = $ABI as const;" >> $TARGET_ABI_FILE
    echo "export {${CONTRACT_NAME}ABI};" >> $TARGET_ABI_FILE
    echo "" >> $TARGET_ABI_FILE
done

echo "ABI prepared: $TARGET_ABI_FILE"
