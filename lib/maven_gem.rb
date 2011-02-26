$:.unshift(File.dirname(__FILE__)) unless $:.include?(File.dirname(__FILE__)) || $:.include?(File.expand_path(File.dirname(__FILE__)))

require 'maven_gem/xml_utils'
require 'maven_gem/pom_spec'
require 'maven_gem/pom_fetcher'
require 'rubygems'
require 'rubygems/gem_runner'

module MavenGem

  @@default_maven_base_url = "http://mirrors.ibiblio.org/pub/mirrors/maven2"

  def self.install(group, artifact = nil, version = nil, repository=nil, properties={})
    gem = build(group, artifact, version, repository, properties)
    begin
      Gem::GemRunner.new.run(["install", gem])
    rescue Gem::SystemExitException => e
      # its pretty lame that Gem raises this expection.  must be necessary
    end
  ensure
    FileUtils.rm_f(gem) if gem
  end

  def self.build(group, artifact = nil, version = nil, repository=nil, properties={})
    repository = repository ? repository : @@default_maven_base_url
    gem = if artifact
      url = MavenGem::PomSpec.to_maven_url(group, artifact, version, repository)
      MavenGem::PomSpec.build(url, repository, properties)
    else
      MavenGem::PomSpec.build(group, repository, properties)
    end
  end
end
