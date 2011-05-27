require 'active_support/inflector'

module ArtifactMigration
	class Exporter
		def self.run
			type = Configuration.singleton.source_config.export_source
			
			type = :rally_exporter if type.nil?
			type = :rally_exporter unless ArtifactMigration::RallyArtifacts.const_defined? type.to_s.classify
			
			exporter = ArtifactMigration::Exporters.const_get(type.to_s.classify.to_sym)
			
			exporter.run
	end
end