# -*- encoding: utf-8 -*-
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'capistrano-choique/version'

Gem::Specification.new do |gem|
  gem.name          = "capistrano-choique"
  gem.version       = Capistrano::Choique::VERSION
  gem.authors       = ["Christian Rodriguez"]
  gem.email         = ["car@cespi.unlp.edu.ar"]
  gem.description   = %q{Capistrano extension to deploy choique cms}
  gem.summary       = %q{capify choique CMS}
  gem.homepage      = ""

  gem.files         = `git ls-files`.split($/)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.require_paths = ["lib"]
  gem.add_dependency('capistrano','> 2.0')
end
