namespace :choique do
  namespace :uploads do
    desc "Download all files from remote web-frontend/uploads folder to local one"
    task :to_local do
      download("#{shared_path}/web-frontend/uploads", "web-frontend", :via => :scp, :recursive => true)
    end

    desc "Upload all files from local web/uploads folder to remote one"
    task :to_remote do
      upload("web-frontend/uploads", "#{shared_path}/web-frontend", :via => :scp, :recursive => true)
    end
  end
end
