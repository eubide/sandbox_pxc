#!/bin/bash

iptables -F
setenforce 0

cat <<EOF >/etc/environment
LANG=en_US.utf-8
LC_ALL=en_US.utf-8
EOF

NODE_NR=$1
NODE_IP="$2"
IPS_COMMA="$3"
BOOTSTRAP_IP="$4"

yum makecache fast

yum -y install yum install https://repo.percona.com/yum/percona-release-latest.noarch.rpm
yum -y install tar gdb strace vim qpress socat

# yum -q list available --showduplicates Percona-XtraDB-Cluster-server-57
# [...]
# Percona-XtraDB-Cluster-server-57.x86_64                5.7.28-31.41.2.el7
# Percona-XtraDB-Cluster-server-57.x86_64                5.7.29-31.43.1.el7
# Percona-XtraDB-Cluster-server-57.x86_64                5.7.30-31.43.1.el7
# Percona-XtraDB-Cluster-server-57.x86_64                5.7.31-31.45.1.el7
# Percona-XtraDB-Cluster-server-57.x86_64                5.7.31-31.45.2.el7
# Percona-XtraDB-Cluster-server-57.x86_64                5.7.31-31.45.3.el7
# Percona-XtraDB-Cluster-server-57.x86_64                5.7.32-31.47.1.el7
# Percona-XtraDB-Cluster-server-57.x86_64                5.7.33-31.49.1.el7

yum -y -q install Percona-XtraDB-Cluster-server-57-5.7.31-31.45.3.el7.x86_64

mysqld --initialize-insecure --user=mysql

tee /etc/my.cnf <<EOF
[mysql]
port                                = 3306
socket                              = /var/lib/mysql/mysql.sock
prompt                              = 'PXC: \u@\h (\d) > '

[client]
port                                = 3306
socket                              = /var/lib/mysql/mysql.sock

[mysqld]
socket                              = /var/lib/mysql/mysql.sock
datadir                             = /var/lib/mysql
user                                = mysql

wsrep_cluster_name                  = pxc_test

wsrep_provider                      = /usr/lib64/libgalera_smm.so
wsrep_provider_options              = "gcs.fc_limit=500; gcs.fc_master_slave=YES; gcs.fc_factor=1.0; gcache.size=256M;"
wsrep_slave_threads                 = 1
wsrep_auto_increment_control        = ON

wsrep_sst_method                    = xtrabackup-v2
wsrep_sst_auth                      = root:sekret

wsrep_cluster_address               = gcomm://$IPS_COMMA
wsrep_node_address                  = $NODE_IP
wsrep_node_name                     = node$NODE_NR

innodb_locks_unsafe_for_binlog      = 1
innodb_autoinc_lock_mode            = 2
innodb_file_per_table               = 1
innodb_log_file_size                = 256M
innodb_flush_log_at_trx_commit      = 2
innodb_buffer_pool_size             = 512M
innodb_use_native_aio               = 0

server_id                           = $NODE_NR
binlog_format                       = ROW

[sst]
streamfmt                           = xbstream

[xtrabackup]
compress
parallel                            = 2
compress_threads                    = 2
rebuild_threads                     = 2
EOF

if [[ $NODE_NR -eq 1 ]]; then
	systemctl start mysql@bootstrap

	# ProxySQL users
	mysql -e "CREATE USER 'monitor'@'%' IDENTIFIED BY 'monit0r';"
	mysql -e "GRANT USAGE ON *.* TO 'monitor'@'%';"
	mysql -e "CREATE USER 'monitor'@'localhost' IDENTIFIED BY 'monit0r';"
	mysql -e "GRANT USAGE ON *.* TO 'monitor'@'localhost';"

	mysql -e "CREATE USER 'app'@'%' IDENTIFIED BY 'app';"
	mysql -e "GRANT ALL ON *.* TO 'app'@'%';"
	mysql -e "CREATE USER 'app'@'localhost' IDENTIFIED BY 'app';"
	mysql -e "GRANT ALL ON *.* TO 'app'@'localhost';"

	mysql -e "CREATE USER 'mariabackup'@'localhost' IDENTIFIED BY 'mar1ab4ckup';"
	mysql -e "GRANT RELOAD, PROCESS, LOCK TABLES, REPLICATION CLIENT ON *.* TO 'mariabackup'@'localhost';"

	mysql -e "CREATE DATABASE test;"

	mysql -e "GRANT ALL PRIVILEGES ON *.* TO 'root'@'192.%' IDENTIFIED BY 'sekret';"
	mysql -e "GRANT ALL PRIVILEGES ON *.* TO 'root'@'127.0.0.1' IDENTIFIED BY 'sekret';"
	mysql -e "GRANT ALL PRIVILEGES ON *.* TO 'root'@'localhost' IDENTIFIED BY 'sekret';"




else
	for i in {1..60}; do
		MYSQLADMIN=$(mysqladmin -uroot -psekret -h"$BOOTSTRAP_IP" ping)
		if [[ "$MYSQLADMIN" == "mysqld is alive" ]]; then
			systemctl start mysql
			echo "ready on $i"
			exit
		else
			sleep 5
		fi
	done
fi
