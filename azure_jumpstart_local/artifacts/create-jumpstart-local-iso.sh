#!/bin/bash

echo "hello from create-jumpstart-local-iso.sh"

echo "Parameter 1: $1"
echo "Parameter 2: $2"

if ! type "$xorriso" > /dev/null; then
    # install foobar here
    echo "xorriso not found. Installing."
    # sudo apt -y install xorriso
fi
