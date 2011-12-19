=begin

This file takes care of creating the database if it does not already exist and establishes a connection via ActiveRecord

=end

require 'sqlite3'
require 'active_record'
require 'fileutils'

module ArtifactMigration
  class DatabaseConnection
    def self.ensure_database_connection
      begin
        Logger.debug ActiveRecord::Base.connection_config
      rescue ActiveRecord::ConnectionNotEstablished
        connect_to_database
        retry
      end
    end

    def self.connect_to_database(dbfile = './db/artifacts.sqlite')
      #Dir.mkdir db_dir unless File.exists? db_dir
      FileUtils.mkdir_p File.dirname dbfile
      FileUtils.touch dbfile

      (SQLite3::Database.new(dbfile)).close

      ActiveRecord::Base.logger = ::Logger.new('active_record.log')
      ActiveRecord::Base.establish_connection(
      	:adapter => "sqlite3",
      	:database  => dbfile
      )

      ArtifactMigration::RallyArtifacts.create_artifact_classes
    end
  end
end