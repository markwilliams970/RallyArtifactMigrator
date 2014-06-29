require 'active_support/inflector'
require 'json'
require 'net/http'
require 'net/https'
require 'events'
require 'rally_api'

module ArtifactMigration
	class Importer
		extend Events::Emitter

		def self.run
			DatabaseConnection.ensure_database_connection

			prepare

			config = Configuration.singleton.target_config

			emit :begin_import

			import_projects if config.migrate_projects_flag

			#[:tag, :release, :iteration, :portfolioitem, :hierarchicalrequirement, :testfolder, :testcase, :testcasestep, :testset, :testcaseresult, :defect, :defectsuite, :task].each do |type|
            [:release, :iteration, :portfolioitem, :hierarchicalrequirement, :testfolder, :testcase, :testcasestep, :testset, :testcaseresult, :defect, :defectsuite, :task].each do |type|

				Logger.info "Importing #{type.to_s.humanize}" if config.migration_types.include? type

				if config.migration_types.include? type
					emit :begin_type_import, type
					import_type type
					emit :end_type_import, type
				end

				update_portfolio_parents if config.migration_types.include?(type) and type == :portfolio_item
				update_story_parents if config.migration_types.include?(type) and type == :hierarchical_requirement
				update_story_predecessors if config.migration_types.include?(type) and type == :hierarchical_requirement
				update_defect_duplicates if config.migration_types.include?(type) and type == :defect
				update_test_folder_parents if config.migration_types.include?(type) and type == :test_folder
			end

			update_rank
			update_artifact_statuses

			if config.migrate_attachments_flag
				if config.version.to_f < 1.29
					import_attachments 
				else
					import_attachments_ws
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

			rconfig = {}
			rconfig[:base_url] = config.server
			rconfig[:username] = config.username
			rconfig[:password] = config.password
			rconfig[:version] = config.version
			rconfig[:retries] = 2
			rconfig[:headers] = ArtifactMigration::INTEGRATION_HEADER
			rconfig[:logger] = ::Logger.new("rallydev.importer.log")
			rconfig[:debug] = true
			
			@@rally_ds = RallyAPI::RallyRestJson.new rconfig
			@@workspace = { "_ref" => "#{config.server}/webservice/#{config.version}/workspace/#{config.workspace_oid}.js" }

			Logger.debug "Using Workspace - #{@@workspace}"

			@@projects = {}
			@@user_cache = {}
			@@pi_attr_cache = {}
			@@object_manager = ObjectManager.new(@@rally_ds, @@workspace)
		end

		def self.object_manager
			@@object_manager
		end

		def self.rally_datasource
			@@rally_ds
		end

		def self.workspace
			@@workspace
		end

		def self.find_portfolio_item_attribute(type, name)
			@@pi_attr_cache[type] = {} unless @@pi_attr_cache.has_key? type
			return @@pi_attr_cache[type][name] if @@pi_attr_cache[type].has_key? name

			res = @@rally_ds.find(type, :workspace => @@workspace, :fetch => true) { equal :name, name }
			Logger.debug "Found #{res.size} results for #{type}::#{name}"
			@@pi_attr_cache[type][name] = res.first

			@@pi_attr_cache[type][name]
		end

		def self.map_field(type, field)
			config = Configuration.singleton.target_config

			Logger.debug "Does field mapping have type [#{type}] defined? - #{config.field_mapping.has_key? type}"
			return field unless config.field_mapping.has_key? type

			if config.field_mapping[type].has_key? field
				Logger.debug "Mapping field [#{field}] to field [#{config.field_mapping[type][field]}] for type [#{type}]"
				return config.field_mapping[type][field]
			else
				return field
			end
		end

		def self.map_project(old_oid)
			if old_oid.to_s.to_i <= 0
				return nil
			end

			config = Configuration.singleton.target_config
			new_oid = config.project_mapping.has_key?(old_oid.to_i) ? config.project_mapping[old_oid.to_i] : config.default_project_oid
			project = nil

			unless new_oid
				pmap = Project.find_by_source_object_i_d(old_oid)
				new_oid = pmap.target_object_i_d if pmap
			end
			Logger.debug "Map Project - #{old_oid} => #{new_oid}"

			if new_oid
				project = @@projects[new_oid]
				unless project
					project = Helper.create_ref :project, new_oid
					@@projects[new_oid] = project if project
				end
			end

			Logger.debug "Project OID #{old_oid} maps to #{project}" if project
			project
		end

		def self.map_user(old_usr)
			config = Configuration.singleton.target_config
			return nil if old_usr.nil? || (old_usr == '')
			mapped_un = config.username_mapping.has_key?(old_usr) ? config.username_mapping[old_usr] : old_usr

			if mapped_un
				uq = RallyAPI::RallyQuery.new()
				uq.type = :user
				uq.workspace = @@workspace
				uq.query_string = "(UserName = \"#{mapped_un}\")"

				@@user_cache[mapped_un] = (@@rally_ds.find(uq)).results.first if @@user_cache[mapped_un].nil?

				if @@user_cache.has_key? mapped_un
					return @@user_cache[mapped_un]
				elsif config.default_username
					mapped_un = config.default_username
					
					uq = RallyAPI::RallyQuery.new()
					uq.type = :user
					uq.workspace = @@workspace
					uq.query_string = "(UserName = \"#{mapped_un}\")"

					@@user_cache[mapped_un] = (@@rally_ds.find(uq)).results.first if @@user_cache[mapped_un].nil?
					return @@user_cache[mapped_un]
				end
			end

			nil
		end

		def self.get_mapped_id(old_oid)
			stmap = ObjectIdMap.find_by_source_id old_oid.to_i
			stmap.target_id if stmap
		end

		protected
		def self.import_projects
			config = Configuration.singleton.target_config

			emit :begin_import_projects, ArtifactMigration::Project.count
			#old_ws, old_p = switch_user_default_workspace_and_project @@rally_ds.user, @@workspace, @@workspace.projects.first

			ArtifactMigration::Project.all.each do |project|
				unless ImportTransactionLog.readonly.where("object_i_d = ? AND transaction_type = ?", project.source_object_i_d, 'import').exists?
					new_oid = config.project_mapping[project.source_object_i_d]
					next if new_oid

					owner = map_user(project.owner)
					newp = @@rally_ds.create(:project, {"Name" => project.name, "Description" => project.description, "State" => project.state, "Owner" => owner, "Workspace" => @@workspace})
					#Logger.debug newp
					if newp
						project.target_object_i_d = newp["ObjectID"]
						st = ActiveRecord::Base.connection.raw_connection.prepare("UPDATE projects SET target_object_i_d=? WHERE source_object_i_d=?")
						st.execute(newp["ObjectID"].to_s.to_i, project.source_object_i_d)
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
				if project.source_parent_i_d and project.source_parent_i_d.to_i > 0
					parent = map_project project.source_parent_i_d
					child = map_project project.source_object_i_d
					uchild = @@rally_ds.update(:project, child["ObjectID"], {"Parent" => parent})
					Logger.debug "Updated Parent Project for #{uchild}"
				end

				emit :loop
			end
			emit :end_update_project_parents

			if config.migrate_project_permissions_flag
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
					user = map_user pp.user

					next unless newp
					next if mapping.include? "#{newp['ObjectID']}_#{pp.user}"

					unless wpmapping.include? "#{config.workspace_oid}_#{pp.user}"
						role = ArtifactMigration::WorkspacePermission.find_by_workspace_i_d_and_user(Configuration.singleton.source_config.workspace_oid, pp.user).role
						Logger.debug "Adding Workspace Permission for #{pp.user} of #{role}"
						@@rally_ds.create(:workspacepermission, "Workspace" => @@workspace, "User" => user, "Role" => role)
						wpmapping << "#{config.workspace_oid}_#{pp.user}"
					else
						Logger.debug "User #{pp.user} is already in WOID #{config.workspace_oid}"
					end

					unless mapping.include? "#{newp["ObjectID"]}_#{user["UserName"]}"
						perm = @@rally_ds.create(:projectpermission, "Project" => newp, "User" => user, "Role" => pp.role)
						Logger.debug perm
						Logger.info "Migrated Project Permission for user #{user["UserName"]} for project #{newp["Name"]}"
						emit :imported_project_permission, pp.project_i_d, pp.user
					else
						Logger.info "Skipped Project Permission for user #{user["UserName"]} for project #{newp["Name"]}"
						emit :imported_project_permission_skipped, pp.project_i_d, pp.user
					end

					emit :loop
				end

				#switch_user_default_workspace_and_project @@rally_ds.user, old_ws, old_p
				emit :end_import_project_permissions
			end
		end

		def self.import_type(type)
			Logger.debug "Looking for class of type #{type.to_s.humanize}"
			klass = ArtifactMigration::RallyArtifacts.get_artifact_class(type)
			c = Configuration.singleton.target_config
			Logger.debug "Klass = #{klass}"

			emit :import_type_count, klass.count
			klass.all.each do |obj|
				attrs = {}
				obj.attributes.each { |k, v|
                    attrs[map_field(type, k.to_sym)] = v
                }

				%w(object_i_d defects predecessors parent successors duplicates children test_cases tags project workspace release iteration work_product).each { |a| attrs.delete a.to_sym if attrs.has_key? a.to_sym }

				artifact_exists = ImportTransactionLog.readonly.where("object_i_d = ? AND transaction_type = ?", obj.object_i_d, 'import').exists?
				unless artifact_exists and !c.update_existing
					valid = true

					attrs[:workspace] = @@workspace
					attrs[:release] = @@object_manager.get_mapped_artifact obj.release                    if klass.column_names.include? 'release' #&& obj.release
					attrs[:iteration] = @@object_manager.get_mapped_artifact obj.iteration                if klass.column_names.include? 'iteration' #&& obj.iteration
					attrs[:project] = map_project obj.project                                             if klass.column_names.include? 'project' #&& obj.project
					attrs[:workproduct] = @@object_manager.get_mapped_artifact obj.work_product           if klass.column_names.include? 'workproduct' #&& obj.work_product
					attrs[:requirement] = @@object_manager.get_mapped_artifact obj.requirement            if klass.column_names.include? 'requirement' #&& obj.requirement
					attrs[:portfolioitem] = @@object_manager.get_mapped_artifact obj.portfolio_item       if klass.column_names.include? 'portfolioitem' #&& obj.requirement
					attrs[:testfolder] = @@object_manager.get_mapped_artifact obj.test_folder             if klass.column_names.include? 'testfolder' #&& obj.test_case
					attrs[:testcase] = @@object_manager.get_mapped_artifact obj.test_case                 if klass.column_names.include? 'testcase' #&& obj.test_case
					attrs[:testcaseresult] = @@object_manager.get_mapped_artifact obj.test_case_result    if klass.column_names.include? 'testcaseresult' #&& obj.test_case_result
					attrs[:testset] = @@object_manager.get_mapped_artifact obj.test_set                   if klass.column_names.include? 'testset' #&& obj.test_case_result
					attrs[:owner] = map_user obj.owner                                                    if klass.column_names.include? 'owner' #&& obj.owner
					attrs[:tester] = map_user obj.tester                                                  if klass.column_names.include? 'tester' #&& obj.tester
					attrs[:submittedby] = map_user obj.submitted_by                                       if klass.column_names.include? 'submittedby' #&& obj.submitted_by

					if type == :portfolioitem
						attrs[:portfolio_item_type] = find_portfolio_item_attribute(:type, attrs[:portfolio_item_type])                   if klass.column_names.include? 'preliminary_estimate'
						attrs[:preliminary_estimate] = find_portfolio_item_attribute(:preliminary_estimate, attrs[:preliminary_estimate]) if klass.column_names.include? 'preliminary_estimate'
					end

					if klass.column_names.include? 'plan_estimate' #&& obj.rank
						if attrs[:plan_estimate] != ''
							attrs[:plan_estimate] = obj.plan_estimate.to_f
							attrs[:plan_estimate] = 999.0 if attrs[:plan_estimate] > 999.0
						end
                    end

                    puts klass.column_names

					if klass.column_names.include? 'tags' and c.migration_types.include? :tag
						tags = []
						Logger.debug "Object tags: #{obj.tags}"
						unless obj.tags.nil?
							unless obj.tags.empty?
								JSON.parse(obj.tags).each do |tid|
									tag = @@object_manager.get_mapped_artifact tid
									tags << tag if tag
								end if obj.tags
								attrs[:tags] = tags
							end
						end
					end

					if type == :defectsuite
						defects = []
						JSON.parse(obj.defects).each do |defect_id|
							defect = @@object_manager.get_mapped_artifact defect_id
							defects << defect if defect
						end
						attrs[:defects] = defects
					end

					Logger.debug "#{attrs}"
					#Clear out any fields that are blank or nil
					attrs.each_key { |k| attrs.delete k if (attrs[k].nil?) or (attrs[k] == '') or (attrs[k] == '[]') }
					attrs.delete_if { |k, v| v.kind_of?(Array) and v.size < 1 }
					attrs.delete_if { |k, v| c.ignore_fields[type].include?(k) if c.ignore_fields.has_key? type }
					attrs.delete_if { |k, v| %w(changesets attachments).include? k }

					attrs.each_key do |k|
						begin
							if JSON.parse(attrs[k]).class == Hash
								att = JSON.parse(attrs[k])
								att[:link_i_d] = att.delete "LinkID"
								att[:display_string] = att.delete "DisplayString"

								attrs[k] = att
							end
						rescue
						end
					end

					if [:testcaseresult, :testcasestep].include? type
						valid = (attrs.has_key? :testcase) && (attrs[:testcase] != nil)
					end

					attrs.delete_if { |k, v| v.nil? }
					attrs.delete :id

					# RallyRestAPI => RallyAPI
					nattrs = {}
					attrs.each { |k, v| nattrs[k.to_s.camelize] = v }
					oattrs = attrs
					attrs = nattrs

                    puts oattrs

					if valid

#						begin
							if artifact_exists
								Logger.debug "Updating #{oattrs[:name]} for project '#{oattrs[:project]}' in workspace '#{oattrs[:workspace]}'"
								Logger.debug "#{attrs}"
								artifact = @@object_manager.get_mapped_artifact obj.object_i_d
								Logger.debug "Artifact hash - #{artifact.to_hash}"
								artifact.update(attrs)
								Logger.debug "Artifact hash updated - #{artifact.to_hash}"
								Logger.info "Updated #{type.to_s.humanize}: #{artifact.name}"
							else
								Logger.debug "Creating #{oattrs[:name]} for project '#{oattrs[:project]}' in workspace '#{oattrs[:workspace]}'"
								Logger.debug "#{type}"
								Logger.debug "#{attrs}"
								artifact = @@rally_ds.create(type.to_s.gsub("_", "").to_sym, attrs)
								Logger.debug "Done... #{artifact}"
								Logger.info "Created #{type.to_s.humanize}: #{artifact}"

								@@object_manager.map_artifact obj.object_i_d, artifact["ObjectID"], artifact
								ImportTransactionLog.create(:object_i_d => obj.object_i_d, :transaction_type => 'import')
							end
=begin
						rescue Exception => e1
							begin
								unless artifact_exists
									Logger.debug e1
									Logger.debug "[WITHOUT DESCRIPTION] Creating #{attrs["Name"]} for project '#{attrs["Project"]}' in workspace '#{attrs["Workspace"]}'"
									attrs.delete "Description"
									Logger.debug "#{attrs}"
									artifact = @@rally_ds.create(type, attrs)
									Logger.info "[WITHOUT DESCRIPTION] Created #{type.to_s.humanize}: #{artifact.name}"

									@@object_manager.map_artifact obj.object_i_d, artifact.object_i_d, artifact
									ImportTransactionLog.create(:object_i_d => obj.object_i_d, :transaction_type => 'import')
									IssueTransactionLog.create(:object_i_d => obj.object_i_d, :severity => 'warning', :issue_type => 'description', :message => e1.message, :backtrace => e1.backtrace)
								end
							rescue Exception => e2
								begin
									unless artifact_exists
										Logger.debug e2
										Logger.debug "[SHELL] Creating #{attrs["Name"]} for project '#{attrs["Project"]}' in workspace '#{attrs["Workspace"]}'"

										attrs_shell = {
											:name => attrs[:name], 
											:workspace => attrs[:workspace], 
											:project => attrs[:project]
										}
										attrs_shell[:portfolio_item_type] = attrs[:portfolio_item_type] if attrs.has_key? :portfolio_item_type
										attrs_shell[:work_product] = attrs[:work_product] if attrs.has_key? :work_product

										artifact = @@rally_ds.create(type, attrs_shell)
										Logger.info "[SHELL] Created #{type.to_s.humanize}: #{artifact.name}"

										@@object_manager.map_artifact obj.object_i_d, artifact.object_i_d, artifact
										ImportTransactionLog.create(:object_i_d => obj.object_i_d, :transaction_type => 'import')
										IssueTransactionLog.create(:object_i_d => obj.object_i_d, :severity => 'warning', :issue_type => 'shell', :message => e2.message, :backtrace => e2.backtrace)
									end
								rescue Exception => e3
									Logger.debug e3
									IssueTransactionLog.create(:object_i_d => obj.object_i_d, :severity => 'error', :issue_type => 'creation', :message => e3.message, :backtrace => e3.backtrace)
								end
							end
						end
=end
						emit :imported_artifact, type, artifact
					end
				else
					Logger.info("Object ID has alread been processed - #{obj.object_i_d}");
				end

				emit :loop
			end if klass
		end

		def self.update_parents(type)
			klass = ArtifactMigration::RallyArtifacts.get_artifact_class(type)

			klass.all.each do |story|
				unless ImportTransactionLog.readonly.where("object_i_d = ? AND transaction_type = ?", story.object_i_d, 'reparent').exists?
					Logger.debug "Looking at #{type} '#{story.object_i_d} - #{story.name}'"
					if story.parent && !story.parent.empty?
						new_story = @@object_manager.get_mapped_artifact story.object_i_d
						new_story_parent = @@object_manager.get_mapped_artifact story.parent.to_i

						if new_story_parent
							Logger.debug "Updating parent for '#{new_story}' to '#{new_story_parent}'"
							@@rally_ds.update(:hierarchicalrequirement, new_story["ObjectID"], "Parent" => new_story_parent)
							ImportTransactionLog.create(:object_i_d => story.object_i_d, :transaction_type => 'reparent')

							emit :reparent, new_story

							Logger.info "Updated parent for '#{new_story}'"
						else
							Logger.info "#{type} #{story.object_i_d} has a parent, but it was not exported.  Was it in another project?"
						end
					end
				end

				emit :loop
			end
		end

		def self.update_rank
			artifacts = []
			c = Configuration.singleton.target_config

			[:hierarchical_requirement, :defect, :defect_suite, :portfolio_item].each do |k|
				next unless c.migration_types.include? k

				klass = ArtifactMigration::RallyArtifacts.get_artifact_class(k)
				Logger.debug "Re-Ranking class #{k} with #{klass.all.count} items"

				artifacts = artifacts.concat(klass.all)
			end

			artifacts.sort_by! { |o| o[:rank].to_f }

			emit :begin_update_artifact_rank, artifacts.count
			Logger.debug "Re-Ranking #{artifacts.count} artifacts"

			last_artifact = nil
			artifacts.each do |a|
				unless last_artifact
					last_artifact = a
					next
				end

				a1 = @@object_manager.get_mapped_artifact a.object_i_d
				a2 = @@object_manager.get_mapped_artifact last_artifact.object_i_d

				otmap1 = ObjectTypeMap.find_by_object_i_d(a.object_i_d)
				otmap2 = ObjectTypeMap.find_by_object_i_d(last_artifact.object_i_d)

				stmap1 = ObjectIdMap.find_by_source_id a.object_i_d.to_i
				stmap2 = ObjectIdMap.find_by_source_id last_artifact.object_i_d.to_i

				#ja1 = @@rally_ds.read(otmap1.artifact_type.to_s.camelize, stmap1.target_id)
				#ja2 = @@rally_ds.read(otmap2.artifact_type.to_s.camelize, stmap2.target_id)

				ja1 = @@rally_ds.read(:artifact, stmap1.target_id)
				ja2 = @@rally_ds.read(:artifact, stmap2.target_id)
				
				Logger.debug "#{ja1}"
				Logger.debug "#{ja2}"

				Logger.debug "Ranking '#{a.name}' below '#{last_artifact.name}'"
				@@rally_ds.rank_below(ja1["_ref"], ja2["_ref"])
				last_artifact = a

				emit :loop
			end

			emit :end_update_artifact_rank
		end

		def self.update_story_parents
			return unless ArtifactMigration::RallyArtifacts::HierarchicalRequirement.column_names.include? 'parent'
			Logger.info "Updating Story Parents"
			emit :begin_update_story_parents, ArtifactMigration::RallyArtifacts::HierarchicalRequirement.count

			update_parents :hierarchical_requirement

			emit :end_update_story_parents
		end

		def self.update_portfolio_parents
			return unless ArtifactMigration::RallyArtifacts::PortfolioItem.column_names.include? 'parent'
			Logger.info "Updating Story Parents"
			emit :begin_update_portfolio_item_parents, ArtifactMigration::RallyArtifacts::PortfolioItem.count

			update_parents :portfolio_item

			emit :end_update_portfolio_item_parents
		end

		def self.update_story_predecessors
			return unless ArtifactMigration::RallyArtifacts::HierarchicalRequirement.column_names.include? 'predecessors'
			Logger.info "Updating Story Predecessors"

			emit :begin_update_story_predecessors, ArtifactMigration::RallyArtifacts::HierarchicalRequirement.count

			ArtifactMigration::RallyArtifacts::HierarchicalRequirement.all.each do |story|
				unless ImportTransactionLog.readonly.where("object_i_d = ? AND transaction_type = ?", story.object_i_d, 'predecessors').exists?
					Logger.debug "Looking at story '#{story.object_i_d} - #{story.name}'"
					if story.predecessors && !story.predecessors.empty? && JSON.parse(story.predecessors).size > 0
						new_story = @@object_manager.get_mapped_artifact story.object_i_d

						preds = []
						unless story.predecessors.nil?
							unless story.predecessors.empty?
								JSON.parse(story.predecessors).each do |p|
									new_pred = @@object_manager.get_mapped_artifact p.to_i
									if new_pred
										preds << new_pred
									else
										Logger.info "Predecessor [#{p}] was found but not attached to the story - #{new_story}.  Was it exported?"
									end
								end
							end
						end

						if preds.size > 0
							Logger.debug "Updating predecessors for '#{new_story}'"
							new_story.update("Predecessors" => preds)
							ImportTransactionLog.create(:object_i_d => story.object_i_d, :transaction_type => 'predecessors')

							emit :story_predecessors_updated, story

							Logger.info "Updated predecessors for '#{new_story}'"
							Logger.info("Not all predecessors were exported") unless JSON.parse(story.predecessors).size == preds.size
						else
							Logger.info "Story #{story.object_i_d} has predecessors, but they were not exported.  Were they in another project?"
						end
					end
				end

				emit :loop
			end

			emit :end_update_story_predecessors
		end

		def self.update_artifact_statuses
			emit :begin_update_artifact_statuses

			config = Configuration.singleton.target_config

			[:hierarchical_requirement, :defect, :defect_suite].reverse.each do |type|
				next unless config.migration_types.include? type
				Logger.info "Updating statuses for #{type.to_s.humanize}" if config.migration_types.include? type

				klass = ArtifactMigration::RallyArtifacts.get_artifact_class(type)
				c = Configuration.singleton.source_config
				Logger.debug "Klass = #{klass}"

				emit :update_status_begin, type, klass.count
				klass.all.each do |obj|
					artifact_id = get_mapped_id obj.object_i_d
					Logger.debug "Looking at #{artifact_id} to update status"
					res = @@rally_ds.read(type.to_s.gsub("_", "").to_sym, artifact_id)
					if res
						artifact = res
						if artifact
							obj_state = (type == :task) ? obj.state : obj.schedule_state
							art_state = (type == :task) ? artifact["State"] : artifact["ScheduleState"]
							if art_state != obj_state
								unless artifact["Children"]
									Logger.info "#{artifact}'s schedule state is being updated"
									artifact.update((type == :task ? "State" : "ScheduleState") => obj_state)

									emit :artifact_status_updated, artifact
								end
							end
						end
					end

					emit :loop
				end
			end

			emit :end_update_artifact_statuses
		end

		def self.update_test_folder_parents
			return unless ArtifactMigration::RallyArtifacts::TestFolder.column_names.include? 'parent'


			Logger.info "Updating Test Folder Parents"

			emit :begin_test_folder_reparent, ArtifactMigration::RallyArtifacts::TestFolder.count
			ArtifactMigration::RallyArtifacts::TestFolder.all.each do |folder|
				unless ImportTransactionLog.readonly.where("object_i_d = ? AND transaction_type = ?", folder.object_i_d, 'reparent').exists?
					Logger.debug "Looking at test folder '#{folder.object_i_d} - #{folder.name}'"
					if folder.parent && !folder.parent.empty?
						new_folder = @@object_manager.get_mapped_artifact folder.object_i_d
						new_folder_parent = @@object_manager.get_mapped_artifact folder.parent.to_i

						if new_folder_parent
							Logger.debug "Updating parent for '#{new_folder}' to '#{new_folder_parent}'"
							new_folder.update(:parent => new_folder_parent)
							ImportTransactionLog.create(:object_i_d => folder.object_i_d, :transaction_type => 'reparent')
							Logger.info "Updated parent for '#{new_folder}'"
						else
							Logger.info "Test Folder #{folder.object_i_d} has a parent, but it was not exported.  Was it in another project?"
						end
					end
				end

				emit :loop
			end
			emit :end_test_folder_reparent
		end

		def self.update_defect_duplicates
			return unless ArtifactMigration::RallyArtifacts::Defect.column_names.include? 'duplicates'
			Logger.info "Updating Defect Duplicates"

			emit :begin_update_defect_duplicates, ArtifactMigration::RallyArtifacts::Defect.count
			ArtifactMigration::RallyArtifacts::Defect.all.each do |defect|
				unless ImportTransactionLog.readonly.where("object_i_d = ? AND transaction_type = ?", defect.object_i_d, 'duplicates').exists?
					Logger.debug "Looking at defect '#{defect.object_i_d} - #{defect.name}'"
					if defect.duplicates && !defect.duplicates.empty? && JSON.parse(defect.duplicates).size > 0
						new_defect = @@object_manager.get_mapped_artifact defect.object_i_d

						dups = []
						JSON.parse(defect.duplicates).each do |d|
							new_dup = @@object_manager.get_mapped_artifact d.to_i
							if new_dup
								dups << new_dup
							else
								Logger.info "Duplicate [#{d}] was found but not attached to the defect - #{new_defect}.  Was it exported?"
							end
						end

						if dups.size > 0
							Logger.debug "Updating predecessors for '#{new_defect}'"
							new_defect.update(:duplicates => dups)
							ImportTransactionLog.create(:object_i_d => defect.object_i_d, :transaction_type => 'duplicates')
							Logger.info "Updated duplicates for '#{new_defect}'"
							Logger.info("Not all duplicates were exported") unless JSON.parse(defect.duplicates).size == dups.size
						else
							Logger.info "Story #{defect.object_i_d} has duplicates, but they were not exported.  Were they in another project?"
						end
					end
				end
				emit :loop
			end
			emit :end_update_defect_duplicates
		end

		def self.import_attachments
			Logger.info "Importing Attachments"

			Logger.debug "Switching Workspaces to OID #{@@workspace}"
			prefs = @@rally_ds.user.user_profile

			old_ws = prefs.default_workspace
			old_p = prefs.default_project

			Logger.debug "Old Default Workspace #{old_ws}/#{old_p}"
			prefs.update(:default_workspace => @@workspace)
			Logger.debug "New Default Workspace #{prefs.default_workspace}/#{prefs.default_project}"

			config = Configuration.singleton.target_config
			token = get_rally_security_token
			attachment_new_url = "ax/newAttachment.sp"
			attachment_create_url = "ax/create.sp"

			client = RestClient::Resource.new("#{config.server}", :verify_ssl => false, :headers => {'Cookie' => token})

			res = client['switchWorkspace.sp'].post("wOid=#{config.workspace_oid}")
			#Logger.debug res

			emit :begin_attachment_import, ArtifactMigration::Attachment.count
			ArtifactMigration::Attachment.all.each do |attachment|
				source_aid = attachment.artifact_i_d
				target_aid = @@object_manager.get_mapped_artifact source_aid
				att_id = attachment.object_i_d

				next if ImportTransactionLog.readonly.where("object_i_d = ? AND transaction_type = ?", att_id, 'import').exists?

				file_name = File.join('Attachments', "#{source_aid}", "#{att_id}")
				Logger.debug "Begin upload for #{file_name} || #{target_aid.object_i_d}"

				#client["#{attachment_new_url}?oid=#{target_aid.object_i_d}"].get
				res = client[attachment_create_url].post(:fileName => attachment.name, :file => File.new(File.join('Attachments', "#{source_aid}", "#{att_id}"), 'rb'), :oid => target_aid.object_i_d, :enclosure => attachment.description)

				Logger.debug res.body
				Logger.debug(res.body.include? %q(<body onload="if(window.opener){window.opener.setTimeout('refreshWindow()', 0);}window.close();"></body>))

				success = res.body.include? %q(<body onload="if(window.opener){window.opener.setTimeout('refreshWindow()', 0);}window.close();"></body>)

				if success
					Logger.info "Uploaded Attachment #{attachment.name} for Artifact #{target_aid}"
					ImportTransactionLog.create(:object_i_d => att_id, :transaction_type => 'import')
				else
					Logger.info "FAILED to upload Attachment #{attachment.name} for Artifact #{target_aid}"
				end

				emit :loop
			end
			emit :end_attachment_import

			prefs.update(:default_workspace => old_ws, :default_project => old_p)
		end

		def self.switch_user_default_workspace(user, workspace)
			prefs = user.user_profile

			old_ws = prefs.default_workspace
			old_p = prefs.default_project

			Logger.debug "Old Default Workspace #{old_ws}/#{old_p}"
			prefs.update(:default_workspace => workspace)
			Logger.debug "New Default Workspace #{prefs.default_workspace}/#{prefs.default_project}"

			return [old_ws, old_p]
		end

		def self.switch_user_default_workspace_and_project(user, workspace, project)
			prefs = user.user_profile

			old_ws = prefs.default_workspace
			old_p = prefs.default_project

			Logger.debug "Old Default Workspace #{old_ws}/#{old_p}"
			prefs.update(:default_workspace => workspace, :defalut_project => project)
			Logger.debug "New Default Workspace #{prefs.default_workspace}/#{prefs.default_project}"

			return [old_ws, old_p]
		end

		def self.import_attachments_new(description, opts = {})
			Logger.info "Importing Attachments with Stateless Editor"
			old_ws, old_p = switch_user_default_workspace @@rally_ds.user, @@workspace
			Logger.debug "Switching Workspaces to OID #{@@workspace}"

			config = Configuration.singleton.target_config

			workspace_oid = config.workspace_oid
			token = get_rally_security_token

			adhoc = RestClient::Resource.new("#{config.server}", :verify_ssl => false, :headers => { 'Cookie' => token } )
			res = adhoc['switchWorkspace.sp'].post("wOid=#{workspace_oid}")

			def get_prefix(source_oid)
				target_type = ArtifactMigration::ObjectTypeMap.find_by_object_i_d source_oid
				case target_type
				when 'defect' then 'df'
				when 'hierarchicalrequirement' then 'ar'
				when 'task' then 'tk'
				when 'testcase' then 'tc'
				end
			end

			emit :begin_attachment_import, ArtifactMigration::Attachment.count
			ArtifactMigration::Attachment.all.each do |attachment|
				source_aid = attachment.artifact_i_d
				target_aid = @@object_manager.get_mapped_artifact source_aid
				target_oid = target_aid.object_i_d
				att_id = attachment.object_i_d
				project_oid = target_aid.project.object_i_d

				next if ImportTransactionLog.readonly.where("object_i_d = ? AND transaction_type = ?", att_id, 'import').exists?

				file_name = File.join('Attachments', "#{source_aid}", "#{att_id}")
				Logger.debug "Begin upload for #{file_name} || #{target_aid.object_i_d}"

				#client["#{attachment_new_url}?oid=#{target_aid.object_i_d}"].get
				#res = client[attachment_create_url].post(:fileName => attachment.name, :file => File.new(File.join('Attachments', "#{source_aid}", "#{att_id}"), 'rb'), :oid => target_aid.object_i_d, :enclosure => attachment.description)
				urlp = "cpoid=#{project_oid}&projectScopeUp=false&projectScopeDown=true"
				postp = {}
				version = 0
				res = adhoc["#{get_prefix(source_aid)}/edit.sp?#{urlp}&oid=#{target_oid}"].get
				doc = Nokogiri::HTML(res)
				doc.xpath('//input').each do |input|
					#puts "#{input['name']} = #{input['value']}"
					postp[input['name'].to_s.to_sym] = input['value'] if input['type'] == 'hidden'
					postp[input['name'].to_s.to_sym] = input['value'] if input['name'].include? 'enclosure'
					postp[input['name'].to_s.to_sym] = input['value'] if input['name'].include? 'steps'
				end

				#puts res.inspect
				#puts res.body
				postp[:fileName] = file_name
				postp[:file] = File.new file_name
				postp[:oid] = target_oid
				postp[:creationContext] = "#{urlp}&oid=#{target_oid}"

				res = adhoc[base_url].post(postp)

				puts res.body
				doc = Nokogiri::HTML(res)
				doc.xpath('//input').each do |input|
					puts "#{input['name']} = #{input['value']}"
					postp[input['name'].to_s.to_sym] = input['value']
					postp[input['name'].to_s.to_sym] = description if input['name'].include? 'enclosure'
				end

				postp[:editorMode] = 'edit'
				postp[:editorType] = target_type

				#'-------------------Save Artifact---------------------'
				postp.delete :file
				postp.each {|k, v| puts "#{k} = #{v}"}

				res = adhoc["#{prefix}/edit/update.sp?#{urlp}"].post(postp)
				doc = Nokogiri::HTML(res)
				doc.xpath('//input[@name = "version"]').each do |v|
					if (v['value'] == postp[:version])
						#puts "Version didn't change"
						success = false
					else
						#puts "Version changed"
						success = true
					end

					#puts "Version #{postp[:version]} => #{v['value']}"
				end

				#File.open("save_out.html", 'w') {|f| f.write(res.body) }

				if success
					Logger.info "Uploaded Attachment #{attachment.name} for Artifact #{target_aid}"
					ImportTransactionLog.create(:object_i_d => att_id, :transaction_type => 'import')
				else
					Logger.info "FAILED to upload Attachment #{attachment.name} for Artifact #{target_aid}"
				end

				emit :loop
			end
			emit :end_attachment_import

			prefs.update(:default_workspace => old_ws, :default_project => old_p)
		end

    def self.import_attachments_ws
      Logger.debug "Importing Attachments with the WSAPI"

			emit :begin_attachment_import, ArtifactMigration::Attachment.count
			ArtifactMigration::Attachment.all.each do |attachment|
				source_aid = attachment.artifact_i_d
				att_id = attachment.object_i_d

				next if ImportTransactionLog.readonly.where("object_i_d = ? AND transaction_type = ?", att_id, 'import').exists?

				file_name = File.join('Attachments', "#{source_aid}", "#{att_id}")

        content = @@rally_ds.create(:attachmentcontent, {
          "Content" => Base64.encode(File.read(file_name)),
          "Workspace" => @@workspace
        })

        att = @@rally_ds.create(:attachment, {
          "Name" => attachment.name,
          "Description" => attachment.description,
          "ContentType" => attachment.content_type,
          "Content" => content,
          "Size" => File.size(file_name),
          "Artifact" => @@object_manager.get_mapped_artifact(artifact.artifact_i_d),
          "User" => map_user(attachment.user_name)
        })

        Logger.debug "Created Attachment #{att}"
				emit :loop
      end
			emit :end_attachment_import
    end

		def self.fix_test_sets
			ArtifactMigration::RallyArtifacts::TestSet.all.each do |test_set|
				target = @@object_manager.get_mapped_artifact test_set.object_i_d.to_i
				needs_update = false

				next if target.nil?

				unless target.test_cases.nil?
					tests = target.test_cases.collect { |test_case| test_case.object_i_d.to_i }
					test_cases = target.test_cases
				else
					tests = []
					test_cases = []
				end

				JSON.parse(test_set.test_cases).each do |test_case|
					unless tests.include? test_case.to_i
						Logger.debug "Updating test set #{test_set.object_i_d} to include test case #{test_case}"
						needs_update = true
						test_cases << @@object_manager.get_mapped_artifact(test_case)
					end
				end

				if needs_update
					Logger.info "Updating test set #{target.name}"
					target.update(:test_cases => test_cases)
				end
			end
		end

		def self.import_attachments_ws
			Logger.info "Importing Attachments"

			config = Configuration.singleton.target_config

			emit :begin_attachment_import, ArtifactMigration::Attachment.count
			ArtifactMigration::Attachment.all.each do |attachment|
				source_aid = attachment.artifact_i_d
				target_aid = @@object_manager.get_mapped_artifact source_aid
				att_id = attachment.object_i_d

				next if ImportTransactionLog.readonly.where("object_i_d = ? AND transaction_type = ?", att_id, 'import').exists?

				file_name = File.join('Attachments', "#{source_aid}", "#{att_id}")
				Logger.debug "Begin upload for #{file_name} || #{target_aid['ObjectID']}"

				byte_content = File.read(file_name)
				content_string = Base64.encode64(byte_content)

				content = @@rally_ds.create(:attachmentcontent, 
                                    "Content" => content_string,
                                    "Workspace" => @@workspace
        )
				@@rally_ds.create( :attachment, 
								  :Workspace => @@workspace,
								  :Name => attachment.name,
								  :Description => attachment.description,
								  :Content => content,
								  :Artifact => target_aid,
								  :ContentType => attachment.content_type,
								  :Size => byte_content.length)

				ImportTransactionLog.create(:object_i_d => att_id, :transaction_type => 'import')

				emit :loop
			end
			emit :end_attachment_import
		end

		private
		def self.get_rally_security_token
			config = Configuration.singleton.target_config
			security_url = "platform/j_platform_security_check.op"

			uri = URI.parse(config.server)
			http = Net::HTTP.new(uri.host, 443)
			http.use_ssl = true

			data = "j_username=#{config.username}&j_password=#{config.password}"
			headers = {}

			Logger.debug "Phase 1 Security Authorization - #{uri.path}/#{security_url}"
			res = http.post2 "#{uri.path}/#{security_url}", data, headers
			Logger.debug "Status Code: #{res.code}"

			cookie = res['set-cookie']

			uri = URI.parse(res['location'])
			#puts uri.path
			headers['Cookie'] = cookie

			Logger.debug "Phase 2 Security Authorization - #{uri.path}"
			res = http.post2 uri.path, 'jsonp=&jsonOnly=', headers
			Logger.debug "Status Code: #{res.code}"

			Logger.debug "Token -- #{cookie}"
			cookie
		end

	end # Class
end # Module
