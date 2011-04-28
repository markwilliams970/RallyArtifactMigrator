#!/usr/bin/env ruby

require 'active_support'
require 'active_support/inflector'
require 'rally_rest_api'
require 'active_record'

module ArtifactMigration
	extend ActiveSupport::Autoload
	
	VALID_TYPES = [:tag, :release, :iteration, :hierarchical_requirement, :defect, :defect_suite, :test_folder, :test_set, :test_case, :test_case_step, :test_case_result, :task].to_set
	RQM_TYPES = [:test_set, :test_folder].to_set
	TYPICAL_TYPES = VALID_TYPES - RQM_TYPES
	ARTIFACT_TYPES = [:hierarchical_requirement, :defect, :defect_suite, :test_case, :task]
	
	RALLY_API_VERSION = "1.23"
	
	VERSION = File.read(File.join(File.dirname(__FILE__), '..', 'VERSION'))
	
	INTEGRATION_HEADER = CustomHttpHeader.new
	INTEGRATION_HEADER.vendor = "Rally Software"
	INTEGRATION_HEADER.name = "Rally Artifact Migrator"
	INTEGRATION_HEADER.version = ArtifactMigration::VERSION

	eager_autoload do
		autoload :ConfigurationDefinition
		autoload :Configuration
		autoload :Validator
		autoload :Runner
		autoload :Logger
		autoload :Helper
		autoload :Schema
		autoload :Importer
		autoload :Exporter
		autoload :ObjectManager
		
		autoload_under 'models' do
			autoload :ImportTransactionLog
			autoload :ObjectCache
			autoload :ObjectIdMap
			autoload :ObjectTypeMap
			autoload :RallyArtifacts
		end
		
	end
end

require 'artifact_migration/bootstrap'