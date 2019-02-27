#!/bin/bash
set -eu -o pipefail

RELEASE="public"

BASH_PROFILE=/home/ubuntu/.bash_profile

source $BASH_PROFILE


GO_SRC="$GOPATH/src"
GO_BIN="$GOPATH/bin"

mkdir -p $GOPATH
mkdir $GO_SRC
mkdir $GO_BIN

# Clone repository using SSH
cd $GO_SRC
git clone git@github.com:Eximchain/eximchain-transaction-executor.git
cd eximchain-transaction-executor

git checkout $RELEASE

# Build Go Project
go install
