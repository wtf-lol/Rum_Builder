#!/bin/bash

tar_zst ()
{
  sleep 105m
  echo $(date +"%d-%m-%Y %T")
  time tar "-I zstd -1 -T2" -cf $rom.ccache.tar.zst $rom
  rclone copy --drive-chunk-size 256M --stats 1s $rom.ccache.tar.zst remote:ccache -P
}

cd /tmp
tar_zst ccache
echo $(date +"%d-%m-%Y %T")
