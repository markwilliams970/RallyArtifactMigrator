=begin

	The ConfigurationDefinintion class holds all of the configuration options.  There should be one instance for the source and one for the target.

=end

require 'active_support/inflector'
require 'yaml'
require 'csv'

CSVImple = CSV

module ArtifactMigration
	class ConfigurationDefinition
		attr_accessor :username
		attr_accessor :password
		attr_accessor :server
		attr_accessor :workspace_oid
        attr_accessor :workspace_name
		attr_accessor :project_scope_up
		attr_accessor :project_scope_down
		attr_accessor :default_username
		attr_accessor :version
		
		attr_accessor :update_existing
		
		attr_accessor :default_project_oid
		
		attr_reader :migration_types
		attr_reader :project_oids
		attr_reader :project_mapping
		attr_reader :ignore_fields
		attr_reader :field_mapping
		attr_reader :username_mapping
		attr_reader :artifact_mapping
		attr_reader :migrate_attachments_flag
		attr_reader :migrate_projects_flag
		attr_reader :migrate_child_projects_flag
		attr_reader :migrate_project_permissions_flag

		def initialize
			@project_oids = [].to_set
			@migration_types = [].to_set
			@project_mapping = {}
			@version = ArtifactMigration::RALLY_API_VERSION
			
			@username_mapping = {}
			@username_mapping_regex = //
			@loggers = []

			@ignore_fields = {}
			@field_mapping = {}
			@migrate_projects_flag = false
			@default_project_oid = nil
			@artifact_mapping = {}
		end
				
		def ignore_field(type, field_name)
			@ignore_fields[type] = [].to_set unless @ignore_fields.has_key? type
			@ignore_fields[type] << field_name.to_s.underscore.to_sym if field_name && !([:object_i_d, :name].include? field_name.to_s.underscore.to_sym)
		end
		
		def map_field(type, options = {})
			@field_mapping[type] = {} unless @field_mapping.has_key type
			
			@field_mapping[type][options[:from].to_s.underscore.to_sym] = options[:to].to_s.underscore.to_sym
		end
		
		def add_project_oid(value)
			@project_oids << value.to_i
		end
		
		def migrate_type(type)
			@migration_types << type
		end

		def dont_migrate_type(type)
			@migration_types = @migration_types - type
		end
		
		def migrate_ee_types
			ArtifactMigration::EE_TYPES.each { |t| migrate_type t }
		end
		
		def migrate_ue_types
			ArtifactMigration::UE_TYPES.each { |t| migrate_type t }
		end
		
		def migrate_attachments
			@migrate_attachments_flag = true
		end
		
		def migrate_projects
		  @migrate_projects_flag = true
		end

		def migrate_child_projects
			@migrate_child_projects_flag = true
		end

		def migrate_project_permissions
			@migrate_project_permissions_flag = true
		end
		
		def map_project_oid(options = {})
			@project_mapping[options[:from]] = options[:to]
		end
		
		def map_username(options = {})
			@username_mapping[options[:from]] = options[:to]
		end
		
		def map_username_by_regex(options = {})
		end

		def map_artifact(options = {})
			@artifact_mapping[options[:from]] = { :type => options[:type], :oid => options[:to] }
		end
		
		def map_username_by_csv(options = {})
			from_column = options[:from]
			to_column = options[:to]
			user_header_row = !from_column.nil? && !to_column.nil? && from_column.class == String
			
			CSVImpl.foreach(options[:file], :headers => user_header_row) do |user|
				@username_mapping[user[from_column]] = user[to_column]
			end
		end

		def map_projects_by_yaml(filename)
			YAML.load(File.open filename).each { |k, v| map_project_id :from => k, :to => v }
		end
	end
end
