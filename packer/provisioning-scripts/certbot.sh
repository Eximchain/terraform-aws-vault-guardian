#!/bin/bash
set -eu -o pipefail

# Install Certbot & dependencies as instructed for
# an nginx server running on Ubuntu 16.04, according
# to certbot's guidelines: https://certbot.eff.org/lets-encrypt/ubuntuxenial-nginx
sudo apt-get install -y software-properties-common
sudo add-apt-repository -y universe
sudo add-apt-repository -y ppa:certbot/certbot
sudo apt-get update
sudo apt-get install -y certbot python-certbot-nginx 