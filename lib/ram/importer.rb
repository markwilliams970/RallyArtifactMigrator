require 'active_support/inflector'
require 'rally_rest_api'
require 'json'
require 'net/http'
require 'net/https'
require 'events'

# This is a hack!
O_ALLOWED_TYPES = RallyRestAPI::ALLOWED_TYPES
class RallyRestAPI
  ALLOWED_TYPES = O_ALLOWED_TYPES + %w(portfolio_item type preliminary_estimate)
end

module ArtifactMigration
	class Importer
		extend Events::Emitter
		
		def self.run
		  DatabaseConnection.ensure_database_connection
		  
			prepare
			
			config = Configuration.singleton.target_config
			
			emit :begin_import
			
			ImportProjects.import_projects if config.migrate_projects_flag
			
			[:tag, :release, :iteration, :portfolio_item, :hierarchical_requirement, :test_folder, :test_case, :test_case_step, :test_set, :test_case_result, :defect, :defect_suite, :task].each do |type|
				Logger.info "Importing #{type.to_s.humanize}" if config.migration_types.include? type

				if config.migration_types.include? type
					emit :begin_type_import, type
					ImportArtifacts.import_type type 
					emit :end_type_import, type
				end

				ImportArtifacts.update_portfolio_parents if config.migration_types.include?(type) and type == :portfolio_item
				ImportArtifacts.update_story_parents if config.migration_types.include?(type) and type == :hierarchical_requirement
				ImportArtifacts.update_story_predecessors if config.migration_types.include?(type) and type == :hierarchical_requirement
				ImportArtifacts.update_defect_duplicates if config.migration_types.include?(type) and type == :defect
				ImportArtifacts.update_test_folder_parents if config.migration_types.include?(type) and type == :test_folder
			end
			
			ImportArtifacts.update_artifact_statuses
			
			if config.migrate_attachments_flag
        if config.version.to_f < 1.29
  			  ImportAttachments.import_attachments 
			  else
			    ImportAttachments.import_attachments_ws
		    end
		  end
			
			emit :end_import
		end
		
		def self.prepare      
			ArtifactMigration::Schema.create_transaction_log_schema
			ArtifactMigration::Schema.create_issue_log_schema			
			ArtifactMigration::Schema.create_object_id_map_schema			
			ArtifactMigration::Schema.create_object_cache_schema
			
			config = Configuration.singleton.target_config
			config.version = ArtifactMigration::RALLY_API_VERSION if config.version.nil?
			
			@@rally_ds = RallyRestAPI.new :username => config.username, :password => config.password, :base_url => config.server, :version => config.version, :http_headers => ArtifactMigration::INTEGRATION_HEADER
			@@workspace = Helper.find_workspace @@rally_ds, config.workspace_oid
			@@object_manager = ObjectManager.new @@rally_ds, @@workspace
			@@user_cache = {}

			ImportProjects.prepare
			ImportAttachments.prepare
			ImportArtifacts.prepare
		end
		
		def self.map_user(old_usr)
			config = Configuration.singleton.target_config
			return nil if old_usr.nil? || (old_usr == '')
			mapped_un = config.username_mapping.has_key?(old_usr) ? config.username_mapping[old_usr] : old_usr
			
			if mapped_un
				@@user_cache[mapped_un] = (@@rally_ds.find(:user, :workspace => @@workspace) { equal :user_name, mapped_un }).results.first if @@user_cache[mapped_un].nil?
				
				if @@user_cache.has_key? mapped_un
					return @@user_cache[mapped_un]
				elsif config.default_username
					mapped_un = config.default_username
					@@user_cache[mapped_un] = (@@rally_ds.find(:user, :workspace => @@workspace) { equal :user_name, mapped_un }).results.first if @@user_cache[mapped_un].nil?
					return @@user_cache[mapped_un]
				end
			end
			
			nil
		end
		
	end # Class
end # Module