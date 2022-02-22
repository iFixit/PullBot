#!/bin/bash
docker run \
   --detach \
   --name pullbot \
   -p 54322:54322 \
   pullbot:latest

