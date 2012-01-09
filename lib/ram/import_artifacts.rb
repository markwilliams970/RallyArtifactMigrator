require 'active_support/inflector'
require 'rally_rest_api'
require 'json'
require 'net/http'
require 'net/https'
require 'events'
require 'thread'
require 'date'

module ArtifactMigration
	class ImportArtifacts
		extend Events::Emitter
		
		def self.prepare
			config = Configuration.singleton.target_config
			config.version = ArtifactMigration::RALLY_API_VERSION if config.version.nil?
			config.max_threads = 3 unless config.max_threads 
			
			@@rally_ds = RallyRestAPI.new :username => config.username, :password => config.password, :base_url => config.server, :version => config.version, :http_headers => ArtifactMigration::INTEGRATION_HEADER

			@@artifact_q = Queue.new
			@@outbound_q = Queue.new
			@@threads = []
			@@mutex = Mutex.new
		  
			@@workspace = Helper.find_workspace @@rally_ds, config.workspace_oid
		  @@object_manager = ObjectManager.new @@rally_ds, @@workspace
			@@pi_attr_cache = {}
			@@thread_done = false
		end
		
		def self.generate_create_artifact_thread
		  return Thread.new do
  			config = Configuration.singleton.target_config
  			rally_ds = RallyRestAPI.new :username => config.username, :password => config.password, :base_url => config.server, :version => config.version, :http_headers => ArtifactMigration::INTEGRATION_HEADER
       
        until @@thread_done and @@artifact_q.empty?
          message = @@artifact_q.pop

          attrs = message[:attrs]
          artifact_exists = message[:artifact_exists]
          type = message[:type]
          obj = message[:obj]
          
          Logger.debug "Threaded import"
				  begin
						if artifact_exists
  						Logger.debug "Updating #{attrs[:name]} for project '#{attrs[:project]}' in workspace '#{attrs[:workspace]}'"
  						Logger.debug "#{attrs}"
  						artifact = @@object_manager.get_mapped_artifact obj.object_i_d
  						artifact.update(attrs)
  						Logger.info "Updated #{type.to_s.humanize}: #{artifact.name}"
					  else
  						Logger.debug "Creating #{attrs[:name]} for project '#{attrs[:project]}' in workspace '#{attrs[:workspace]}'"
  						Logger.debug "#{attrs}"
  						artifact = rally_ds.create(type, attrs)
  						Logger.info "Created #{type.to_s.humanize}: #{artifact.name}"

						  @@outbound_q << {
						    :map_object => {
						      :source_id => obj.object_i_d,
						      :target_id => artifact.object_i_d,
						      :artifact => artifact
						    },
						    :transaction_log => {
						      :object_i_d => obj.object_i_d, 
						      :transaction_type => 'import', 
						      :imported_on => DateTime.now
						    }
					    }
    						
  						#@@object_manager.map_artifact obj.object_i_d, artifact.object_i_d, artifact
						  #ImportTransactionLog.create()
				    end
					rescue Exception => e1
					  begin
					    unless artifact_exists
  					    Logger.debug e1
    						Logger.debug "[WITHOUT DESCRIPTION] Creating #{attrs[:name]} for project '#{attrs[:project]}' in workspace '#{attrs[:workspace]}'"
    						attrs.delete :description
    						Logger.debug "#{attrs}"
    						artifact = rally_ds.create(type, attrs)
    						Logger.info "[WITHOUT DESCRIPTION] Created #{type.to_s.humanize}: #{artifact.name}"

  						  @@outbound_q << {
  						    :map_object => {
  						      :source_id => obj.object_i_d,
  						      :target_id => artifact.object_i_d,
  						      :artifact => artifact
  						    },
  						    :transaction_log => {
  						      :object_i_d => obj.object_i_d, 
  						      :transaction_type => 'import', 
  						      :imported_on => DateTime.now
  						    }, 
  						    :issue_log => {
                    :object_i_d => obj.object_i_d, 
                    :severity => 'warning', 
                    :issue_type => 'description', 
                    :message => e1.message, 
                    :backtrace => e1.backtrace
                  }
  					    }

    						#ImportTransactionLog.create(:object_i_d => obj.object_i_d, :transaction_type => 'import', :imported_on => DateTime.now)
    						#IssueTransactionLog.create()
    					end
  					rescue Exception => e2
  					  begin
  					    unless artifact_exists
    					    Logger.debug e2
      						Logger.debug "[SHELL] Creating #{attrs[:name]} for project '#{attrs[:project]}' in workspace '#{attrs[:workspace]}'"
    						
      						attrs_shell = {
      						  :name => attrs[:name], 
      						  :workspace => attrs[:workspace], 
      						  :project => attrs[:project]
      						}
      						attrs_shell[:portfolio_item_type] = attrs[:portfolio_item_type] if attrs.has_key? :portfolio_item_type
      						attrs_shell[:work_product] = attrs[:work_product] if attrs.has_key? :work_product
    						
      						artifact = rally_ds.create(type, attrs_shell)
      						Logger.info "[SHELL] Created #{type.to_s.humanize}: #{artifact.name}"

    						  @@outbound_q << {
    						    :map_object => {
    						      :source_id => obj.object_i_d,
    						      :target_id => artifact.object_i_d,
    						      :artifact => artifact
    						    },
    						    :transaction_log => {
    						      :object_i_d => obj.object_i_d, 
    						      :transaction_type => 'import', 
    						      :imported_on => DateTime.now
    						    }, 
    						    :issue_log => {
                      :object_i_d => obj.object_i_d, 
                      :severity => 'warning', 
                      :issue_type => 'shell', 
                      :message => e2.message, 
                      :backtrace => e2.backtrace
                    }
    					    }

#      						@@object_manager.map_artifact obj.object_i_d, artifact.object_i_d, artifact

#      						ImportTransactionLog.create(:object_i_d => obj.object_i_d, :transaction_type => 'import', :imported_on => DateTime.now)
#      						IssueTransactionLog.create(:object_i_d => obj.object_i_d, :severity => 'warning', :issue_type => 'shell', :message => e2.message, :backtrace => e2.backtrace)
      					end
					    rescue Exception => e3
					      Logger.debug e3
  						  @@outbound_q << {
  						    :issue_log => {
                    :object_i_d => obj.object_i_d, 
                    :severity => 'error', 
                    :issue_type => 'creation', 
                    :message => e3.message, 
                    :backtrace => e3.backtrace
                  }
  					    }
    						#IssueTransactionLog.create(:object_i_d => obj.object_i_d, :severity => 'error', :issue_type => 'creation', :message => e3.message, :backtrace => e3.backtrace)
				      end
					  end
				  end
					emit :imported_artifact, type, artifact
					emit :loop
				end
		  end
	  end
		
		def self.object_manager
			@@object_manager
		end
		
		def self.find_portfolio_item_attribute(type, name)
		  @@pi_attr_cache[type] = {} unless @@pi_attr_cache.has_key? type
		  return @@pi_attr_cache[type][name] if @@pi_attr_cache[type].has_key? name
		  
		  @@mutex.synchronize {
		    res = @@rally_ds.find(type, :workspace => @@workspace, :fetch => true) { equal :name, name }
  		  Logger.debug "Found #{res.size} results for #{type}::#{name}"
  		  @@pi_attr_cache[type][name] = res.first
	    }	    
		  
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
		
		def self.import_type(type)
			Logger.debug "Looking for class of type #{type.to_s.humanize}"
			klass = ArtifactMigration::RallyArtifacts.get_artifact_class(type)
			c = Configuration.singleton.target_config
			Logger.debug "Klass = #{klass}"
			@@thread_done = false
			
			emit :import_type_count, klass.count
			
			c.max_threads.times do |i|
			  Logger.debug "Creating thread #{i}"
			  t = generate_create_artifact_thread
			  @@threads << t
			  Logger.debug "Thread #{i} created"
		  end
			
			klass.all.each do |obj|
				attrs = {}
				obj.attributes.each { |k, v| attrs[map_field(type, k.to_sym)] = v }
				
				%w(object_i_d defects predecessors parent successors duplicates children test_cases tags project workspace release iteration work_product).each { |a| attrs.delete a.to_sym if attrs.has_key? a.to_sym }
				
				artifact_exists = ImportTransactionLog.readonly.where("object_i_d = ? AND transaction_type = ?", obj.object_i_d, 'import').exists?
				unless artifact_exists and !c.update_existing
					valid = true
					
					attrs[:workspace] = @@workspace
					attrs[:release] = @@object_manager.get_mapped_artifact obj.release 						if klass.column_names.include? 'release' #&& obj.release
					attrs[:iteration] = @@object_manager.get_mapped_artifact obj.iteration 				if klass.column_names.include? 'iteration' #&& obj.iteration
					attrs[:project] = ImportProjects.map_project obj.project 											if klass.column_names.include? 'project' #&& obj.project
					attrs[:work_product] = @@object_manager.get_mapped_artifact obj.work_product 	if klass.column_names.include? 'work_product' #&& obj.work_product
					attrs[:requirement] = @@object_manager.get_mapped_artifact obj.requirement 		if klass.column_names.include? 'requirement' #&& obj.requirement
					attrs[:portfolio_item] = @@object_manager.get_mapped_artifact obj.portfolio_item 		    if klass.column_names.include? 'portfolio_item' #&& obj.requirement
					attrs[:test_folder] = @@object_manager.get_mapped_artifact obj.test_folder		if klass.column_names.include? 'test_folder' #&& obj.test_case
					attrs[:test_case] = @@object_manager.get_mapped_artifact obj.test_case 				if klass.column_names.include? 'test_case' #&& obj.test_case
					attrs[:test_case_result] = @@object_manager.get_mapped_artifact obj.test_case_result 		if klass.column_names.include? 'test_case_result' #&& obj.test_case_result
					attrs[:test_set] = @@object_manager.get_mapped_artifact obj.test_set 					if klass.column_names.include? 'test_set' #&& obj.test_case_result
					attrs[:owner] = Importer.map_user obj.owner 																						if klass.column_names.include? 'owner' #&& obj.owner
					attrs[:tester] = Importer.map_user obj.tester 																					if klass.column_names.include? 'tester' #&& obj.tester
					attrs[:submitted_by] = Importer.map_user obj.submitted_by 															if klass.column_names.include? 'submitted_by' #&& obj.submitted_by

          if type == :portfolio_item
					  attrs[:portfolio_item_type] = find_portfolio_item_attribute(:type, attrs[:portfolio_item_type])                   if klass.column_names.include? 'preliminary_estimate'
					  attrs[:preliminary_estimate] = find_portfolio_item_attribute(:preliminary_estimate, attrs[:preliminary_estimate]) if klass.column_names.include? 'preliminary_estimate'
					end
					
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
					attrs.delete_if { |k, v| c.ignore_fields[type].include?(k) if c.ignore_fields.has_key? type }
					
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

					if [:test_case_result, :test_case_step].include? type
						valid = (attrs.has_key? :test_case) && (attrs[:test_case] != nil)
					end
					
					attrs.delete_if { |k, v| v.nil? }
					
					if valid
					  @@artifact_q << { :attrs => attrs, :artifact_exists => artifact_exists, :type => type, :obj => obj }
					end
				else
					Logger.info("Object ID has alread been processed - #{obj.object_i_d}");
				end
				
#				emit :loop
			end if klass
			
			@@thread_done = true
			@@threads.each { |t| t.join }

			until @@outbound_q.empty?
			  msg = @@outbound_q.pop
			  
			  if msg.has_key? :map_object
          @@object_manager.map_artifact msg[:map_object][:source_id], msg[:map_object][:target_id], msg[:map_object][:artifact]
        end
        
        if msg.has_key? :import_log
          ImportTransactionLog.create(:object_i_d => msg[:import_log][:object_i_d], :transaction_type => msg[:import_log][:transaction_type], :imported_on => msg[:import_log][:imported_on])
        end

        if msg.has_key? :issue_log
          IssueTransactionLog.create(:object_i_d => msg[:issue_log][:object_i_d], :severity => msg[:issue_log][:severity], :issue_type => msg[:issue_log][:issue_type], :message => msg[:issue_log][:message], :backtrace => msg[:issue_log][:backtrace])
        end
      end
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
							new_story.update(:parent => new_story_parent)
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
							new_story.update(:predecessors => preds)
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
				Logger.info "Updating statuses for #{type.to_s.humanize}" if config.migration_types.include? type
				
				klass = ArtifactMigration::RallyArtifacts.get_artifact_class(type)
				c = Configuration.singleton.source_config
				Logger.debug "Klass = #{klass}"

				emit :update_status_begin, type, klass.count
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
								unless artifact.children
									Logger.info "#{artifact}'s schedule state is being updated"
									artifact.update((type == :task ? :state : :schedule_state) => obj_state)
									
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
		
		def self.get_mapped_id(old_oid)
			stmap = ObjectIdMap.find_by_source_id old_oid.to_i
			stmap.target_id if stmap
		end
		
	end
end