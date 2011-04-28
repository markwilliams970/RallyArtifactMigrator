require 'active_support/inflector'

module ArtifactMigration
	class Exporter
		def self.run
			prepare
						
			c = Configuration.singleton.source_config
			[:tag, :release, :iteration, :hierarchical_requirement, :test_folder, :test_case, :test_case_step, :test_set, :test_case_result, :defect, :defect_suite, :task].each do |type|
				export_type type if c.migration_types.include? type
			end
			
#			export_type :release
		end
		
		def self.prepare
			Schema.drop_all_artifact_tables
			
			Schema.create_artifact_schemas
			Schema.create_object_type_map_schema
			
			attrs = {}
			@@rw_attrs = {}
			
			c = Configuration.singleton.source_config
			ret = Helper.batch_toolkit :url => c.server,
				:username => c.username,
				:password => c.password,
				:version => ArtifactMigration::RALLY_API_VERSION,
				:workspace => c.workspace_oid,
				:type => :type_definition,
				:fields => %w(Abstract Attributes DisplayName ElementName Name Note Parent)
			
			ret['Results'].each do |r| 
				r['Attributes'].each do |a| 
					attrs[r['ElementName']] = [].to_set unless attrs[r['ElementName']]
					attrs[r['ElementName']] << a['Name'].gsub(' ', '')

					@@rw_attrs[r['ElementName']] = [].to_set unless @@rw_attrs[r['ElementName']]
					@@rw_attrs[r['ElementName']] << a['Name'].gsub(' ', '') unless a['ReadOnly']
				end

			end
			
			%w(HierarchicalRequirement Defect DefectSuite Task TestCase TestSet).each do |wp|
				@@rw_attrs[wp] = @@rw_attrs[wp] + %w(Name Notes Owner Tags Package Description FormattedID Project).to_set
			end
			
			%w(HierarchicalRequirement Defect DefectSuite Task TestCase TestSet).each do |wp|
				@@rw_attrs[wp] = @@rw_attrs[wp] - %w(Successors).to_set
			end
			
			Logger.debug("Columns for TestSet are #{@@rw_attrs['TestSet']}")
			@@rw_attrs.each { |k, v| Schema.update_schema_for_artifact(k.underscore.to_sym, v)}
			
		end
		
		def self.export_type(type)
			klass = ArtifactMigration::RallyArtifacts.get_artifact_class(type)
			c = Configuration.singleton.source_config
			
			Logger.info("Exporting #{type} with class [#{klass}]")
			
			c.project_oids.each do |poid|
				Logger.info("Searching Project #{poid}")
				
				ret = Helper.batch_toolkit :url => c.server,
					:username => c.username,
					:password => c.password,
					:version => ArtifactMigration::RALLY_API_VERSION,
					:workspace => c.workspace_oid,
					:project => poid,
					:project_scope_up => c.project_scope_up,
					:project_scope_down => c.project_scope_down,
					:type => type,
					:fields => @@rw_attrs[type.to_s.classify] + %w(UserName).to_set
			
				Logger.info("Found #{ret['Results'].size} #{type.to_s.humanize}")
				ret["Results"].each do |o|
					attrs = {}
					artifact = nil
					
					o.each do |k, v| 
						if %w(Project Requirement WorkProduct TestCase Defect DefectSuite TestFolder Parent TestCaseResult Iteration Release TestSet).include? k
							attrs[k.to_s.underscore.to_sym] = v["ObjectID"] if v
						elsif %w(Owner SubmittedBy).include? k
							attrs[k.to_s.underscore.to_sym] = v["UserName"] if v
						elsif %w(Tags Predecessors Successors TestCases Duplicates).include? k
							rels = []
							v.each do |t|
								rels.push t['ObjectID']
							end if v
							
							attrs[k.to_s.underscore.to_sym] = rels.to_json
						else
							if v.class == Hash
								if v.has_key? "LinkID"
									attrs[k.to_s.underscore.to_sym] = v["LinkID"].to_s if klass.column_names.include? k.to_s.underscore 
								end
							else
								attrs[k.to_s.underscore.to_sym] = v.to_s if klass.column_names.include? k.to_s.underscore 
							end
						end
					end
					
					c.ignore_fields[type].each { |a| attrs.delete a } if c.ignore_fields.has_key? type
					
					attrs[:object_i_d] = o["ObjectID"]
					
					artifact = klass.create(attrs) unless klass.find_by_object_i_d(o['ObjectID'].to_i)
					ObjectTypeMap.create(:object_i_d => artifact.object_i_d, :artifact_type => type.to_s) if artifact and ObjectTypeMap.find_by_object_i_d(artifact.object_i_d).nil?
					
					Logger.debug(artifact.attributes) if artifact
				end
			end
		end
	end
end