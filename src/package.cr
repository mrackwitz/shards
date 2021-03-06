require "./resolvers/*"
require "./helpers/versions"

module Shards
  class Package
    include Helpers::Versions

    getter :requirements

    def initialize(@dependency, @update_cache = false)
      @requirements = [] of String
    end

    def name
      @dependency.name
    end

    def version
      if matching_versions.any?
        matching_versions.first
      else
        raise Conflict.new(self)
      end
    end

    def matching_versions
      resolve_versions(available_versions, requirements)
    end

    def spec
      resolver.spec(version)
    end

    def matches?(commit)
      resolver = self.resolver

      if resolver.responds_to?(:matches?)
        resolver.matches?(commit)
      else
        raise LockConflict.new("wrong resolver")
      end
    end

    def installed?(version = nil, loose = false)
      if spec = resolver.installed_spec
        version ||= spec.version

        if resolver.installed_commit_hash == version
          true
        elsif loose
          matching_versions.includes?(version)
        else
          self.version == version
        end
      else
        false
      end
    end

    def install(version = nil)
      resolver.install(version || self.version)
      resolver.run_script("postinstall")
    end

    def to_lock(io : IO)
      key = resolver.class.key
      io << "    " << key << ": " << @dependency[key] << "\n"

      if @dependency.refs || !(version =~ RELEASE_VERSION)
        io << "    commit: " << resolver.installed_commit_hash.to_s << "\n"
      else
        io << "    version: " << version << "\n"
      end
    end

    def resolver
      @resolver ||= Shards.find_resolver(@dependency, update_cache: @update_cache)
    end

    private def available_versions
      @available_versions ||= resolver.available_versions
    end
  end

  class Set < Array(Package)
    def initialize(@update_cache = true)
      super()
    end

    def add(dependency)
      package = find { |package| package.name == dependency.name }

      unless package
        package = Package.new(dependency, update_cache: @update_cache)
        self << package
      end

      package.requirements << dependency.version
      package
    end
  end
end
