#!/bin/bash
set -eu -o pipefail

ROOT=/opt/guardian

sudo mkdir $ROOT
sudo mkdir $ROOT/bin
sudo mkdir $ROOT/log
sudo mkdir $ROOT/go
sudo mkdir $ROOT/info

sudo chown -R ubuntu $ROOT
sudo chmod -R 777 $ROOT
