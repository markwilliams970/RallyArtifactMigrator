#!/usr/bin/env ruby

require 'active_support'
require 'active_support/inflector'
require 'rally_rest_api'
require 'active_record'
require 'require_all'
require 'rally_api'

require_all "#{File.dirname(__FILE__)}/ram/**/*.rb"

module ArtifactMigration
	extend ActiveSupport::Autoload
	
	EE_TYPES = [:tag, :release, :iteration, :hierarchical_requirement, :defect, :defect_suite, :test_case, :test_case_step, :test_case_result, :task].to_set
	UE_TYPES = [:test_set, :test_folder, :portfolio_item].to_set + ArtifactMigration::EE_TYPES
	ARTIFACT_TYPES = [:portfolio_item, :hierarchical_requirement, :defect, :defect_suite, :test_case, :task]

	RALLY_API_VERSION = "1.36"
	
	VERSION = File.read(File.join(File.dirname(__FILE__), '..', 'VERSION'))
	
	INTEGRATION_HEADER = RallyAPI::CustomHttpHeader.new
	INTEGRATION_HEADER.vendor = "Rally Software"
	INTEGRATION_HEADER.name = "Rally Artifact Migrator"
	INTEGRATION_HEADER.version = ArtifactMigration::VERSION
	
end

#require 'artifact_migration/bootstrap'
