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
  end

end
