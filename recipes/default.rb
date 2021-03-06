include_recipe "java"

node.override.elasticsearch.version = node.elastic.version

if  node.elastic.systemd == false
  node.override.elastic.systemd == "false"
end
if  node.elastic.systemd == true
  node.override.elastic.systemd == "true"
end

case node.platform
when "ubuntu"
 if node.platform_version.to_f <= 14.04
   node.override.elastic.systemd = "false"
 end
end


Chef::Log.info "Using systemd (1): #{node.elastic.systemd}"

name = "elasticsearch-#{node.elastic.node_name}"

case node.platform_family
when 'rhel'
  package 'unzip'
end


elasticsearch_user 'elasticsearch' do
  username node.elastic.user
  groupname node.elastic.group
  shell '/bin/bash'
  comment 'Elasticsearch User'
  instance_name node.elastic.node_name
  action :create
end

install_dir = Hash.new
install_dir['package'] = node.elastic.dir

elasticsearch_install 'elastic_installation' do
  type :tarball
  version node.elastic.version
  instance_name node.elastic.node_name
#  download_url node['elasticsearch']['download_urls_v2']['tar']
  download_url node.elasticsearch.download_urls.tar
#  download_checksum node.elasticsearch.checksums["#{node.elasticsearch.version}"]['tar']
  download_checksum node.elastic.checksum
  action :install
end

node.override.ulimit.conf_dir = "/etc/security"
node.override.ulimit.conf_file = "limits.conf"

node.override.ulimit[:params][:default][:nofile] = 65000     # hard and soft open file limit for all users
node.override.ulimit[:params][:default][:nproc] = 8000

node.override.ulimit.conf_dir = "/etc/security"
node.override.ulimit.conf_file = "limits.conf"

node.override.ulimit[:params][:default][:nofile] = 65000     # hard and soft open file limit for all users
node.override.ulimit[:params][:default][:nproc] = 8000

include_recipe "ulimit2"


node.override.elasticsearch.url = node.elastic.url
node.override.elasticsearch.version = node.elastic.version

my_ip = my_private_ip()
mysql_ip = my_ip
elastic_ip = private_recipe_ip("elastic","default")

elasticsearch_configure 'my_elasticsearch' do
#  user node.elastic.user
#  group node.elastic.group
#  path_home node.elastic.home_dir
#  path_conf node.elastic.home_dir + "/etc/elasticsearch"
#  path_data node.elastic.home_dir + "/var/data/elasticsearch"
#  path_logs node.elastic.home_dir + "/var/log/elasticsearch"
  # path_pid ({
  #    'tarball' => node.elastic.home_dir + "/var"
  # })
  # path_bin ({
  #    'tarball' => node.elastic.home_dir + "/bin"
  # })
  logging({:"action" => 'INFO'})
  allocated_memory node.elastic.memory
  thread_stack_size node.elastic.thread_stack_size
  env_options '-DFOO=BAR'
  gc_settings <<-CONFIG
#                 -XX:+UseParNewGC
                -XX:+UseConcMarkSweepGC
                -XX:CMSInitiatingOccupancyFraction=75
                -XX:+UseCMSInitiatingOccupancyOnly
                -XX:+HeapDumpOnOutOfMemoryError
                -XX:+PrintGCDetails
              CONFIG
#  nofile_limit 64000
  configuration ({
    'cluster.name' => node.elastic.cluster_name,
    'node.name' => node.elastic.node_name,
    'network.host' =>  my_ip,
    'http.cors.enabled' => true,
    'http.cors.allow-origin' => "*"
  })
  instance_name node.elastic.node_name
  action :manage
end

elasticsearch_service "#{name}" do
   instance_name node.elastic.node_name
#  user node.elastic.user
#  group node.elastic.group
#  node_name node.elastic.node_name
#  pid_path node.elastic.home_dir + "/var/run"
#  path_conf node.elastic.home_dir + "/etc/elasticsearch"
   init_source 'elasticsearch.erb'
   init_cookbook 'elastic'
   service_actions [:nothing]
#   service_actions [:enable, :start]
end

file "#{node.elastic.home_dir}/config/elasticsearch.yml" do
  user node.elastic.user
  action :delete
end

template "#{node.elastic.home_dir}/config/elasticsearch.yml" do
  source "elasticsearch.yml.erb"
  user node.elastic.user
  group node.elastic.group
  mode "755"
  variables({
              :my_ip => my_ip
            })
end

template "#{node.elastic.home_dir}/config/elasticsearch.yml" do
  source "elasticsearch.yml.erb"
  user node.elastic.user
  group node.elastic.group
  mode "755"
  variables({
              :my_ip => my_ip
            })
end

template "#{node.elastic.home_dir}/bin/elastic-start.sh" do
  source "elastic-start.sh.erb"
  user node.elastic.user
  group node.elastic.group
  mode "751"
end

template "#{node.elastic.home_dir}/bin/elastic-stop.sh" do
  source "elastic-stop.sh.erb"
  user node.elastic.user
  group node.elastic.group
  mode "751"
end



template "#{node.elastic.home_dir}/bin/kill-process.sh" do
  source "kill-process.sh.erb"
  user node.elastic.user
  group node.elastic.group
  mode "751"
end

#if node.kagent.enabled == "true"

  kagent_config "elasticsearch" do
    service "elasticsearch"
    start_script "#{node.elastic.home_dir}/bin/elastic-start.sh"
    stop_script "#{node.elastic.home_dir}/bin/elastic-stop.sh"
    log_file "#{node.elastic.home_dir}/logs/#{node.elastic.cluster_name}.log"
    pid_file "/tmp/elasticsearch.pid"
  end
#end



template "#{node.elastic.home_dir}/bin/elasticsearch-stop.sh" do
  source "elasticsearch-stop.sh.erb"
  user node.elastic.user
  group node.elastic.group
  mode "751"
end

template "#{node.elastic.home_dir}/bin/elasticsearch-start.sh" do
  source "elasticsearch-start.sh.erb"
  user node.elastic.user
  group node.elastic.group
  mode "751"
end

if node.elastic.systemd == "true"
  file "/etc/init.d/#{name}" do
     action :delete
  end

  file "/etc/defaults/#{name}" do
     action :delete
  end

  file "/etc/rc.d/init.d/#{name}" do
    action :delete
  end

  elastic_service = "/lib/systemd/system/#{name}.service"

  case node.platform_family
  when "rhel"
    elastic_service =  "/usr/lib/systemd/system/#{name}.service"
  end

  execute "systemctl daemon-reload"

  template "#{elastic_service}" do
    source "elasticsearch.service.erb"
    user "root"
    group "root"
    mode "754"
    variables({
                :start_script => "#{node.elastic.home_dir}/bin/elasticsearch-start.sh",
                :stop_script => "#{node.elastic.home_dir}/bin/elasticsearch-stop.sh",
                :install_dir => "#{node.elastic.home_dir}",
                :pid => "/tmp/elasticsearch.pid",
                :nofile_limit => node.elastic.limits.nofile,
                :memlock_limit => node.elastic.limits.memory_limit
              })
#    notifies :enable, "service[#{name}]"
#    notifies :restart, "service[#{name}]", :immediately
  end

else  # systemd is false

  # template "/etc/init.d/#{name}" do
  #   source "elasticsearch.erb"
  #   user "root"
  #   mode "755"
  #   variables({
  #               :elastic_ip => elastic_ip,
  #               :http_port => node.elastic.port,
  #               :nofile_limit => node.elastic.ulimit_files,
  #               :memlock_limit => node.elastic.ulimit_memlock,
  #               :args => ""
  #             })
  #   notifies :enable, "service[#{name}]"
  #   notifies :restart, "service[#{name}]", :immediately
  # end

end

Chef::Log.info "Using systemd (2): #{node.elastic.systemd}"

service "#{name}" do
  case node.elastic.systemd
    when "true"
    provider Chef::Provider::Service::Systemd
    else
    provider Chef::Provider::Service::Init::Debian
  end
  supports :restart => true, :stop => true, :start => true, :status => true
  action :enable
end

systemd = false
if node.elastic.systemd == "true" || node.elastic.systemd == true
  systemd = true
end

Chef::Log.info "Using systemd (4): #{systemd}"
 elastic_start "start_install_elastic" do
   elastic_ip elastic_ip
   systemd systemd
   action :run
 end
