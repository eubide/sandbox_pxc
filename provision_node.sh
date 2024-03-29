#!/bin/bash

iptables -F
setenforce 0
sed -i 's/SELINUX=enforcing/SELINUX=disabled/g' /etc/selinux/config

cat <<EOF >/etc/environment
LANG=en_US.utf-8
LC_ALL=en_US.utf-8
LC_CTYPE=en_US.UTF-8
LC_ALL=en_US.UTF-8
EOF

sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/g' /etc/ssh/sshd_config
systemctl restart sshd.service

NODE_NR=$1
NODE_IP="$2"
IPS_COMMA="$3"
BOOTSTRAP_IP="$4"

yum makecache fast

yum -y install yum install https://repo.percona.com/yum/percona-release-latest.noarch.rpm
yum -y install tar gdb strace perf socat pigz wget
yum -y install vim qpress percona-toolkit

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
# Percona-XtraDB-Cluster-server-57.x86_64                5.7.34-31.51.1.el7

# yum -y -q install Percona-XtraDB-Cluster-server-57-5.7.28-31.41.2.el7.x86_64
# yum -y -q install Percona-XtraDB-Cluster-server-57-5.7.30-31.43.1.el7.x86_64
# yum -y -q install Percona-XtraDB-Cluster-server-57-5.7.31-31.45.3.el7.x86_64

yum -y -q install Percona-XtraDB-Cluster-server-57-5.7.32-31.47.1.el7.x86_64

yum -y install sysbench

mysqld --initialize-insecure --user=mysql

tee /etc/my.cnf <<EOF
[mysql]
port                           = 3306
socket                         = /var/lib/mysql/mysql.sock
prompt                         = 'PXC ${NODE_NR}: \u@\h (\d) > '

[client]
port                           = 3306
socket                         = /var/lib/mysql/mysql.sock

[mysqld]
socket                         = /var/lib/mysql/mysql.sock
datadir                        = /var/lib/mysql
user                           = mysql

server_id                      = ${NODE_NR}0
binlog_format                  = ROW

log_error                      = node${NODE_NR}.err

innodb_locks_unsafe_for_binlog = 1
innodb_autoinc_lock_mode       = 2
innodb_file_per_table          = 1
innodb_log_file_size           = 256M
innodb_flush_log_at_trx_commit = 2
innodb_buffer_pool_size        = 512M
innodb_use_native_aio          = 0

wsrep_cluster_name             = pxc_test

wsrep_provider                 = /usr/lib64/libgalera_smm.so
wsrep_provider_options         = "gcs.fc_limit=100; gcs.fc_master_slave=NO; gcs.fc_factor=1.0; gcache.size=16M;"
# wsrep_provider_options       = "gcs.fc_limit=1; gcs.fc_master_slave=YES; gcache.size=256M;"
wsrep_slave_threads            = 1
wsrep_auto_increment_control   = ON

wsrep_sst_method               = xtrabackup-v2
wsrep_sst_auth                 = root:sekret

wsrep_cluster_address          = gcomm://$IPS_COMMA
wsrep_node_address             = $NODE_IP
wsrep_node_name                = node$NODE_NR

## async replica
# log_bin
# gtid_mode                      = ON
# log_slave_updates              = ON
# enforce-gtid-consistency       = ON

slow_query_log
long_query_time                = 0
slow_query_log_file            = slowquery_node${NODE_NR}.log

[sst]
streamfmt                      = xbstream

# pigz -- use-memory=32G and increase p to cpu number
# inno_apply_opts              = " --use-memory=1G"
compressor                     = "pigz -p2"
decompressor                   = "pigz -p2 -d"

[xtrabackup]
compress
parallel                       = 2
compress_threads               = 2
rebuild_threads                = 2
EOF

# exit 0

if [[ $NODE_NR -eq 1 ]]; then
  systemctl start mysql@bootstrap

  mysql -e "CREATE USER 'monitor'@'%' IDENTIFIED BY 'monit0r';"
  mysql -e "GRANT USAGE ON *.* TO 'monitor'@'%';"
  mysql -e "CREATE USER 'monitor'@'localhost' IDENTIFIED BY 'monit0r';"
  mysql -e "GRANT USAGE ON *.* TO 'monitor'@'localhost';"

  mysql -e "CREATE USER 'app'@'%' IDENTIFIED BY 'app';"
  mysql -e "GRANT ALL ON *.* TO 'app'@'%';"
  mysql -e "CREATE USER 'app'@'localhost' IDENTIFIED BY 'app';"
  mysql -e "GRANT ALL ON *.* TO 'app'@'localhost';"

  mysql -e "CREATE DATABASE IF NOT EXISTS test;"

  mysql -e "GRANT ALL PRIVILEGES ON *.* TO 'root'@'192.%' IDENTIFIED BY 'sekret';"
  mysql -e "GRANT ALL PRIVILEGES ON *.* TO 'root'@'127.0.0.1' IDENTIFIED BY 'sekret';"
  mysql -e "GRANT ALL PRIVILEGES ON *.* TO 'root'@'localhost' IDENTIFIED BY 'sekret';"

else

  for i in {1..60}; do
    MYSQLADMIN=$(mysqladmin -uroot -psekret -h"$BOOTSTRAP_IP" ping)
    if [[ "$MYSQLADMIN" == "mysqld is alive" ]]; then
      systemctl start mysql
      echo "ready on $i loop"
      exit
    else
      sleep 5
    fi
  done
fi

cat <<EOF >/home/vagrant/.my.cnf
[mysql]
user=root
password=sekret
EOF
