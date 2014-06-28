require 'rspec'
require_relative 'helper'

describe "RAM Export" do
  
  before :all do
    headers = RallyAPI::CustomHttpHeader.new()
    headers.name = "RAM"
    headers.vendor = "Rally Labs"
    headers.version = "0.4.2"
    
    config = {}
    config[:base_url]   = "https://demo-mountain.rallydev.com/slm"
    config[:username]   = "markwilliams@rallydev.com"
    config[:password]   = "RallyON!"
    config[:version]    = '1.43'
#    config[:workspace]  = "Workspace Name"
#    config[:project]    = "Project Name"
    config[:headers]    = headers #from RallyAPI::CustomHttpHeader.new()

    @rally = RallyAPI::RallyRestJson.new(config)
    
    ArtifactMigration::Configuration.define do |config|
    	config.source do |source|

            source.server = 'https://rally1.rallydev.com/slm'
            source.username = "markwilliams@rallydev.com"
            source.password = "RallyON!"
            source.workspace_oid = 722746
            source.project_scope_up = false
            source.project_scope_down = false
            source.version = "1.43"

            source.add_project_oid 723109
            source.add_project_oid 723135
            source.add_project_oid 723161

    		source.migrate_ue_types # Migrates all UE types (includes test sets, test folders and portfolio items)
    		source.migrate_attachments
    		source.migrate_projects

    		[:hierarchicalrequirement, :defect, :defectsuite, :testcase].each { |type| source.ignore_field type, :package }

    	end
    end
  end
  
  context ""
  
end
