#!/bin/bash

. ./sysbench_config

sysbench \
	--db-driver=mysql \
	--mysql-user=app \
	--mysql_password=app \
	--mysql-db=test \
	--mysql-host=${HOST_IP} \
	--mysql-port=${HOST_PORT} \
	--tables=${TABLES} \
	--table-size=${TABLE_SIZE} \
	/usr/share/sysbench/${TYPE} \
	prepare
