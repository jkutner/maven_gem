require 'ostruct'
require 'fileutils'
require 'yaml'

module MavenGem
  class PomSpec
    extend MavenGem::XmlUtils

    @@properties = {}

    def self.build(location, maven_base_url, properties={})
      @@properties.merge!(properties)
      pom_doc = MavenGem::PomFetcher.fetch(location)
      pom = MavenGem::PomSpec.parse_pom(pom_doc, maven_base_url)
      spec = MavenGem::PomSpec.generate_spec(pom)
      MavenGem::PomSpec.create_gem(spec, pom)
    end

    # Unless the maven version string is a valid Gem version string create a substitute
    # gem version string by dividing the maven version string into it's numeric elements
    # and joining them back together with '.' characters.
    # 
    # The string 'alpha' in a maven version string is converted to '0'.
    # The string 'beta' in a maven version string is converted to '1'.
    # 
    # In general gem versions strings need to either be an Integer or start with a 
    # digit and a '.'.
    # 
    # For example the flying saucer core-renderer jar that uses itext to generate a
    # pdf from styled xhtml input has a version string of "R8pre2". 
    # 
    # Installing this jar:
    # 
    #   jruby -S gem maven org/xhtmlrenderer core-renderer R8pre2
    # 
    # results in:
    # 
    #   Successfully installed core-renderer-8.2-java
    #   1 gem installed
    # 
    #   jruby -S gem list core-renderer
    #   
    #   *** LOCAL GEMS ***
    #   
    #   core-renderer (8.2)
    # 
    # In addition the following constants are created in the new maven gem:
    # 
    #   CoreRenderer::VERSION         # => "8.2"
    #   CoreRenderer::MAVEN_VERSION   # => "R8pre2"
    # 
    # TODO: Parse maven version number modifiers, i.e: [1.5,) [1.5,1.6], (,1.5]
    def self.maven_to_gem_version(maven_version)
      maven_version = parse_property(maven_version)
      maven_version = maven_version.gsub(/alpha/, '0')
      maven_version = maven_version.gsub(/beta/, '1')
      maven_numbers = maven_version.gsub(/\D+/, '.').split('.').find_all { |i| i.length > 0 }
      if maven_numbers.empty?
        '0.0.0'
      else
        maven_numbers.join('.')
      end
    end

    def self.is_property?(s)
      !(s.match(/\A\$\{/).nil?)
    end

    def self.parse_property(property)
      if is_property?(property)
        property_name = property.gsub(/\A\$\{/, '').gsub(/\}\z/, '')
        property = @@properties[property_name]
        raise "No value found for property: ${#{property_name}}" if property.nil?
      end
      property
    end

    def self.parse_pom(pom_doc, maven_base_url, options = {})
      puts "Processing POM" if options[:verbose]

      pom = OpenStruct.new
      document = REXML::Document.new(pom_doc, maven_base_url)

#      pom.parent = OpenStruct.new
      pom.parent_group = xpath_parent_group(document)
      pom.parent_artifact = xpath_parent_artifact(document)
      pom.parent_version = xpath_parent_version(document)

      if pom.parent_version
        parent_pom_path = to_maven_path(pom.parent_group, pom.parent_artifact, pom.parent_version)
        parent_pom_location ="#{maven_base_url}/#{parent_pom_path}"
        parent_pom_doc = MavenGem::PomFetcher.fetch(parent_pom_location)
        pom.parent = parse_pom(parent_pom_doc, maven_base_url)

        @@properties['parent.version'] = pom.parent_version
      end

      pom.group = xpath_group(document)
      pom.artifact = xpath_text(document, '/project/artifactId')
      pom.maven_version = parse_property(xpath_text(document, '/project/version') || xpath_text(document, '/project/parent/version'))
      pom.version = maven_to_gem_version(pom.maven_version)

      @@properties.merge! xpath_properties(document)
      @@properties['project.groupId'] = pom.group
      @@properties['project.artifactId'] = pom.artifact
      @@properties['project.version'] = pom.maven_version

      pom.description = xpath_text(document, '/project/description')
      pom.url = xpath_text(document, '/project/url')
      pom.dependencies = xpath_dependencies(document)
      pom.authors = xpath_authors(document)

      pom.name = maven_to_gem_name(pom.group, pom.artifact)
      pom.lib_name = "#{pom.artifact}.rb"
      pom.gem_name = "#{pom.name}-#{pom.version}"
      pom.jar_file = "#{pom.artifact}-#{pom.maven_version}.jar"
      pom.remote_dir = to_maven_path(pom.group, pom.artifact, pom.maven_version)
      pom.remote_jar_url = "#{maven_base_url}/#{pom.remote_dir}/#{pom.jar_file}"
      pom.gem_file = "#{pom.gem_name}-java.gem"
      pom
    end

    def self.generate_spec(pom, options = {})
      spec = Gem::Specification.new do |specification|
        specification.platform = "java"
        specification.version = pom.version
        specification.name = pom.name
        pom.dependencies.each {|dep| specification.dependencies << dep}
        specification.authors = pom.authors
        specification.description = pom.description
        specification.homepage = pom.url

        specification.files = ["lib/#{pom.lib_name}", "lib/#{pom.jar_file}"]
      end
    end

    def self.create_gem(spec, pom, options = {})
      gem = create_files(spec, pom, options)
    end

    def self.to_maven_url(group, artifact, version, maven_base_url)
      "#{maven_base_url}/#{self.to_maven_pom(group, artifact, version)}"
    end

    private

    def self.to_maven_path(group, artifact, version)
      "#{group.gsub('.', '/')}/#{artifact}/#{version}"
    end

    def self.to_maven_pom(group, artifact, version)
      "#{to_maven_path(group, artifact, version)}/#{artifact}-#{version}.pom"
    end

    def self.maven_to_gem_name(group, artifact, options = {})
      "#{parse_property(group)}.#{parse_property(artifact)}"
    end

    def self.create_files(specification, pom, options = {})
      gem_dir = create_tmp_directories(pom, options)

      ruby_file_contents(gem_dir, pom, options)
      jar_file_contents(gem_dir, pom, options)
      metadata_contents(gem_dir, specification, pom, options)
      gem_contents(gem_dir, pom, options)
    ensure
      FileUtils.rm_r(gem_dir) if gem_dir
    end

    def self.create_tmp_directories(pom, options = {})
      gem_dir = "/tmp/#{pom.name}.#{$$}"
      puts "Using #{gem_dir} work dir" if options[:verbose]
      unless File.exist?(gem_dir)
        FileUtils.mkdir_p(gem_dir)
        FileUtils.mkdir_p("#{gem_dir}/lib")
      end
      gem_dir
    end

    def self.ruby_file_contents(gem_dir, pom, options = {})
      titleized_classname = pom.artifact.split('-').collect { |e| e.capitalize }.join
      ruby_file_content = <<HEREDOC
module #{titleized_classname}
  VERSION = '#{pom.version}'
  MAVEN_VERSION = '#{pom.maven_version}'
end
begin
  require 'java'
  require File.dirname(__FILE__) + '/#{pom.jar_file}'
rescue LoadError
  puts 'JAR-based gems require JRuby to load. Please visit www.jruby.org.'
  raise
end
HEREDOC

      ruby_file = "#{gem_dir}/lib/#{pom.lib_name}"
      puts "Writing #{ruby_file}" if options[:verbose]
      File.open(ruby_file, 'w') do |file|
        file.write(ruby_file_content)
      end
    end

    def self.jar_file_contents(gem_dir, pom, options = {})
      puts "Fetching #{pom.remote_jar_url}" if options[:verbose]
      uri = URI.parse(pom.remote_jar_url)
      jar_contents = Net::HTTP.get(uri)
      File.open("#{gem_dir}/lib/#{pom.jar_file}", 'w') {|f| f.write(jar_contents)}
    end

    def self.metadata_contents(gem_dir, spec, pom, options = {})
      metadata_file = "#{gem_dir}/metadata"
      puts "Writing #{metadata_file}" if options[:verbose]
      File.open(metadata_file, 'w') do |file|
        file.write(spec.to_yaml)
      end
    end

    def self.gem_contents(gem_dir, pom, options = {})
      puts "Building #{pom.gem_file}" if options[:verbose]
      Dir.chdir(gem_dir) do
        fail unless
          system('gzip metadata') and
          system('tar czf data.tar.gz lib/*') and
          system("tar cf ../#{pom.gem_file} data.tar.gz metadata.gz")
      end

      File.expand_path("../#{pom.gem_file}", gem_dir) # return the gem file
    end
  end
end
