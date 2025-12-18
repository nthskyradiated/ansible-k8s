#!/bin/bash

sed -i -e 's/#DNS=/DNS=8.8.8.8 4.2.2.2/' /etc/systemd/resolved.conf

service systemd-resolved restart