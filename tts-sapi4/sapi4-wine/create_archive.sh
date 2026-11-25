#!/usr/bin/bash

container_name="sapi4-wine"


printf "%s\n" "Creating the archive..."
docker compose up -d --build

docker exec "$container_name" bash -c "find /root/.wine -type f -exec md5sum {} \; | sort > /root/files_before_install.txt"

docker exec -it "$container_name" wine /root/spchapi.exe /Q
docker exec -it "$container_name" wine /root/tv_enua.exe /Q
docker exec -it "$container_name" wine /root/msttsl.exe /Q
printf "%s\n" "Files installed..."

docker exec "$container_name" bash -c "find /root/.wine -type f -exec md5sum {} \; | sort > /root/files_after_install.txt"

# Compare files before and after the installation and keep only new or modified ones
docker exec "$container_name" bash /root/compare_and_move_files.sh "/root/tmp/compare_output" "/root/files_before_install.txt" "/root/files_after_install.txt"

docker exec "$container_name" bash -c "mv /root/tmp/compare_output/root/.wine /root/tmp/.wine"

docker exec "$container_name" bash -c "cd /root/tmp && tar --sort=name --owner=0 --group=0 --mtime='UTC 1970-01-01' -cf - .wine/ | gzip -n > /root/wine.tar.gz"
printf "%s\n" "Archive created..."

docker exec "$container_name" bash -c "mv /root/wine.tar.gz /out"
printf "%s\n" "Archive copied outside the container..."

docker compose down
printf "%s\n" "Archive creation complete..."
