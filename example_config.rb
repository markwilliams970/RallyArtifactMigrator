###############################################
#                                             #
# Rally Artifact Migration Configuration File #
#                                             #
###############################################

ArtifactMigration::Configuration.define do |config|
	config.source do |source|
		source.server = 'https://demo.rallydev.com/slm'
		source.username = "dan@acme.com"
		source.password = "AcmeUser"
		source.workspace_oid = 729424
		source.project_scope_up = false
		source.project_scope_down = false
		
		source.add_project_oid 729688
		source.add_project_oid 729701
		source.add_project_oid 729727
		
		source.migrate_all_types # Exports all types to the intermediate database
		source.migrate_attachments
		
		[:hierarchical_requirement, :defect, :defect_suite, :test_case].each { |type| source.ignore_field type, :package }
		
	end
	
	config.target do |target|
		target.server = 'https://demo.rallydev.com/slm'
		target.username = "dan@rallydev.com"
		target.password = "AcmeUser"
		target.workspace_oid = 11111111
		target.project_scope_up = true
		target.project_scope_down = true
		
		target.default_project_oid = 22222222
		target.map_project_oid :from => 729701, :to => 33333333
		target.map_project_oid :from => 729727, :to => 44444444
		
		target.migrate_typical_types # Typical types do not include RQM Types (Test Folder, Test Set, ect.)
		target.migrate_attachments
		

=begin
		Example of mapping a username.  Note that this must be done for each username
		target.map_username :from => 'dan@acme.com', :to => 'dan.theman@acme.com'

		Example for mapping a field:
		target.map_field :hierarchical_requirement, :from => :formatted_i_d, :to => :old_formatted_i_d
		
		Example of mapping all Artifact Formatted IDs:
		ArtifactMigration::ARTIFACT_TYPES.each do |type|
			target.map_field type, :from => :formatted_i_d, :to => :old_formatted_i_d
		end
=end
	end
	
	output = Logger.new STDOUT
	output.level = Logger::INFO
	
	#debug = Logger.new "debug.log"
	#debug.level = Logger::DEBUG
	
	config.add_logger output
	#config.add_logger debug
end
