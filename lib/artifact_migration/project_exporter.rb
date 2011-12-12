require 'rally_rest_api'
require 'events'


module ArtifactMigration
	class ProjectExporter
		extend Events::Emitter
		
		def self.prepare
		  @@projects = []
		  @@target_root = nil
		  
		  emit :project_export_preparation_complete
	  end
	  
	  def self.set_target_root_project(oid)
	    @@target_root = oid
	    
	    emit :project_target_root_set oid
    end
	  
	  def self.add_project_oid(oid)
	    @@projects << oid
	    
	    emit :project_added oid
    end
    
    def self.run
      emit :being_project_migration
      
      
      
      emit :end_project_migration
    end
	end
end