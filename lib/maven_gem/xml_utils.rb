require 'rexml/document'
require 'rexml/xpath'

module MavenGem
  module XmlUtils
    def xpath_text(element, node)
      first = REXML::XPath.first(element, node) and first.text
    end

    def xpath_dependencies(element)
      deps = REXML::XPath.first(element, '/project/dependencies')
      pom_dependencies = []

      if deps
        deps.elements.each do |dep|
          next if xpath_text(dep, 'optional') == 'true'

          dep_group = xpath_text(dep, 'groupId')
          dep_artifact = xpath_text(dep, 'artifactId')
          dep_version = xpath_text(dep, 'version')
          dep_scope = xpath_text(dep, 'scope')

          if !['test', 'provided'].include?(dep_scope)
            # TODO: Parse maven version number modifiers, i.e: [1.5,)
            pom_dependencies << if dep_version
              Gem::Dependency.new(maven_to_gem_name(dep_group, dep_artifact),
                "=#{maven_to_gem_version(dep_version)}")
            else
              Gem::Dependency.new(maven_to_gem_name(dep_group, dep_artifact))
            end
          end
        end
      end

      pom_dependencies
    end

    def xpath_authors(element)
      developers = REXML::XPath.first(element, 'project/developers')

      authors = if developers
        developers.elements.map do |el|
          xpath_text(el, 'name')
        end
      end || []
    end

    def xpath_group(element)
      xpath_text(element, '/project/groupId') || xpath_text(element, '/project/parent/groupId')
    end

    def xpath_parent_group(element)
      parent = REXML::XPath.first(element, 'parent')
      parent ? xpath_group(parent) : nil
    end

    def xpath_parent_artifact(element)
      parent = REXML::XPath.first(element, 'parent')
      parent ? xpath_text(element, 'parent/artifactId') : nil
    end

    def xpath_parent_version(element)
      parent = REXML::XPath.first(element, 'parent')
      parent ? xpath_text(element, 'parent/version') : nil
    end

    def xpath_properties(element)
      props = REXML::XPath.first(element, '/project/properties')
      pom_properties = {}

      if props
        props.elements.each do |prop|
          pom_properties[prop.name] = prop.text
        end
      end

      pom_properties
    end
  end
end
