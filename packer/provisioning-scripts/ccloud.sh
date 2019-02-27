#!/bin/bash
set -eu -o pipefail

wget https://s3-us-west-2.amazonaws.com/confluent.cloud/cli/ccloud-latest.tar.gz
tar xfz ccloud-latest.tar.gz
rm ccloud-latest.tar.gz # Need to delete before finding $CCLOUD_DIR

CCLOUD_DIR=$(ls | grep ccloud)
sudo cp $CCLOUD_DIR/bin/* /usr/local/bin/
sudo cp $CCLOUD_DIR/share/java/ccloud-0.2.1.jar /usr/local/share/java/

rm -rf $CCLOUD_DIR
