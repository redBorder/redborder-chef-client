#!/bin/bash
source /etc/profile
rvm gemset use default &>/dev/null
source /etc/sysconfig/chef-client
exec chef-client -c $CONFIG -i $INTERVAL -s $SPLAY $OPTIONS
