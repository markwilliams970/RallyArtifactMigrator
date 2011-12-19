require 'rspec'
require_relative "helper"

describe "RAM Export" do
  
  before :all do
    headers = RallyAPI::CustomHttpHeader.new()
    headers.name = "RAM"
    headers.vendor = "Rally"
    headers.version = "0.4.2"
    
    config = {}
    config[:base_url]   = "https://preview.rallydev.com"
    config[:username]   = "cobrien@rallydev.com"
    config[:password]   = "Just4Rally"
    config[:version]    = '1.29'
#    config[:workspace]  = "Workspace Name"
#    config[:project]    = "Project Name"
    config[:headers]    = headers #from RallyAPI::CustomHttpHeader.new()

    @rally = RallyAPI::RallyRestJson.new(config)
    
    ArtifactMigration::Configuration.define do |config|
    	config.source do |source|
    		source.server = 'https://preview.rallydev.com/slm'
    		source.username = "cobrien@rallydev.com"
    		source.password = "Just4Rally"
    		source.workspace_oid = 729424
    		source.project_scope_up = false
    		source.project_scope_down = false
    		source.version = "1.29"

    		source.add_project_oid 729688
    		source.add_project_oid 729701
    		source.add_project_oid 729727

    		source.migrate_ue_types # Migrates all UE types (includes test sets, test folders and portfolio items)
    		source.migrate_attachments
    		source.migrate_projects

    		[:hierarchical_requirement, :defect, :defect_suite, :test_case].each { |type| source.ignore_field type, :package }

    	end
    end
  end
  
  context ""
  
end
