=begin

	The ConfigurationDefinintion class holds all of the configuration options.  There should be one instance for the source and one for the target.

=end

require 'active_support/inflector'

module ArtifactMigration
	class RallyConfigurationDefinition		
		attr_accessor :username
		attr_accessor :password
		attr_accessor :server
		attr_accessor :workspace_oid
		attr_accessor :project_scope_up
		attr_accessor :project_scope_down
		
		attr_reader :project_oids
		attr_reader :project_mapping
		attr_reader :ignore_fields
		attr_reader :field_mapping
		attr_reader :username_mapping
		
		def initialize
			@project_oids = [].to_set
			@project_mapping = {}
			
			@username_mapping = {}
			@username_mapping_regex = //
			@loggers = []

			@ignore_fields = {}
			@field_mapping = {}
		end
				
		def ignore_field(type, field_name)
			@ignore_fields[type] ||= [].to_set
			@ignore_fields[type] << field_name.to_s.underscore.to_sym if field_name && !([:object_i_d, :name].include? field_name.to_s.underscore.to_sym)
		end
		
		def map_field(type, options = {})
			@field_mapping[type] ||= {}
			
			@field_mapping[type][options[:from].to_s.underscore.to_sym] = options[:to].to_s.underscore.to_sym
		end
		
		def add_project_oid(value)
			@project_oids << value.to_i
		end
				
		def map_project_oid(options = {})
			@project_mapping[options[:from]] = options[:to]
		end
	end
end