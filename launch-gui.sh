#!/bin/sh
set -e
cd "$(dirname "$0")"

if [ ! -d "NoSpeaker.app" ]; then
    echo "NoSpeaker.app not found. Building it now..."
    ./build-app.sh
fi

echo "Launching NoSpeaker.app..."
open NoSpeaker.app
