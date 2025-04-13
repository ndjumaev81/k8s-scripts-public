#!/bin/bash

# Check GitHub username argument
if [ $# -ne 1 ]; then
    echo "Usage: $0 <github-username>"
    exit 1
fi

GITHUB_USERNAME="$1"
