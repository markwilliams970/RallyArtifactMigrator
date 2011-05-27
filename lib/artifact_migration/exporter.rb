require 'active_support/inflector'

module ArtifactMigration
	class Exporter
		def self.run
			type = Configuration.singleton.source_config.export_source
			
			type = :rally if type.nil?
			type = :rally unless ArtifactMigration::RallyArtifacts.const_defined? type.to_s.classify
			
			exporter = case
			when type == :rally
				ArtifactMigration::Exporters::RallyExporter
			else
				ArtifactMigration::Exporters.const_get(type.to_s.classify.to_sym)
			
			exporter.run
	end
end