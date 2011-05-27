=begin

	The ConfigurationDefinintion class holds all of the configuration options.  There should be one instance for the source and one for the target.

=end

require 'active_support/inflector'

module ArtifactMigration
	class SourceConfigurationDefinition	< ConfigurationDefinition
		attr_reader :rally
		
		attr_accessor :vendor
		
		def initialize
			@rally = RallyConfigurationDefinition.new
			@vendor = :rally
		end
				
		def ignore_field(type, field_name)
			@ignore_fields[type] ||= [].to_set
			@ignore_fields[type] << field_name.to_s.underscore.to_sym if field_name && !([:object_i_d, :name].include? field_name.to_s.underscore.to_sym)
		end
		
		def map_project_oid(options = {})
			@project_mapping[options[:from]] = options[:to]
		end
		
		def map_username(options = {})
			@username_mapping[options[:from]] = options[:to]
		end
	end
end