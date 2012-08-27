require 'active_record'
require 'active_support/inflector'

module ArtifactMigration
	class Schema
		def self.create_transaction_log_schema
			ActiveRecord::Schema.define do
				ActiveRecord::Migration.verbose = false
				unless ImportTransactionLog.table_exists?
					create_table :import_transaction_logs, :id => false do |t|
						t.column :object_i_d, :integer
						t.column :transaction_type, :string
					end
					
					add_index :import_transaction_logs, :object_i_d
					add_index :import_transaction_logs, :transaction_type
				end
			end
		end

		def self.create_issue_log_schema
			ActiveRecord::Schema.define do
				ActiveRecord::Migration.verbose = false
				unless IssueTransactionLog.table_exists?
					create_table :issue_transaction_logs, :id => false do |t|
						t.column :object_i_d, :integer
						t.column :issue_type, :string
						t.column :severity, :string
						t.column :message, :text
						t.column :backtrace, :text
					end
					
					add_index :issue_transaction_logs, :object_i_d
					add_index :issue_transaction_logs, :issue_type
					add_index :issue_transaction_logs, :severity
				end
			end
		end

		def self.create_object_id_map_schema
			ActiveRecord::Schema.define do
				ActiveRecord::Migration.verbose = false
				unless ObjectIdMap.table_exists?
					create_table ObjectIdMap.table_name.to_sym, :id => false do |t|
						t.column :source_id, :integer
						t.column :target_id, :integer
					end
					
					add_index ObjectIdMap.table_name.to_sym, :source_id
					add_index ObjectIdMap.table_name.to_sym, :target_id
				end
			end
		end

		def self.create_object_type_map_schema
			ActiveRecord::Schema.define do
				ActiveRecord::Migration.verbose = false
				create_table ObjectTypeMap.table_name.to_sym, :force => true, :id => false do |t|
					t.column :object_i_d, :integer
					t.column :artifact_type, :string
				end
				
				add_index ObjectTypeMap.table_name.to_sym, :object_i_d, :unique => true
			end
		end
		
		def self.create_options_schema
			ActiveRecord::Schema.define do
				ActiveRecord::Migration.verbose = false
				unless Options.table_exists?
					create_table Options.table_name.to_sym, :id => true do |t|
						t.column :key, :string
						t.column :value, :text
					end

					add_index Options.table_name.to_sym, :key, :unique => true
				end
			end
		end

		def self.create_object_cache_schema
			ActiveRecord::Schema.define do
				ActiveRecord::Migration.verbose = false
				unless ObjectCache.table_exists?
					create_table ObjectCache.table_name.to_sym, :id => false do |t|
						t.column :object_i_d, :integer
						t.column :cached_object, :text
					end

					add_index ObjectCache.table_name.to_sym, :object_i_d, :unique => true
				end
			end
		end
		
		def self.create_artifact_schemas
			ActiveRecord::Schema.define do
				ActiveRecord::Migration.verbose = false
				
				ArtifactMigration::RallyArtifacts.constants.each do |c|
					next if c == :Attachment
					next if c == :Project
					
					Logger.debug "Creating schema for #{c}"
					klass = ArtifactMigration::RallyArtifacts.const_get(c)
					
					unless klass.table_exists?
						create_table c.to_s.tableize.to_sym, :id => true do |t|
							t.column :object_i_d, :integer
						end

						add_index c.to_s.tableize.to_sym, :object_i_d, :unique => true
					end
					#klass.set_primary_key "object_i_d"

					#Logger.debug "#{c.to_s}'s primary key is: #{klass.primary_key}"
					
				end
			end
		end
	
		def self.create_project_scheme
			ActiveRecord::Schema.define do
				ActiveRecord::Migration.verbose = false
				
        unless ArtifactMigration::Project.table_exists?
  				create_table :projects, :id => false, :force => false do |t|
  					t.column :source_object_i_d, :integer
  					t.column :target_object_i_d, :integer
  					t.column :source_parent_i_d, :integer
  					t.column :name, :string
  					t.column :description, :text
  					t.column :owner, :string
  					t.column :state, :string
  				end
				
  				add_index :projects, :source_object_i_d, :unique => true
  				add_index :projects, :target_object_i_d, :unique => true
  				add_index :projects, :source_parent_i_d
        end

        unless ArtifactMigration::ProjectPermission.table_exists?
  				create_table :project_permissions, :id => false, :force => false do |t|
  					t.column :project_i_d, :integer
  					t.column :user, :string
  					t.column :role, :string
  				end
				
  				add_index :project_permissions, :project_i_d
  				add_index :project_permissions, :user
        end

        unless ArtifactMigration::WorkspacePermission.table_exists?
  				create_table :workspace_permissions, :id => false, :true => false do |t|
  					t.column :workspace_i_d, :integer
  					t.column :user, :string
  					t.column :role, :string
  				end
				
  				add_index :workspace_permissions, :workspace_i_d
  				add_index :workspace_permissions, :user
        end
			end
		end
		
    def self.create_attribute_value_schema
			ActiveRecord::Schema.define do
				ActiveRecord::Migration.verbose = false
				
				create_table :attribte_values, :id => false, :force => true do |t|
				  t.column :attribute_i_d, :integer
				  t.column :name, :string
				  t.column :artifact_type, :string
				  t.column :attribute_type, :string
				  t.column :values, :text
			  end
			end
    end
		
		def self.create_attachments_list_schema
			ActiveRecord::Schema.define do
				ActiveRecord::Migration.verbose = false
				
				create_table :attachments_lists, :id => false, :force => true do |t|
					t.column :object_i_d, :integer
					t.column :artifact_i_d, :integer
				end
				
				add_index :attachments_lists, :object_i_d, :unique => true
			end
		end
		
		def self.create_attachment_schema
			ActiveRecord::Schema.define do
				ActiveRecord::Migration.verbose = false
				
				create_table :attachments, :id => false, :force => true do |t|
					t.column :object_i_d, :integer
					t.column :artifact_i_d, :integer
					t.column :name, :string
					t.column :description, :text
					t.column :user_name, :string
					t.column :content_type, :string
				end
				
				add_index :attachments, :object_i_d, :unique => true
			end
		end
		
		def self.update_schema_for_artifact(type, columns)
			klass = ArtifactMigration::RallyArtifacts.get_artifact_class(type)
			if !klass.nil? && klass.ancestors.include?(ActiveRecord::Base) && klass.table_exists?
				ActiveRecord::Schema.define do
					ActiveRecord::Migration.verbose = false
					change_table type.to_s.tableize.to_sym do |t|
						columns.each do |c|
							t.column c.underscore, :text unless klass.column_names.include? c.underscore
						end
					end
				end
				klass.reset_column_information
				Logger.debug "Columns after update of #{type} - #{klass.column_names}"
			end
		end
		
		def self.create_one_to_many_association(parent_type, child_type)
			p_klass = ArtifactMigration::RallyArtifacts.get_artifact_class(parent_type)
			c_klass = ArtifactMigration::RallyArtifacts.get_artifact_class(child_type)
			
			if !p_klass.nil? && p_klass.ancestors.include?(ActiveRecord::Base) && p_klass.table_exists? &&
				 !c_klass.nil? && c_klass.ancestors.include?(ActiveRecord::Base) && c_klass.table_exists?
				ActiveRecord::Schema.define do
					ActiveRecord::Migration.verbose = false
					change_table child_type.to_s.tableize.to_sym do |t|
						t.references parent_type unless c_klass.column_names.include? c.underscore
					end
				end
				#p_klass.reset_column_information
				c_klass.reset_column_information
				
				Logger.debug "Columns after update of #{child_type} - #{c_klass.column_names}"
			end
		end

		# FINISH!!!!!!!
		def self.create_many_to_many_association(parent_type, child_type)
			p_klass = ArtifactMigration::RallyArtifacts.get_artifact_class(parent_type)
			c_klass = ArtifactMigration::RallyArtifacts.get_artifact_class(child_type)
			a_klass = ArtifactMigration::RallyArtifacts.get_artifact_class("#{parent_type}_#{child_type}".to_sym)
			
			if !p_klass.nil? && p_klass.ancestors.include?(ActiveRecord::Base) && p_klass.table_exists? &&
				 !c_klass.nil? && c_klass.ancestors.include?(ActiveRecord::Base) && c_klass.table_exists? &&
				 !a_klass.nil? && a_klass.ancestors.include?(ActiveRecord::Base) && !a_klass.table_exists?
				ActiveRecord::Schema.define do
					ActiveRecord::Migration.verbose = false

					create_table "#{parent_type.to_s.tableize}_#{child_type.to_s.tableize}".to_sym, :force => true, :id => false do |t|
						t.references parent_type
						t.references child_type
					end
				end
				
				#p_klass.reset_column_information
				#c_klass.reset_column_information
				a_klass.reset_column_information
			end
		end
		
		def self.drop_all_artifact_tables
			ActiveRecord::Schema.define do
				ActiveRecord::Migration.verbose = false
				ArtifactMigration::RallyArtifacts.constants.each do |c|
					klass = ArtifactMigration::RallyArtifacts.const_get(c)
					
					if klass.table_exists?
						remove_index c.to_s.tableize.to_sym, :object_i_d if index_exists? c.to_s.tableize.to_sym, :object_i_d
						drop_table c.to_s.tableize.to_sym
					end
				end
			end
		end
		
	end
end
