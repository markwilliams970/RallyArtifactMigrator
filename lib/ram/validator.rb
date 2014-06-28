require 'active_support/inflector'
require 'rainbow'
require 'events'

module ArtifactMigration
	class Validator
		extend Events::Emitter
		
		def self.verify
			@@log = ArtifactMigration::Logger
			success = true
			
			emit :verify_source
			success = verify_source_config

 			if success
				emit :verify_target
				success = verify_target_config
			end
			
			sc = Configuration.singleton.source_config
			tc = Configuration.singleton.target_config
			
			success &&= assert("Set of artifacts to import is a subset of the artifacts to export") { tc.migration_types.subset? sc.migration_types }
			
			success
		end
		
		protected
		def self.assert(*args)
			value = true
			
			if block_given?
				value = yield
				
				emit :validation, args[0].to_s, value
				@@log.info("#{args[0].to_s}", value == true ? "YES".color(:green) : "NO".color(:red)) if args
			end
			
			value
		end
		
		def self.verify_source_config
			@@log.info("=========Validating Source Configuration=========")
			config = Configuration.singleton.source_config

			valid = verify_connection config
			return false unless valid

            headers                          = RallyAPI::CustomHttpHeader.new()
            headers.name                     = "Rally Artifact Migrator"
            headers.vendor                   = "Rally Software"
            headers.version                  = ArtifactMigration::VERSION

            rallyapi_config                  = {:base_url => config.server}
            rallyapi_config[:username]       = config.username
            rallyapi_config[:password]       = config.password
            rallyapi_config[:headers]        = headers #from RallyAPI::CustomHttpHeader.new()
            rallyapi_config[:version]        = ArtifactMigration::RALLY_API_VERSION

            source                           = RallyAPI::RallyRestJson.new(rallyapi_config)

			ws = ArtifactMigration::Helper.find_workspace(source, config.workspace_oid)
			@@log.info("---------Validating Project OIDs----------------")
			config.project_oids.each do |oid|
				p = ArtifactMigration::Helper.find_project(source, ws, oid)
				assert("Validating Project #{oid} exists") { !p.nil? }
			end
			
			valid
		end

		def self.verify_target_config
			@@log.info("=========Validating Target Configuration=========")
			config_t = Configuration.singleton.target_config
			config_s = Configuration.singleton.source_config
			valid = verify_connection config_t
			return false unless valid

            headers                                 = RallyAPI::CustomHttpHeader.new()
            headers.name                            = "Rally Artifact Migrator"
            headers.vendor                          = "Rally Software"
            headers.version                         = ArtifactMigration::VERSION

            rallyapi_config_source                  = {:base_url => config_s.server}
            rallyapi_config_source[:username]       = config_s.username
            rallyapi_config_source[:password]       = config_s.password
            rallyapi_config_source[:headers]        = headers #from RallyAPI::CustomHttpHeader.new()
            rallyapi_config_source[:version]        = ArtifactMigration::RALLY_API_VERSION
            source                                  = RallyAPI::RallyRestJson.new(rallyapi_config_source)

            rallyapi_config_target                  = {:base_url => config_t.server}
            rallyapi_config_target[:username]       = config_t.username
            rallyapi_config_target[:password]       = config_t.password
            rallyapi_config_target[:headers]        = headers #from RallyAPI::CustomHttpHeader.new()
            rallyapi_config_target[:version]        = ArtifactMigration::RALLY_API_VERSION
            target                                  = RallyAPI::RallyRestJson.new(rallyapi_config_target)

			ws_s = ArtifactMigration::Helper.find_workspace(source, config_s.workspace_oid)
			ws_t = ArtifactMigration::Helper.find_workspace(target, config_t.workspace_oid)
			
			@@log.info("---------Validating Project Mapping-------------")
			config_t.project_mapping.each do |k, v|
				p_s = ArtifactMigration::Helper.find_project(source, ws_s, k)
				p_w = ArtifactMigration::Helper.find_project(target, ws_t, v)
				
				valid &&= assert("Validating Project #{k} maps to #{v}") { !(p_s.nil? || p_w.nil?) }
			end
			
			valid
		end
		
		def self.verify_connection(config)
			valid = assert("Validating username is defined") { !config.username.nil? }
			valid &&= assert("Validating password is defined") { !config.password.nil? }
			valid &&= assert("Validating server is defined") { !config.server.nil? }
			valid &&= assert("Validating workspace_oid is defined") { !config.workspace_oid.nil? }
			
			return false unless valid

            headers                          = RallyAPI::CustomHttpHeader.new()
            headers.name                     = "Rally Artifact Migrator"
            headers.vendor                   = "Rally Labs"
            headers.version                  = ArtifactMigration::VERSION

            rallyapi_config                  = {:base_url => config.server}
            rallyapi_config[:username]       = config.username
            rallyapi_config[:password]       = config.password
            rallyapi_config[:headers]        = headers #from RallyAPI::CustomHttpHeader.new()
            rallyapi_config[:version]        = ArtifactMigration::RALLY_API_VERSION

            @@rally                          = RallyAPI::RallyRestJson.new(rallyapi_config)

			ws = ArtifactMigration::Helper.find_workspace(@@rally, config.workspace_oid)
			valid &&= assert("Validating a workspace was found") { !ws.nil? }
			valid &&= assert("Validating supplied workspace_oid is valid") { ws["ObjectID"].to_i == config.workspace_oid } if valid

			config.migration_types.each do |type|
				valid &&= assert("Validating #{type.to_s.titleize} is a valid type") { ArtifactMigration::UE_TYPES.include? type }
			end
			
			valid
		end
		
		def self.verify_attribute_matches(source, target)
			
		end
		
		def verify_users_exist(source, target)
			
		end
	end
end