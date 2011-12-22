=begin

The Configuration class is stores all the configuration information for export and import

=end

module ArtifactMigration
	class Configuration
		attr_reader :loggers
		attr_reader :source_config
		attr_reader :target_config
		
		#
		# Begins the configuration block in the config file
		#
		def self.define
			yield Configuration.singleton if block_given?
		end
		
		#
		# There can only be one configuration instance
		#
		def self.singleton
			@@singleton ||= Configuration.new
			
			@@singleton
		end
		
		#
		# Defines the source configuration block in the config file
		#
		def source
			@source_config ||= ConfigurationDefinition.new
			yield @source_config if block_given?
		end
		
		#
		# Defines the target configuration block in the config file
		#
		def target
			@target_config ||= ConfigurationDefinition.new
			yield @target_config if block_given?
		end
		
		def add_logger(logger)
			@loggers << logger
		end
		
		def clear_loggers
		  @loggers = []
	  end
		
		def connect_to_database(dbfile)
		  DatabaseConnection.connect_to_database dbfile
	  end
		
	protected
		def initialize
			@loggers = []
		end
	
	end
end