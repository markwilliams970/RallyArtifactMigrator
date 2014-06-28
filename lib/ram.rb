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
	
	EE_TYPES = [:tag, :release, :iteration, :hierarchicalrequirement, :defect, :defectsuite, :testcase, :testcasestep, :testcaseresult, :task].to_set
	UE_TYPES = [:testset, :testfolder, :portfolioitem].to_set + ArtifactMigration::EE_TYPES
	ARTIFACT_TYPES = [:portfolioitem, :hierarchicalrequirement, :defect, :defectsuite, :testcase, :task]

	RALLY_API_VERSION = "1.43"

	VERSION = File.read(File.join(File.dirname(__FILE__), '..', 'VERSION'))
	
	INTEGRATION_HEADER = RallyAPI::CustomHttpHeader.new
	INTEGRATION_HEADER.vendor = "Rally Software"
	INTEGRATION_HEADER.name = "Rally Artifact Migrator"
	INTEGRATION_HEADER.version = ArtifactMigration::VERSION
	
end

#require 'artifact_migration/bootstrap'
