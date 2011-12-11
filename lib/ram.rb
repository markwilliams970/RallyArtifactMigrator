#!/usr/bin/env ruby

require 'active_support'
require 'active_support/inflector'
require 'rally_rest_api'
require 'active_record'

module ArtifactMigration
	extend ActiveSupport::Autoload
	
	EE_TYPES = [:tag, :release, :iteration, :hierarchical_requirement, :defect, :defect_suite, :test_case, :test_case_step, :test_case_result, :task].to_set
	UE_TYPES = [:test_set, :test_folder, :portfolio_item].to_set + ArtifactMigration::EE_TYPES
	ARTIFACT_TYPES = [:portfolio_item, :hierarchical_requirement, :defect, :defect_suite, :test_case, :task]

	RALLY_API_VERSION = "1.29"
	
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
		autoload :ProjectExporter
		autoload :ProgressBar
		autoload :CLI
		autoload :ObjectManager
		
		autoload_under 'models' do
			autoload :ImportTransactionLog
			autoload :IssueTransactionLog
			autoload :ObjectCache
			autoload :ObjectIdMap
			autoload :ObjectTypeMap
			autoload :RallyArtifacts
		end
			
	end
end

require 'artifact_migration/bootstrap'