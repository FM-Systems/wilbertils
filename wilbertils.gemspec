# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'wilbertils/version'

Gem::Specification.new do |spec|
  spec.name          = "wilbertils"
  spec.version       = Wilbertils::VERSION
  spec.authors       = ["David Clarke"]
  spec.email         = ["terrorhawks@gmail.com"]
  spec.description   = "Utils for Wilberforce projects"
  spec.summary       = "All the good stuff in one place to keep it DRY"
  spec.homepage      = ""
  spec.license       = "MIT"

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.3"
  spec.add_development_dependency "rspec"
  spec.add_development_dependency "rake"
  spec.add_runtime_dependency "log4r", "~> 1.1.10"
  spec.add_runtime_dependency "statsd-ruby"
  spec.add_runtime_dependency 'airbrake', '3.1.14'
  spec.add_runtime_dependency 'sucker_punch', '1.0.2'
  spec.add_runtime_dependency 'activesupport'

end

