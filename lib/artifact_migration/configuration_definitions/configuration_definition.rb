=begin

	The ConfigurationDefinintion class holds all of the configuration options.  There should be one instance for the source and one for the target.

=end

require 'active_support/inflector'

module ArtifactMigration
	class ConfigurationDefinition		
		attr_reader :migration_types
		attr_reader :migrate_attachments_flag
		
		def initialize
			@migration_types = [].to_set
		end
				
		def migrate_type(type)
			@migration_types << type
		end
		
		def migrate_typical_types
			ArtifactMigration::TYPICAL_TYPES.each { |t| migrate_type t }
		end
		
		def migrate_all_types
			ArtifactMigration::VALID_TYPES.each { |t| migrate_type t }
		end
		
		def migrate_attachments
			@migrate_attachments_flag = true
		end
	end
end