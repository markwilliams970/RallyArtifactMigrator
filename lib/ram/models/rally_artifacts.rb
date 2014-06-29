require 'active_record'
require 'active_support/inflector'

module ArtifactMigration
	class Attachment < ActiveRecord::Base
	end
	
	class Project < ActiveRecord::Base
  end
  
  class ProjectPermission < ActiveRecord::Base
  end

  class WorkspacePermission < ActiveRecord::Base
  end
  
  class Owners < ActiveRecord::Base
  end
  
  class AttributeValues < ActiveRecord::Base
  end

	module RallyArtifacts		
		def self.create_artifact_classes
			ArtifactMigration::UE_TYPES.each do |type|
				klass = ArtifactMigration::RallyArtifacts.const_set(type.to_s.classify, Class.new(ActiveRecord::Base))
                puts "type: #{type}"
				klass.set_inheritance_column "inheritance_type"
				#klass.const_set(:is_rally_artifact, true)
			end
			
			Logger.debug("RallyArtifacts constants - #{ArtifactMigration::RallyArtifacts.constants}")
		end
		
		def self.create_artifact_association(parent, child, type = :one_to_many)
			if type == :one_to_many
				ArtifactMigration::Schema.create_one_to_many_association parent, child
				
				get_artifact_class(parent).has_many child
				get_artifact_class(child).belongs_to parent
			elsif type == :one_to_many_self
				
			elsif type == :many_to_many
				a_klass_name = "#{parent.to_s}_#{child.to_s}"
				a_klass = ArtifactMigration::RallyArtifacts.const_set(a_klass_name.classify, Class.new(ActiveRecord::Base))
				a_klass.const_set(:is_rally_artifact, false)
				
				ArtifactMigration::Schema.create_many_to_many_association parent, child
				
				get_artifact_class(parent).has_many child, :through => a_klass_name.to_sym
				get_artifact_class(child).has_many parent, :through => a_klass_name.to_sym
			else
				Logger.debug("Unknown association type: #{type}")
			end
		end
		
		def self.instantiate_artifact(type)
			get_artifact_class(type).new unless get_artifact_class(type).nil?
		end
		
		def self.get_artifact_class(type)
			ArtifactMigration::RallyArtifacts.const_get(type.to_s.classify.to_sym) if ArtifactMigration::RallyArtifacts.const_defined? type.to_s.classify
		end
	end
	
	module RallyAssociations
		# Place holder module for holding the 
	end
end	