#!/bin/bash
set -eu -o pipefail

sudo apt-get install -y default-jre

# Create java directory for .jar files
sudo mkdir /usr/local/share/java
