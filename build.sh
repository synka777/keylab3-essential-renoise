#!/bin/bash
# build.sh — Génére le XRNX avec versionnement

PLUGIN_ID=$(grep -oP '(?<=<Id>)[^<]+' manifest.xml)
VERSION=$(grep -oP '(?<=<Version>)[^<]+' manifest.xml)

echo "Packaging : ${PLUGIN_ID} v${VERSION}"
zip -qr "${PLUGIN_ID}_v${VERSION}.xrnx" . \
  -x "*.git*" ".git/*" ".DS_Store*" "__pycache__*" "*.pyc" "*~" ".github/*"

ls -lh "${PLUGIN_ID}_v${VERSION}.xrnx"