#!/bin/bash

redir -I memcached :11211 memcached:11211
redir -I redis     :6379  redis:6379

trap "exit 0" SIGTERM
sleep infinity &
wait $!
