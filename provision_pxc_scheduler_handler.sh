#!/bin/bash

# run as root

# https://github.com/Tusamarco/pxc_scheduler_handler

wget https://golang.org/dl/go1.17.linux-amd64.tar.gz

rm -rf /usr/local/go && tar -C /usr/local -xzf go1.17.linux-amd64.tar.gz

export PATH=$PATH:/usr/local/go/bin

yum -y install git

git clone https://github.com/Tusamarco/pxc_scheduler_handler.git

cd pxc_scheduler_handler/

go get github.com/Tusamarco/toml
go get github.com/go-sql-driver/mysql
go get github.com/sirupsen/logrus
go get golang.org/x/text/language
go get golang.org/x/text/message

go build -o pxc_scheduler_handler .

cp pxc_scheduler_handler /var/lib/proxysql/pxc_scheduler_handler
cp config/config.toml /var/lib/proxysql/.

cd ..

rm -f go1.17.linux-amd64.tar.gz

tee fix_servers.sql <<EOF
DELETE FROM runtime_mysql_galera_hostgroups;
DELETE FROM mysql_servers ;

INSERT INTO mysql_servers (hostname,hostgroup_id,port,weight,max_connections,comment) VALUES ('192.168.35.50',100,3306,1000,2000,'Preferred writer');
INSERT INTO mysql_servers (hostname,hostgroup_id,port,weight,max_connections,comment) VALUES ('192.168.35.51',100,3306,999,2000,'Second preferred ');
INSERT INTO mysql_servers (hostname,hostgroup_id,port,weight,max_connections,comment) VALUES ('192.168.35.52',100,3306,998,2000,'Last chance');

INSERT INTO mysql_servers (hostname,hostgroup_id,port,weight,max_connections,comment) VALUES ('192.168.35.50',101,3306,998,2000,'Last reader');
INSERT INTO mysql_servers (hostname,hostgroup_id,port,weight,max_connections,comment) VALUES ('192.168.35.51',101,3306,1000,2000,'reader1');    
INSERT INTO mysql_servers (hostname,hostgroup_id,port,weight,max_connections,comment) VALUES ('192.168.35.52',101,3306,1000,2000,'reader2');        

INSERT INTO mysql_servers (hostname,hostgroup_id,port,weight,max_connections,comment) VALUES ('192.168.35.50',8100,3306,1000,2000,'Failover server preferred');
INSERT INTO mysql_servers (hostname,hostgroup_id,port,weight,max_connections,comment) VALUES ('192.168.35.51',8100,3306,999,2000,'Second preferred');    
INSERT INTO mysql_servers (hostname,hostgroup_id,port,weight,max_connections,comment) VALUES ('192.168.35.52',8100,3306,998,2000,'Thirdh and last in the list');      

INSERT INTO mysql_servers (hostname,hostgroup_id,port,weight,max_connections,comment) VALUES ('192.168.35.50',8101,3306,998,2000,'Failover server preferred');
INSERT INTO mysql_servers (hostname,hostgroup_id,port,weight,max_connections,comment) VALUES ('192.168.35.51',8101,3306,999,2000,'Second preferred');    
INSERT INTO mysql_servers (hostname,hostgroup_id,port,weight,max_connections,comment) VALUES ('192.168.35.52',8101,3306,1000,2000,'Thirdh and last in the list');      

LOAD MYSQL SERVERS TO RUNTIME; SAVE MYSQL SERVERS TO DISK; 
EOF

admin <fix_servers.sql
