require File.dirname(__FILE__) + '/../spec_helper'
require 'fileutils'

describe MavenGem::PomSpec do

  before(:each) do
    ant_path = File.join(FIXTURES, 'ant.pom')
    @pom = MavenGem::PomFetcher.fetch(ant_path)
  end

  describe "maven_to_gem_version" do
    it "represents alpha keyword as 0" do
      MavenGem::PomSpec.maven_to_gem_version("1.0-alpha").should == '1.0.0'
    end

    it "represents beta keyword as 1" do
      MavenGem::PomSpec.maven_to_gem_version("1.0-beta").should == '1.0.1'
    end

    it "removes non numeric characters from gem version" do
      MavenGem::PomSpec.maven_to_gem_version("1.0.0-SNAPSHOT").should == '1.0.0'
    end
  end

  describe "parse_pom" do
    it "keeps the groupId as group" do
      ant_pom.group.should == 'ant'
    end

    it "keeps the artifactId as artifact" do
      ant_pom.artifact.should == 'ant'
    end

    it "keeps the original version as maven_version" do
      ant_pom.maven_version.should == '1.6.5'
      with_non_numeric_version = @pom.gsub(/<version>1.6.5<\/version>/, '<version>1.6.6-SNAPSHOT</version>')
      MavenGem::PomSpec.parse_pom(with_non_numeric_version, "http://foobar.com").maven_version.should == '1.6.6-SNAPSHOT'
    end

    it "keeps the version number as version" do
      ant_pom.version.should == '1.6.5'
      with_non_numeric_version = @pom.gsub(/<version>1.6.5<\/version>/, '<version>1.6.6-SNAPSHOT</version>')
      MavenGem::PomSpec.parse_pom(with_non_numeric_version, "http://foobar.com").version.should == '1.6.6'
    end

    it "keeps the pom description as description" do
      ant_pom.description.should == 'Apache Ant'
    end

    it "keeps the project url as url" do
      ant_pom.url.should == 'http://ant.apache.org'
    end

    it "doesn't add dependencies when the node doesn't exist" do
      hudson_rake_pom.dependencies.should be_empty
    end

    it "doesn't add dependencies when are optional" do
      ant_pom.dependencies.should be_empty
    end

    it "adds dependencies when aren't optional" do
      pom = pom_with_dependencies
      pom.dependencies.map {|d| d.name}.should include('xerces.xercesImpl')
    end

    it "adds dependencies with formatted gem version" do
      pom = pom_with_dependencies
      pom.dependencies.map {|d| d.requirement.as_list }.flatten.should include('= 2.6.2')
    end

    it "adds dependencies without version" do
      @pom.gsub(/<optional>true<\/optional>/, '')
      @pom.gsub(/<(version)>.+<\/$1>/, '')
      pom_spec = MavenGem::PomSpec.parse_pom(@pom, "http://foobar.com")

      pom_spec.dependencies.each {|d| d.requirement.as_list.should be_empty}
    end

    it "doesn't add authors when the node doesn't exist" do
     ant_pom.authors.should be_empty
    end

    it "uses parent groupId when groupId node doesn't exist" do
      pom = hudson_rake_pom
      pom.group.should == 'org.jvnet.hudson.plugins'
    end

    it "adds authors when developers node is present" do
      pom = hudson_rake_pom

      pom.authors.should include('David Calavera')
    end

    it "uses group and artifact to create the specification name" do
      ant_pom.name.should == 'ant.ant'
      hudson_rake_pom.name.should == 'org.jvnet.hudson.plugins.rake'
    end

    it "uses group, artifact and version to create library and jar attributes" do
      pom = ant_pom
      pom.lib_name.should == 'ant.rb'
      pom.gem_name.should == 'ant.ant-1.6.5'
      pom.jar_file.should == 'ant-1.6.5.jar'
      pom.remote_dir.should == 'ant/ant/1.6.5'
      pom.remote_jar_url.should == "http://mirrors.ibiblio.org/pub/mirrors/maven2/ant/ant/1.6.5/ant-1.6.5.jar"
      pom.gem_file.should == 'ant.ant-1.6.5-java.gem'

      with_non_numeric_version = @pom.gsub(/<version>1.6.5<\/version>/, '<version>1.6.6-SNAPSHOT</version>')
      pom = MavenGem::PomSpec.parse_pom(with_non_numeric_version, "http://foobar.com")
      pom.jar_file.should == 'ant-1.6.6-SNAPSHOT.jar'
      pom.gem_file.should == 'ant.ant-1.6.6-java.gem'
    end

    it "uses the version from the parent when its version doesn't exit" do
      pom = MavenGem::PomFetcher.fetch(File.join(FIXTURES, 'hudson-rake.pom'))
      pom_without_version = pom.gsub(/<version>1.7-SNAPSHOT<\/version>/, '')

      pom_spec = MavenGem::PomSpec.parse_pom(pom_without_version, "http://foobar.com")
      pom_spec.version.should == '1.319'
    end
  end

  describe "generate_spec" do
    it "generates a speficication object from a pom file" do
      spec = MavenGem::PomSpec.generate_spec(ant_pom)
      spec.should be_kind_of(Gem::Specification)
    end

    it "uses the pom version and name in the specification" do
      pom = ant_pom
      spec = MavenGem::PomSpec.generate_spec(pom)
      spec.name.should == pom.name
      spec.version.version.should == pom.version
    end

    it "uses the pom artifact to add a library file" do
      pom = ant_pom
      spec = MavenGem::PomSpec.generate_spec(pom)
      spec.lib_files.should include("lib/#{pom.artifact}.rb")
    end
  end

  describe "create_gem" do
    it "creates the gem file" do
      pending # still need to figure out how to get a handle to 
      begin
        pom = ant_pom
        spec = MavenGem::PomSpec.generate_spec(pom)
        lambda {
          MavenGem::PomSpec.create_gem(spec, pom)
        }.should_not raise_error
        File.exist?('ant.ant-1.6.5-java.gem').should be_true
      ensure
        FileUtils.rm_f('ant.ant-1.6.5-java.gem')
      end
    end

    it "creates a ruby module with the artifact name" do
      within_tmp_directory do |tmp_dir|
        MavenGem::PomSpec.__send__(:ruby_file_contents, tmp_dir, ant_pom)
        File.exist?(tmp_dir + '/lib/ant.rb').should be_true
        lib_file = File.read(tmp_dir + '/lib/ant.rb')
        lib_file.should include('module Ant')
      end
    end

    it "creates a ruby module with the maven version as a constant" do
      within_tmp_directory do |tmp_dir|
        MavenGem::PomSpec.__send__(:ruby_file_contents, tmp_dir, hudson_rake_pom)
        File.exist?(tmp_dir + '/lib/rake.rb').should be_true
        lib_file = File.read(tmp_dir + '/lib/rake.rb')
        lib_file.should include("VERSION = '1.7'")
        lib_file.should include("MAVEN_VERSION = '1.7-SNAPSHOT'")
      end
    end
  end

  describe "to_maven_url" do
    it "creates an artifact jar url from group, artifact and version" do
      MavenGem::PomSpec.to_maven_url('ant', 'ant', '1.6.5', "http://mirrors.ibiblio.org/pub/mirrors/maven2").should ==
        "http://mirrors.ibiblio.org/pub/mirrors/maven2/ant/ant/1.6.5/ant-1.6.5.pom"
    end

    it "creates an artifact jar url from group, artifact, version and repo" do
      MavenGem::PomSpec.to_maven_url('ant', 'ant', '1.6.5', 'http://foobar.com').should ==
        "http://foobar.com/ant/ant/1.6.5/ant-1.6.5.pom"
    end
  end

  def pom_with_dependencies
    with_deps = @pom.gsub(/<optional>true<\/optional>/, '')
    MavenGem::PomSpec.parse_pom(with_deps, "http://foobar.com")
  end

  def hudson_rake_pom
    pom_url = File.join(FIXTURES, 'hudson-rake.pom')
    pom = MavenGem::PomFetcher.fetch(File.join(FIXTURES, 'hudson-rake.pom'))
    MavenGem::PomSpec.parse_pom(pom, pom_url)
  end

  def ant_pom
    MavenGem::PomSpec.parse_pom(@pom, "http://mirrors.ibiblio.org/pub/mirrors/maven2")
  end

  def within_tmp_directory
    tmp_dir = '/tmp/maven_gem_spec'
    begin
      FileUtils.mkdir_p(tmp_dir + '/lib')

      yield(tmp_dir)
    ensure
      FileUtils.rm_r(tmp_dir)
    end
  end
end
