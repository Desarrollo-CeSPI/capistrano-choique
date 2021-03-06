require 'capistrano'
require 'capistrano-choique/version'


module Capistrano
  module Choique
    def self.load_into(configuration)
      configuration.load do
        load_paths.push File.expand_path('../', __FILE__)
        Dir.glob(File.join(File.dirname(__FILE__), '/capistrano-choique/recipes/*.rb')).sort.each { |f| load f }

        set :repository,  "https://github.com/Desarrollo-CeSPI/choique.git"
        set :deploy_via,  :remote_cache
        set :scm,         :git

        set(:choique_tag) { branch }

        set :branch do
          default_tag = /tags\/([\w.\d]+).*?$/.match(`git ls-remote -t #{repository}`.split("\n").last) 
          default_tag = if default_tag 
                          default_tag[1]  
                        else
                          "master"
                        end
          tag = Capistrano::CLI.ui.ask "Tag to deploy (Press enter when done): [#{default_tag}]"
          tag = default_tag if tag.empty?
          tag
        end

        set(:user) { application }

        set :php_bin,     "php"

        set :db_type, "mysql"
        set :db_host, "localhost"
        set :db_port, "3306"
        set(:db_name) { application }
        set(:db_user) { application }

        set :symfony_env_prod, :prod
        set :symfony_env_local, :dev

        set (:remote_tmp_dir) { "#{deploy_to}/tmp" }

        set(:choique_name) { application }
        set :choique_backend_port, "8000"
        set(:choique_frontend_url) { "http://#{domain}/" }
        set(:choique_backend_url) { "https://#{domain}:#{choique_backend_port}/" }
        set :choique_testing, false

        set :shared_children, %w(log web-frontend/uploads flavors data/index)
        set :shared_files, %w(apps/backend/config/factories.yml config/databases.yml config/propel.ini config/app.yml config/choique.yml)
        set :asset_children,    %w(web-frontend/css web-frontend/images web-frontend/js web-backend/css web-backend/images web-backend/js)

        # helper function
        def deep_merge(hash1, hash2)

            #if both 'all' and env keys are nil break
            if(hash1 == nil && hash2 == nil)
              return nil
            end

            #the config.yml may not have 'all' key but instead 'dev' 'prod' and so on
            if(hash1 == nil && hash2 != nil)
              return hash2 # no need to merge
            end

            #if only the 'all' key is specified
            #There might not be a second has to cascade to
            if(hash2 == nil && hash1 != nil)
              return hash1;
            end
            hash1.merge(hash2){|key, subhash1, subhash2|
                if (subhash1.is_a?(Hash) && subhash2.is_a?(Hash))
                    next deep_merge(subhash1, subhash2)
                end
                subhash2
            }
        end

        # load database params from databases.yml to build mysql/pgsql commands
        def load_database_config(data, env)
          db_config = YAML::load(data)

          connections = deep_merge(db_config['all'], db_config[env.to_s])

          db_param = connections['propel']['param']

          {
            'type'  => db_param['phptype'],
            'user'  => db_param['username'],
            'pass'  => db_param['password'],
            'db'    => db_param['database'],
            'host'  => db_param['hostspec'],
            'port'  => db_param['port']
          }
        end

        # generate mysql / pgsql commands
        def generate_sql_command(cmd_type, config)
            db_type  = config['type']
            cmd_conf = {
              'mysql' => {
                'create' => "mysqladmin -u #{config['user']} --password='#{config['pass']}' create",
                'dump'   => "mysqldump -u #{config['user']} --password='#{config['pass']}'",
                'drop'   => "mysqladmin -f -u #{config['user']} --password='#{config['pass']}' drop",
                'import' => "mysql -u #{config['user']} --password='#{config['pass']}'"
              },
              'pgsql' => {
                'create' => "createdb -U #{config['user']}",
                'dump'   => "pg_dump -U #{config['user']}",
                'drop'   => "dropdb -U #{config['user']}",
                'import' => "psql -U #{config['user']} --password='#{config['pass']}'"
              }
            }

            cmd = cmd_conf[db_type][cmd_type]
            cmd+= " --host=#{config['host']}" if config['host']
            cmd+= " --port=#{config['port']}" if config['port']
            cmd+= " #{config['db']}"

            cmd
        end

        after "deploy:finalize_update" do
          choique.flavors.init if choique.flavors_initialize?
          choique.build_model
          choique.fix_permissions
          choique.data_init if choique.need_init?
          choique.flavors.fix_flavor unless choique.flavors_initialize?
          choique.cc
        end

        after "deploy:setup" do
          prefix = File.join(File.dirname(__FILE__), '/../data/templates/')
          database_conf = ERB.new(File.read("#{prefix}/databases.yml.erb")).result(binding)
          propel_conf = ERB.new(File.read("#{prefix}/propel.ini.erb")).result(binding)
          app_conf = ERB.new(File.read("#{prefix}/app.yml.erb")).result(binding)
          factories_conf = ERB.new(File.read("#{prefix}/backend_factories.yml.erb")).result(binding)
          run "#{try_sudo} mkdir -p #{shared_path}/config #{shared_path}/apps/backend/config"
          put database_conf, "#{shared_path}/config/databases.yml"
          put propel_conf, "#{shared_path}/config/propel.ini"
          put app_conf, "#{shared_path}/config/app.yml"
          put factories_conf, "#{shared_path}/apps/backend/config/factories.yml"
          run "#{try_sudo} mkdir -p #{remote_tmp_dir}"
        end

        after "deploy:create_symlink" do
          deploy_date = Time.now.strftime('%F')
          build_version = "#{deploy_date} #{choique_tag} build+#{current_revision}"
          put(build_version,"#{current_release}/VERSION")
        end

      end
    end
  end
end

if Capistrano::Configuration.instance
    Capistrano::Choique.load_into(Capistrano::Configuration.instance)
end

