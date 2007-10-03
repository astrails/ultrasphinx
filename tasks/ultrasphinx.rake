
ENV['RAILS_ENV'] ||= "development"

namespace :ultrasphinx do  

  task :_environment => [:environment] do
    # We can't just chain :environment because we want to make 
    # sure it's set only for known Sphinx tasks
    Ultrasphinx.with_rake = true
  end
  
  desc "Bootstrap a full Sphinx environment"
  task :bootstrap => [:_environment, :configure, :index, :"daemon:restart"] do
  end
  
  desc "Rebuild the configuration file for this particular environment."
  task :configure => [:_environment] do
    Ultrasphinx::Configure.run
  end
  
  desc "Reindex the database and send an update signal to the search daemon."
  task :index => [:_environment] do
    mkdir_p Ultrasphinx::INDEX_SETTINGS['path']
    cmd = "indexer --config #{Ultrasphinx::CONF_PATH}"
    cmd << " #{ENV['OPTS']} " if ENV['OPTS']
    cmd << " --rotate" if ultrasphinx_daemon_running?
    cmd << " #{Ultrasphinx::UNIFIED_INDEX_NAME}"
    say cmd
    system cmd
  end
  
  
  namespace :daemon do
    desc "Start the search daemon"
    task :start => [:_environment] do
      FileUtils.mkdir_p File.dirname(Ultrasphinx::DAEMON_SETTINGS["log"]) rescue nil
      raise Ultrasphinx::DaemonError, "Already running" if ultrasphinx_daemon_running?
      system "searchd --config #{Ultrasphinx::CONF_PATH}"
      sleep(2) # give daemon a chance to write the pid file
      if ultrasphinx_daemon_running?
        say "started successfully"
      else
        say "failed to start"
      end
    end
    
    desc "Stop the search daemon"
    task :stop => [:_environment] do
      raise Ultrasphinx::DaemonError, "Doesn't seem to be running" unless ultrasphinx_daemon_running?
      system "kill #{pid = ultrasphinx_daemon_pid}"
      sleep(1)
      if ultrasphinx_daemon_running?
        system "kill -9 #{pid}"  
        sleep(1)
      end
      if ultrasphinx_daemon_running?
        say "#{pid} could not be stopped"
      else
        say "stopped #{pid}"
      end
    end

    desc "Restart the search daemon"
    task :restart => [:_environment] do
      Rake::Task["ultrasphinx:daemon:stop"].invoke if ultrasphinx_daemon_running?
      sleep(3)
      Rake::Task["ultrasphinx:daemon:start"].invoke
    end
    
    desc "Check if the search daemon is running"
    task :status => [:_environment] do
      if ultrasphinx_daemon_running?
        say "daemon is running."
      else
        say "daemon is stopped."
      end
    end      
  end
          
    
  namespace :spelling do
    desc "Rebuild the custom spelling dictionary. You may need to use 'sudo' if your Aspell folder is not writable by the app user."
    task :build => [:_environment] do    
      ENV['OPTS'] = "--buildstops #{Ultrasphinx::STOPWORDS_PATH} #{Ultrasphinx::MAX_WORDS} --buildfreqs"
      Rake::Task["ultrasphinx:index"].invoke
      tmpfile = "/tmp/custom_words.txt"
      words = []
      say "filtering"
      File.open(Ultrasphinx::STOPWORDS_PATH).each do |line|
        if line =~ /^([^\s\d_]{4,}) (\d+)/
          # XXX should be configurable
          words << $1 if $2.to_i > 40 
          # ideally we would also skip words within X edit distance of a correction
          # by aspell-en, in order to not add typos to the dictionary
        end
      end
      say "writing #{words.size} words"
      File.open(tmpfile, 'w').write(words.join("\n"))
      say "loading into aspell"
      system("aspell --lang=en create master custom.rws < #{tmpfile}")
    end
  end
  
end

# task shortcuts
namespace :us do
  task :start => ["ultrasphinx:daemon:start"]
  task :restart => ["ultrasphinx:daemon:restart"]
  task :stop => ["ultrasphinx:daemon:stop"]
  task :stat => ["ultrasphinx:daemon:status"]
  task :in => ["ultrasphinx:index"]
  task :spell => ["ultrasphinx:spelling:build"]
  task :conf => ["ultrasphinx:configure"]  
  task :boot => ["ultrasphinx:bootstrap"]  
end

# support methods

def ultrasphinx_daemon_pid
  open(open(Ultrasphinx::BASE_PATH).readlines.map do |line| 
    line[/^\s*pid_file\s*=\s*([^\s\#]*)/, 1]
  end.compact.first).readline.chomp rescue nil # XXX ridiculous
end

def ultrasphinx_daemon_running?
  if ultrasphinx_daemon_pid and `ps #{ultrasphinx_daemon_pid} | wc`.to_i > 1 
    true
  else
    # remove bogus lockfiles
    Dir[Ultrasphinx::INDEX_SETTINGS["path"] + "*spl"].each {|file| File.delete(file)}
    false
  end  
end

def say msg
  Ultrasphinx.say msg
end
  