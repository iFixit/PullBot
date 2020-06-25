#!/bin/bash
docker run \
   --net host \
   --detach \
   --name pullbot \
   -p 54322:54322 \
   pullbot:latest

