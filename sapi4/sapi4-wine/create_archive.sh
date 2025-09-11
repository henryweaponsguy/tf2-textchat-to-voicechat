#!/bin/bash

CONTAINER_NAME="sapi4-wine"


echo "Creating the archive..."
docker compose up -d --build

docker exec "$CONTAINER_NAME" bash -c "find /root/.wine -type f -exec md5sum {} \; | sort > /root/files_before_install.txt"

docker exec -it "$CONTAINER_NAME" wine /root/spchapi.exe /Q
docker exec -it "$CONTAINER_NAME" wine /root/tv_enua.exe /Q
docker exec -it "$CONTAINER_NAME" wine /root/msttsl.exe /Q
echo "Files installed..."

docker exec "$CONTAINER_NAME" bash -c "find /root/.wine -type f -exec md5sum {} \; | sort > /root/files_after_install.txt"

# Compare files before and after the installation and keep only new or modified ones
docker exec "$CONTAINER_NAME" bash /root/compare_and_move_files.sh "/root/tmp/compare_output" "/root/files_before_install.txt" "/root/files_after_install.txt"

docker exec "$CONTAINER_NAME" bash -c "mv /root/tmp/compare_output/root/.wine /root/tmp/.wine"

docker exec -it "$CONTAINER_NAME" bash -c "cd /root/tmp && tar --sort=name --owner=0 --group=0 --mtime='UTC 1970-01-01' -cf - .wine/ | gzip -n > /root/wine.tar.gz"
echo "Archive created..."

docker exec -it "$CONTAINER_NAME" bash -c "mv /root/wine.tar.gz /out"
echo "Archive copied outside the container..."

docker compose down
echo "Archive creation complete..."
