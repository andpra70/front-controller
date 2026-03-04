#!/bin/bash

# Stop all running containers at once
docker stop $(docker ps -q)

# Optionally, you can also remove the stopped containers
docker rm $(docker ps -a -q)

# If you want to remove all images as well, uncomment the following line
# docker rmi $(docker images -q)

echo "All containers stopped and removed. All images removed."
