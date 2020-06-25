#!/bin/bash

SHA=$(git rev-parse --short HEAD)

docker build -t pullbot:$SHA .
docker tag pullbot:$SHA pullbot:latest

