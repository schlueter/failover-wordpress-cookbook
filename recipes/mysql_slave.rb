##
#    Copyright (C) 2015 Brandon Schlueter
#
#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.
##

db = node['failover_wordpress']['database']['slave']
master_db = node['failover_wordpress']['database']['master']

mysql_service db['instance_name'] do
  port '3306'
  version '5.5'
  bind_address db['host']
  initial_root_password db['root_password']
  action [:create, :start]
end

mysql_config db['instance_name'] do
  source 'mysite.cnf.erb'
  notifies :restart, 'mysql_service[default]'
  variables(
    server_id: db['server_id'],
    host: db['host']
  )
  action :create
end

mysql2_chef_gem 'default' do
  action :install
end

socket = "/var/run/mysql-#{db['instance_name']}/mysqld.sock"

if node['platform_family'] == 'debian'
  link '/var/run/mysqld/mysqld.sock' do
    to socket
    not_if 'test -f /var/run/mysqld/mysqld.sock'
  end
elsif node['platform_family'] == 'rhel'
  link '/var/lib/mysql/mysql.sock' do
    to socket
    not_if 'test -f /var/lib/mysql/mysql.sock'
  end
end

mysql_connection_info = {
  host: db['host'],
  username: 'root',
  password: db['root_password']
}

mysql_database_user db['app_user'] do
  connection mysql_connection_info
  password db['app_pass']
  database_name db['name']
  host node['failover_wordpress']['webserver']['host']
  privileges [:all]
  action [:create, :grant]
end

mysql_database_user db['slave_user'] do
  connection mysql_connection_info
  password db['slave_pass']
  host node['failover_wordpress']['database']['slave']['host']
  privileges ['REPLICATION SLAVE']
  action [:create, :grant]
end

mysql_database db['name'] do
  connection mysql_connection_info
  sql <<-SQL
CHANGE MASTER TO
  MASTER_HOST='#{master_db['host']}',
  MASTER_USER='#{master_db['slave_user']}',
  MASTER_PASSWORD='#{master_db['slave_pass']}',
  MASTER_LOG_FILE='#{master_db['log_file']}',
  MASTER_LOG_POS=#{master_db['log_pos']};
  SQL
  action [:create, :query]
end