#!/bin/bash

mkdir Auto-Camera
cp *.toc Auto-Camera
cp *.lua Auto-Camera
cp -r modules Auto-Camera
cp -r libs Auto-Camera
cp *.xml Auto-Camera
zip -r Auto-Camera.zip Auto-Camera
rm -r Auto-Camera
