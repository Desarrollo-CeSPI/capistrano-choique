namespace :choique do
  # Needs to initialize db?
  def need_init? 
    config = ""
    run "#{try_sudo} cat #{shared_path}/config/databases.yml" do |ch, st, data|
      config = load_database_config data, :prod
    end
    sql_dump_cmd = generate_sql_command('dump', config)
    logger.debug sql_dump_cmd.gsub(/(--password=)([^ ]+)/, '\1\'********\'')    # Log the command with a masked password
    saved_log_level = logger.level
    logger.level = Capistrano::Logger::IMPORTANT    # Change log level so that the real command (containing a plaintext password) is not displayed
    ret = 'true' != capture("if `#{sql_dump_cmd} 2> /dev/null | grep -q article`; then echo true; fi").chomp
    logger.level = saved_log_level
    ret
  end

  # Needs to create a default flavor?
  def flavors_initialize?
    capture("ls #{shared_path}/flavors | wc -l").chomp.to_i == 0
  end


  desc "Creates model classes. It will not touch database"
  task :build_model do
    stream "cd #{latest_release} && #{php_bin} ./symfony propel-build-model"
  end

  desc "Creates model classes and destroy and initialize database with default data"
  task :data_init do
    stream "cd #{latest_release} && #{php_bin} ./symfony propel-build-all-load backend"
    choique.reindex
  end

  desc "Rebuild search index"
  task :reindex do
    stream "cd #{latest_release} && #{php_bin} ./symfony choique-reindex"
  end

  desc "Fix file permission"
  task :fix_permissions do
    stream "cd #{latest_release} && #{php_bin} ./symfony choique-fix-perms"
  end

  desc "Clear symfony cache"
  task :cc do
    stream "cd #{latest_release} && #{php_bin} ./symfony cc"
  end

  desc "Package current version of choique including dump and download"
  task :package do
    name = "choique-#{Time.now.strftime('%F')}"
    run "cat #{current_release}/VERSION" do |ch, st, data|
      name += "-" + data.gsub(/ build.*/,'').gsub(/^\d{4}-\d{2}-\d{2} (v[\w.-_]+)/,'\1')
    end
    run "test -d #{remote_tmp_dir}/#{name} && rm -fr #{remote_tmp_dir}/#{name}; true"
    run "mkdir #{remote_tmp_dir}/#{name}"
    run "cd #{latest_release}; tar cf - * | (cd #{remote_tmp_dir}/#{name}; tar xfp -)"
    dereference = (shared_children + shared_files).join(' ')
    run "cd #{latest_release}; tar cf - #{dereference} -h | (cd #{remote_tmp_dir}/#{name}; tar xfp -)"
    run "rm #{remote_tmp_dir}/#{name}/config/databases.yml #{remote_tmp_dir}/#{name}/config/propel.ini"
    run "rm -fr #{remote_tmp_dir}/#{name}/cache/*;"
    run "rm -fr #{remote_tmp_dir}/#{name}/log/*;"    

    # Dump database
    file = "#{remote_tmp_dir}/#{name}/dump-#{name}.sql"
    config = ""
    run "#{try_sudo} cat #{shared_path}/config/databases.yml" do |ch, st, data|
      config = load_database_config data, symfony_env_prod
    end  
    sql_dump_cmd = generate_sql_command('dump', config)
    logger.debug sql_dump_cmd.gsub(/(--password=)([^ ]+)/, '\1\'********\'')    # Log the command with a masked password
    saved_log_level = logger.level
    logger.level = Capistrano::Logger::IMPORTANT    # Change log level so that the real command (containing a plaintext password) is not displayed
    try_sudo "#{sql_dump_cmd} | gzip -c > #{file}"
    logger.level = saved_log_level
    
    # Package and transfer
    run "cd #{remote_tmp_dir}/; tar cfz #{name}.tgz #{name}"
    require "fileutils"
    FileUtils.mkdir_p("backups")
    get "#{remote_tmp_dir}/#{name}.tgz", "backups/#{name}.tgz"
    begin
      FileUtils.ln_sf("#{name}.tgz", "backups/package-latest.tgz")
    rescue Exception # fallback for file systems that don't support symlinks
      FileUtils.cp_r("#{name}.tgz", "backups/package-latest.tgz")
    end  
    run "rm -fr #{remote_tmp_dir}/#{name}.tgz #{remote_tmp_dir}/#{name}"
  end

  namespace :app do

    desc "Disable a aplication"
    task :disable do
      app_name = Capistrano::CLI.ui.ask "Enter application name (frontend|backend):"
      env_name = Capistrano::CLI.ui.ask "Enter enviroment name (prod|dev):"
      stream "cd #{latest_release} && #{php_bin} ./symfony disable '#{app_name}' '#{env_name}'"
    end

    desc "Enable a aplication"
    task :enable do
      app_name = Capistrano::CLI.ui.ask "Enter application name (frontend|backend):"
      env_name = Capistrano::CLI.ui.ask "Enter enviroment name (prod|dev):"
      stream "cd #{latest_release} && #{php_bin} ./symfony enable '#{app_name}' '#{env_name}'"
    end

  end

  namespace :user do

    desc "Create/Update user"
    task :update_or_create_admin do
      username = Capistrano::CLI.ui.ask "Enter username:"
      password = Capistrano::CLI.password_prompt 
      stream "cd #{latest_release} && #{php_bin} ./symfony choique-user-update-or-create-admin '#{username}' '#{password}'"
    end

    desc "Enable user"
    task :enable do
      username = Capistrano::CLI.ui.ask "Enter username:"
      stream "cd #{latest_release} && #{php_bin} ./symfony choique-user-enable '#{username}'"
    end

    desc "Disable user"
    task :disable do
      username = Capistrano::CLI.ui.ask "Enter username:"
      stream "cd #{latest_release} && #{php_bin} ./symfony choique-user-disable '#{username}'"
    end
  end

  namespace :flavors do

    desc "Set default flavor"
    task :init do
      stream "cd #{latest_release} && #{php_bin} ./symfony choique-flavors-initialize"
    end

    desc "Download current flavor"
    task :download_current do
      choique_config = {}
      run "#{try_sudo} cat #{current_dir}/config/choique.yml" do |ch, st, data|
       choique_config = YAML::load(data)
      end
      current = choique_config['choique']['flavors']['current']
      filename = "#{application}.remote_current_flavor.#{Time.now.strftime("%Y-%m-%d_%H-%M-%S")}.zip"
      file = "#{remote_tmp_dir}/#{filename}"
      try_sudo "cd #{shared_path}/flavors/#{current}; zip -r #{file} *"
      require "fileutils"
      FileUtils.mkdir_p("backups")
      get file, "backups/#{filename}"
      begin
        FileUtils.ln_sf(filename, "backups/#{application}.remote_current_flavor.latest.zip")
      rescue Exception # fallback for file systems that don't support symlinks
        FileUtils.cp_r("backups/#{filename}", "backups/#{application}.remote_current_flavor.latest.zip")
      end
      run "#{try_sudo} rm #{file}"
    end

    desc "Download flavors folder and install it locally"
    task :to_local do
      choique_config = {}
      run "#{try_sudo} cat #{current_dir}/config/choique.yml" do |ch, st, data|
       choique_config = YAML::load(data)
      end
      run_locally("rm -fr flavors/*")
      current = choique_config['choique']['flavors']['current']
      download("#{shared_path}/flavors", ".", :via => :scp, :recursive => true)
      run_locally("php symfony choique-flavor-select #{current}")
    end

    desc "Upload flavors folder and install it remotelly"
    task :to_remote do
      choique_config = {}
      run "#{try_sudo} cat #{current_dir}/config/choique.yml" do |ch, st, data|
       choique_config = YAML::load(data)
      end
      current = choique_config['choique']['flavors']['current']
      run "#{try_sudo} rm -fr #{shared_path}/flavors/*"
      upload("flavors", "#{shared_path}", :via => :scp, :recursive => true)
      stream "cd #{latest_release} && #{php_bin} ./symfony choique-flavor-select #{current}"
    end


    desc "Fix flavor after deploy"
    task :fix_flavor do
      choique_config = {}
      run "#{try_sudo} cat #{shared_path}/config/choique.yml" do |ch, st, data|
       choique_config = YAML::load(data)
      end
      current = choique_config['choique']['flavors']['current']
      stream "cd #{latest_release} && #{php_bin} ./symfony choique-flavor-select #{current}"
    end
  end

end

