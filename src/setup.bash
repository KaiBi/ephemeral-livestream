#!/bin/bash

set -euo pipefail

apt-get update
apt-get install -y openssh-server putty-tools

mkdir -p ../.secret/

rm -f ../.secret/ssh_host_*
cp -a /etc/ssh/ssh_host_* ../.secret/

rm -f ../.secret/host_fingerprint
ssh-keygen -lf ../.secret/ssh_host_ed25519_key.pub -E md5 | cut -c9-55 > ../.secret/host_fingerprint

rm -f ../.secret/id_ed25519{,.pub,.ppk}
ssh-keygen -t ed25519 -q -N "" -f ../.secret/id_ed25519
puttygen ../.secret/id_ed25519 -o ../.secret/id_ed25519.ppk