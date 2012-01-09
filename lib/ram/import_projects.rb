require 'active_support/inflector'
require 'rally_rest_api'
require 'json'
require 'net/http'
require 'net/https'
require 'events'

module ArtifactMigration
	class ImportProjects
		extend Events::Emitter
		
		def self.projects
		  @@projects
	  end
		
		def self.prepare
			config = Configuration.singleton.target_config
			config.version = ArtifactMigration::RALLY_API_VERSION if config.version.nil?
			
			@@rally_ds = RallyRestAPI.new :username => config.username, :password => config.password, :base_url => config.server, :version => config.version, :http_headers => ArtifactMigration::INTEGRATION_HEADER
			@@workspace = Helper.find_workspace @@rally_ds, config.workspace_oid
		  @@object_manager = ObjectManager.new @@rally_ds, @@workspace
			@@projects = {}
		end
		
		def self.import_projects
			config = Configuration.singleton.target_config

			emit :begin_import_projects, ArtifactMigration::Project.count

			ArtifactMigration::Project.all.each do |project|
			  unless ImportTransactionLog.readonly.where("object_i_d = ? AND transaction_type = ?", project.source_object_i_d, 'import').exists?
  			  new_oid = config.project_mapping[project.source_object_i_d]
  			  next if new_oid

  			  owner = Importer.map_user(project.owner)
  			  newp = @@rally_ds.create(:project, :name => project.name, :description => project.description, :state => project.state, :owner => owner, :workspace => @@workspace)
  			  #Logger.debug newp
  			  if newp
  			    project.target_object_i_d = newp.object_i_d
  			    st = ActiveRecord::Base.connection.raw_connection.prepare("UPDATE projects SET target_object_i_d=? WHERE source_object_i_d=?")
            st.execute(newp.object_i_d.to_s.to_i, project.source_object_i_d)
            st.close

  			    ImportTransactionLog.create(:object_i_d => project.source_object_i_d, :transaction_type => 'import')

  			    config.map_project_oid :from => project.source_object_i_d, :to => newp.object_i_d.to_s.to_i
  			    emit :imported_project, project.source_object_i_d
  		    else
  		      emit :imported_project_skipped, project.source_object_i_d
  		    end

  		    emit :loop
  		  else
          config.map_project_oid :from => project.source_object_i_d, :to => project.target_object_i_d
  		  end
	    end
		  emit :end_import_projects

		  emit :begin_update_project_parents, ArtifactMigration::Project.count
		  ArtifactMigration::Project.all.each do |project|
		    if project.source_parent_i_d
		      parent = map_project project.source_parent_i_d
		      child = map_project project.source_object_i_d
		      child.update :parent => parent
		      Logger.debug "Updated Parent Project for #{project.name}"
	      end

	      emit :loop
			end
			emit :end_update_project_parents

			ret = Helper.batch_toolkit :url => config.server,
				:username => config.username,
				:password => config.password,
				:version => config.version,
				:workspace => config.workspace_oid,
				:project_scope_up => config.project_scope_up,
				:project_scope_down => config.project_scope_down,
				:type => :workspace_permission,
				:fields => %w(ObjectID User Role Workspace UserName Name).to_set

			wpmapping = ret["Results"].collect { |wp| "#{wp['Workspace']['ObjectID']}_#{wp['User']['UserName']}" }
			Logger.debug "WPMapping - #{wpmapping}"

			ret = Helper.batch_toolkit :url => config.server,
				:username => config.username,
				:password => config.password,
				:version => config.version,
				:workspace => config.workspace_oid,
				:project_scope_up => config.project_scope_up,
				:project_scope_down => config.project_scope_down,
				:type => :project_permission,
				:fields => %w(ObjectID User Role Project UserName Name).to_set

			mapping = ret["Results"].collect { |pp| "#{pp['Project']['ObjectID']}_#{pp['User']['UserName']}" }
			Logger.debug "PPMapping - #{mapping.size} - #{mapping}"

			emit :begin_import_project_permissions, ArtifactMigration::ProjectPermission.count
			ArtifactMigration::ProjectPermission.all.each do |pp|
			  newp = map_project pp.project_i_d
			  user = Importer.map_user pp.user

			  next unless newp
			  next if mapping.include? "#{newp.object_i_d}_#{pp.user}"

			  unless wpmapping.include? "#{config.workspace_oid}_#{pp.user}"
			    role = ArtifactMigration::WorkspacePermission.find_by_workspace_i_d_and_user(Configuration.singleton.source_config.workspace_oid, pp.user).role
			    Logger.debug "Adding Workspace Permission for #{pp.user} of #{role}"
			    @@rally_ds.create(:workspace_permission, :workspace => @@workspace, :user => user, :role => role)
			  else
			    Logger.debug "User #{pp.user} is already in WOID #{config.workspace_oid}"
		    end

			  unless mapping.include? "#{newp.object_i_d}_#{user.user_name}"
  			  perm = @@rally_ds.create(:project_permission, :project => newp, :user => user, :role => pp.role)
  			  Logger.debug perm
  			  emit :imported_project_permission, pp.project_i_d, pp.user
  			else
  			  emit :imported_project_permission_skipped, pp.project_i_d, pp.user
			  end

			  emit :loop
		  end

		  #switch_user_default_workspace_and_project @@rally_ds.user, old_ws, old_p
		  emit :end_import_project_permissions

	  end
    
    def self.map_project(old_oid)
    	config = Configuration.singleton.target_config
    	new_oid = config.project_mapping.has_key?(old_oid.to_i) ? config.project_mapping[old_oid.to_i] : config.default_project_oid
    	project = nil
	
    	if new_oid
    		project = @@projects[new_oid]
    		unless project
    			project = Helper.find_project @@rally_ds, @@workspace, new_oid
    			@@projects[new_oid] = project if project
    		end
    	end
	
    	Logger.debug "Project OID #{old_oid} maps to #{project.object_i_d}" if project
    	project
    end
  end
end