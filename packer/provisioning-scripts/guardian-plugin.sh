#!/bin/bash
set -eu -o pipefail

RELEASE="master"

BASH_PROFILE=/home/ubuntu/.bash_profile
PLUGIN_DIR=/opt/vault/bin/plugins

source $BASH_PROFILE

GO_SRC="$GOPATH/src"
GO_BIN="$GOPATH/bin"

sudo mkdir -p $GOPATH
sudo mkdir -p $GO_SRC/github.com/eximchain
sudo mkdir $GO_BIN

sudo chown -R ubuntu $GOPATH
sudo chmod -R 777 $GOPATH

# Build the plugin
cd $GO_SRC/github.com/eximchain
git clone git@github.com:Eximchain/vault-guardian-plugin.git
cd vault-guardian-plugin
git checkout $RELEASE
go build -o build/guardian-plugin

# Move the plugin to the plugin library dir
sudo mkdir $PLUGIN_DIR
sudo cp build/guardian-plugin $PLUGIN_DIR/

# Set permissions on plugin library dir
sudo chown vault:vault -R $PLUGIN_DIR
sudo chmod 644 $PLUGIN_DIR

# Remove source code
cd ..
sudo rm -rf vault-guardian-plugin