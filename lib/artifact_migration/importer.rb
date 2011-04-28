require 'active_support/inflector'
require 'rally_rest_api'
require 'json'

module ArtifactMigration
	class Importer
		def self.run
			ArtifactMigration::Schema.create_transaction_log_schema
			ArtifactMigration::Schema.create_object_id_map_schema			
			ArtifactMigration::Schema.create_object_cache_schema
			
			config = Configuration.singleton.target_config
			
			@@rally_ds = RallyRestAPI.new :username => config.username, :password => config.password, :base_url => config.server, :version => ArtifactMigration::RALLY_API_VERSION, :http_headers => ArtifactMigration::INTEGRATION_HEADER
			@@workspace = Helper.find_workspace @@rally_ds, config.workspace_oid
			@@projects = {}
			@@user_cache = {}
			
			@@object_manager = ObjectManager.new @@rally_ds, @@workspace
			
			[:tag, :release, :iteration, :hierarchical_requirement, :test_folder, :test_case, :test_case_step, :test_set, :test_case_result, :defect, :defect_suite, :task].each do |type|
				Logger.info "Importing #{type.to_s.humanize}" if config.migration_types.include? type
				
				import_type type if config.migration_types.include? type
				
				update_story_parents if config.migration_types.include?(type) and type == :hierarchical_requirement
				update_story_predecessors if config.migration_types.include?(type) and type == :hierarchical_requirement
				update_defect_duplicates if config.migration_types.include?(type) and type == :defect
				update_test_folder_parents if config.migration_types.include?(type) and type == :test_folder
				#fix_test_sets if config.migration_types.include?(type) and type == :test_set
			end
			
			update_artifact_statuses
		end
		
		protected
		def self.map_field(type, field)
			config = Configuration.singleton.target_config
			
			return field unless (config.field_mapping.has_key? type)
			
			if config.field_mapping[type].has_key? field
				Logger.debug "Mapping field [#{field}] to field [#{config.field_mapping[type][field]}] for type [#{type}]"
				return config.field_mapping[type][field]
			else
				return field
			end
		end
		
		def self.map_project(old_oid)
			config = Configuration.singleton.target_config
			new_oid = config.project_mapping.has_key?(old_oid.to_i) ? config.project_mapping[old_oid.to_i] : config.default_project_oid
			
			if new_oid
				project = @@projects[new_oid]
				unless project
					project = Helper.find_project @@rally_ds, @@workspace, new_oid
					@@projects[new_oid] = project if project
				end
			end
			
			Logger.debug "Project OID #{old_oid} maps to #{project.object_i_d}"
			project
		end
		
		def self.map_user(old_usr)
			config = Configuration.singleton.target_config
			return nil if old_usr.nil? || (old_usr == '')
			mapped_un = config.username_mapping.has_key?(old_usr) ? config.username_mapping[old_usr] : old_usr
			
			if mapped_un
				@@user_cache[mapped_un] = (@@rally_ds.find(:user, :workspace => @@workspace) { equal :user_name, mapped_un }).results.first if @@user_cache[mapped_un].nil?
				return @@user_cache[mapped_un]
			end
			
			nil
		end
		
		def self.get_mapped_id(old_oid)
			stmap = ObjectIdMap.find_by_source_id old_oid.to_i
			stmap.target_id if stmap
		end
		
		def self.import_type(type)
			Logger.debug "Looking for class of type #{type.to_s.humanize}"
			klass = ArtifactMigration::RallyArtifacts.get_artifact_class(type)
			c = Configuration.singleton.source_config
			Logger.debug "Klass = #{klass}"
			
			klass.all.each do |obj|
				attrs = {}
				obj.attributes.each { |k, v| attrs[map_field(type, k.to_sym)] = v }
				
				%w(object_i_d defects predecessors parent successors duplicates children test_cases tags project workspace release iteration work_product).each { |a| attrs.delete a.to_sym if attrs.has_key? a.to_sym }
				
				unless ImportTransactionLog.readonly.where("object_i_d = ? AND transaction_type = ?", obj.object_i_d, 'import').exists?
					valid = true
					
					attrs[:workspace] = @@workspace
					attrs[:release] = @@object_manager.get_mapped_artifact obj.release 						if klass.column_names.include? 'release' #&& obj.release
					attrs[:iteration] = @@object_manager.get_mapped_artifact obj.iteration 				if klass.column_names.include? 'iteration' #&& obj.iteration
					attrs[:project] = map_project obj.project 																		if klass.column_names.include? 'project' #&& obj.project
					attrs[:work_product] = @@object_manager.get_mapped_artifact obj.work_product 	if klass.column_names.include? 'work_product' #&& obj.work_product
					attrs[:requirement] = @@object_manager.get_mapped_artifact obj.requirement 		if klass.column_names.include? 'requirement' #&& obj.requirement
					attrs[:test_folder] = @@object_manager.get_mapped_artifact obj.test_folder		if klass.column_names.include? 'test_folder' #&& obj.test_case
					attrs[:test_case] = @@object_manager.get_mapped_artifact obj.test_case 				if klass.column_names.include? 'test_case' #&& obj.test_case
					attrs[:test_case_result] = @@object_manager.get_mapped_artifact obj.test_case_result 		if klass.column_names.include? 'test_case_result' #&& obj.test_case_result
					attrs[:test_set] = @@object_manager.get_mapped_artifact obj.test_set 					if klass.column_names.include? 'test_set' #&& obj.test_case_result
					attrs[:owner] = map_user obj.owner 																						if klass.column_names.include? 'owner' #&& obj.owner
					attrs[:tester] = map_user obj.tester 																					if klass.column_names.include? 'tester' #&& obj.tester
					attrs[:submitted_by] = map_user obj.submitted_by 															if klass.column_names.include? 'submitted_by' #&& obj.submitted_by
					
					if klass.column_names.include? 'plan_estimate' #&& obj.rank
						if attrs[:plan_estimate] != ''
							attrs[:plan_estimate] = obj.plan_estimate.to_f
							attrs[:plan_estimate] = 999.0 if attrs[:plan_estimate] > 999.0
						end
					end
					
					if klass.column_names.include? 'tags'
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
					
					if type == :defect_suite
						defects = []
						obj.defects.each do |defect_id|
							defect = @@object_manager.get_mapped_artifact defect_id
							defects << defect if defect
						end
						attrs[:defects] = defects
					end
					
					#Clear out any fields that are blank or nil
					attrs.each_key { |k| attrs.delete k if (attrs[k].nil?) or (attrs[k] == '') }

					if [:test_case_result, :test_case_step].include? type
						valid = (attrs.has_key? :test_case) && (attrs[:test_case] != nil)
					end
					
					attrs.delete_if { |k, v| v.nil? }
					
					if valid
						Logger.debug "Creating #{attrs[:name]} for project '#{attrs[:project]}' in workspace '#{attrs[:workspace]}'"
						Logger.debug "#{attrs}"
						artifact = @@rally_ds.create(type, attrs)
						Logger.info "Created #{type.to_s.humanize}: #{artifact.name}"
										
						@@object_manager.map_artifact obj.object_i_d, artifact.object_i_d, artifact
						ImportTransactionLog.create(:object_i_d => obj.object_i_d, :transaction_type => 'import')
					end
				else
					Logger.info("Object ID has alread been processed - #{obj.object_i_d}");
				end
			end if klass
		end
		
		def self.update_story_parents
			return unless ArtifactMigration::RallyArtifacts::HierarchicalRequirement.column_names.include? 'parent'
			Logger.info "Updating Story Parents"
			
			ArtifactMigration::RallyArtifacts::HierarchicalRequirement.all.each do |story|
				unless ImportTransactionLog.readonly.where("object_i_d = ? AND transaction_type = ?", story.object_i_d, 'reparent').exists?
					Logger.debug "Looking at story '#{story.object_i_d} - #{story.name}'"
					if story.parent && !story.parent.empty?
						new_story = @@object_manager.get_mapped_artifact story.object_i_d
						new_story_parent = @@object_manager.get_mapped_artifact story.parent.to_i
						
						if new_story_parent
							Logger.debug "Updating parent for '#{new_story}' to '#{new_story_parent}'"
							new_story.update(:parent => new_story_parent)
							ImportTransactionLog.create(:object_i_d => story.object_i_d, :transaction_type => 'reparent')
							Logger.info "Updated parent for '#{new_story}'"
						else
							Logger.info "Story #{story.object_i_d} has a parent, but it was not exported.  Was it in another project?"
						end
					end
				end
			end
		end
		
		def self.update_story_predecessors
			return unless ArtifactMigration::RallyArtifacts::HierarchicalRequirement.column_names.include? 'predecessors'
			Logger.info "Updating Story Predecessors"
			
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
							new_story.update(:predecessors => preds)
							ImportTransactionLog.create(:object_i_d => story.object_i_d, :transaction_type => 'predecessors')
							Logger.info "Updated predecessors for '#{new_story}'"
							Logger.info("Not all predecessors were exported") unless JSON.parse(story.predecessors).size == preds.size
						else
							Logger.info "Story #{story.object_i_d} has predecessors, but they were not exported.  Were they in another project?"
						end
					end
				end
			end
		end
		
		def self.update_artifact_statuses
			config = Configuration.singleton.target_config
			
			[:hierarchical_requirement, :defect, :defect_suite].reverse.each do |type|
				Logger.info "Updating statuses for #{type.to_s.humanize}" if config.migration_types.include? type
				
				klass = ArtifactMigration::RallyArtifacts.get_artifact_class(type)
				c = Configuration.singleton.source_config
				Logger.debug "Klass = #{klass}"

				klass.all.each do |obj|
					artifact_id = get_mapped_id obj.object_i_d
					Logger.debug "Looking at #{artifact_id} to update status"
					res = @@rally_ds.find(type, :workspace => @@workspace) { equal :object_i_d, artifact_id }
					if res
						artifact = res.first
						if artifact
							obj_state = (type == :task) ? obj.state : obj.schedule_state
							art_state = (type == :task) ? artifact.state : artifact.schedule_state
							if art_state != obj_state
								Logger.info "#{artifact}'s schedule state is being updated" unless artifact.children
								artifact.update((type == :task ? :state : :schedule_state) => obj_state) unless artifact.children
							end
						end
					end
				end
			end
		end
		
		def self.update_test_folder_parents
			return unless ArtifactMigration::RallyArtifacts::TestFolder.column_names.include? 'parent'
			Logger.info "Updating Test Folder Parents"
			
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
			end
		end
		
		def self.update_defect_duplicates
			return unless ArtifactMigration::RallyArtifacts::Defect.column_names.include? 'duplicates'
			Logger.info "Updating Defect Dupicates"
			
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
			end
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

	end # Class
end # Module