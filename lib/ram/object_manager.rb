require 'active_support/inflector'
require 'rally_rest_api'
require 'yaml'

module ArtifactMigration
	class ObjectManager
		attr_reader :rally_datasource
		attr_reader :workspace
		
		def initialize(rally_datasource, workspace)
			@rally_datasource = rally_datasource
			@workspace = workspace
			
			@connected = false
			verify_connected_to_rally
		end
		
		def get_mapped_artifact(old_id)
			return nil unless verify_connected_to_rally
			return nil unless old_id
			Logger.debug "ObjectManager::get_mapped_artifact - Begin"
			
			stmap = ObjectIdMap.find_by_source_id old_id.to_i
			return nil unless stmap
			
			Logger.debug "ObjectManager::get_mapped_artifact - #{old_id} maps to #{stmap.target_id}"
			cache = ObjectCache.find_by_object_i_d stmap.target_id
			cached_object = YAML.load(cache.cached_object) if cache
			
			if cached_object
				#Logger.debug "Cache hit!"
				rro = RestObject.new
				cached_object[0] = rally_datasource
				rro.marshal_load cached_object
				artifact = rro
			else
				#Logger.debug "Cache miss..."
				klass_type = ObjectTypeMap.find_by_object_i_d old_id
				res = rally_datasource.find(klass_type.artifact_type.to_sym, :workspace => workspace) { equal :object_i_d, stmap.target_id.to_i }
				artifact = res.first if res
			  ObjectCache.create(:object_i_d => artifact.object_i_d, :cached_object => artifact.marshal_dump.to_yaml)
			end
			
			artifact
		end
		
		def map_artifact(old_oid, new_oid, artifact)
			unless ObjectIdMap.find_by_source_id(old_oid)
			  ObjectIdMap.create(:source_id => old_oid.to_i, :target_id => new_oid.to_i)
			  ObjectCache.create(:object_i_d => new_oid, :cached_object => artifact.marshal_dump.to_yaml)
			end
		end
		
		
		protected
		def verify_connected_to_rally
			return true if @connected
			
			#Logger.debug "ObjectManager::verify_connected_to_rally - !rally_datasource.nil? = #{!rally_datasource.nil?}"
			conn = !rally_datasource.nil?
			#Logger.debug "ObjectManager::verify_connected_to_rally - !rally_datasource.user.nil? = #{!rally_datasource.nil?}"
			conn = !rally_datasource.user.nil? if conn
			
			@connected = conn
			
			Logger.debug "ObjectManager::verify_connected_to_rally - #{@connected}"
			@connected
		end
	end
end