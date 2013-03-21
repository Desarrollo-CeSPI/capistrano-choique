# Extend deploy tasks from original
namespace :deploy do

  desc <<-DESC
    Prepares one or more servers for deployment. Before you can use any \
    of the Capistrano deployment tasks with your project, you will need to \
    make sure all of your servers have been prepared with `cap deploy:setup'. When \
    you add a new server to your cluster, you can easily run the setup task \
    on just that server by specifying the HOSTS environment variable:

      $ cap HOSTS=new.server.com deploy:setup

    It is safe to run this task on servers that have already been set up; it \
    will not destroy any deployed revisions or data.
  DESC
  task :setup, :except => { :no_release => true } do
    dirs = [deploy_to, releases_path, shared_path]
    dirs += shared_children.map { |d| File.join(shared_path, d) }
    run "#{try_sudo} mkdir -p #{dirs.join(' ')}"
    run "#{try_sudo} chmod g+w #{dirs.join(' ')}" if fetch(:group_writable, true)
  end

  desc "Symlink static directories and static files that need to remain between deployments."
  task :share_childs do
    if shared_children
      shared_children.each do |link|
        run "#{try_sudo} mkdir -p #{shared_path}/#{link}"
        run "#{try_sudo} sh -c 'if [ -d #{release_path}/#{link} ] ; then rm -rf #{release_path}/#{link}; fi'"
        run "#{try_sudo} ln -nfs #{shared_path}/#{link} #{release_path}/#{link}"
      end
    end
    if shared_files
      shared_files.each do |link|
        link_dir = File.dirname("#{shared_path}/#{link}")
        run "#{try_sudo} mkdir -p #{link_dir}"
        run "#{try_sudo} touch #{shared_path}/#{link}"
        run "#{try_sudo} ln -nfs #{shared_path}/#{link} #{release_path}/#{link}"
      end
    end
  end

  desc "Customize the finalize_update task to work with symfony."
  task :finalize_update, :except => { :no_release => true } do
    run "#{try_sudo} chmod -R g+w #{latest_release}" if fetch(:group_writable, true)
    run "#{try_sudo} mkdir -p #{latest_release}/cache"
    run "#{try_sudo} chmod -R g+w #{latest_release}/cache"

    # Share common files & folders
    share_childs

    if fetch(:normalize_asset_timestamps, true)
      stamp = Time.now.utc.strftime("%Y%m%d%H%M.%S")
      asset_paths = asset_children.map { |p| "#{latest_release}/#{p}" }.join(" ")
      run "#{try_sudo} find #{asset_paths} -exec touch -t #{stamp} {} ';'; true", :env => { "TZ" => "UTC" }
    end
  end
end

