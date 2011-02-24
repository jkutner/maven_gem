$:.unshift(File.dirname(__FILE__)) unless $:.include?(File.dirname(__FILE__)) || $:.include?(File.expand_path(File.dirname(__FILE__)))

require 'maven_gem/xml_utils'
require 'maven_gem/pom_spec'
require 'maven_gem/pom_fetcher'
require 'rubygems'
require 'rubygems/gem_runner'

module MavenGem
  # :properties won't be needed once we can get to the parent pom.xml
  def self.install(group, artifact = nil, version = nil, properties={}, repository={})
    gem = build(group, artifact, version, properties, repository)
    Gem::GemRunner.new.run(["install", gem])
  ensure
    FileUtils.rm_f(gem) if gem
  end

  def self.build(group, artifact = nil, version = nil, properties={}, repository={})
    gem = if artifact
      url = repository[:url] ?
          MavenGem::PomSpec.to_maven_url(group, artifact, version, repository[:url]) :
          MavenGem::PomSpec.to_maven_url(group, artifact, version)
      puts url
      MavenGem::PomSpec.build(url, properties, repository[:url])
    else
      repository[:url] ?
          MavenGem::PomSpec.build(group, properties, repository[:url]) :
          MavenGem::PomSpec.build(group, properties)
    end
  end
end
