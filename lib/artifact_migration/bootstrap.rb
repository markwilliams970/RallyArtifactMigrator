=begin

This file takes care of creating the database if it does not already exist and establishes a connection via ActiveRecord

=end

require 'sqlite3'
require 'active_record'
require 'fileutils'

def ensure_database_connection
  begin
    Logger.debug ActiveRecord::Base.connection_config
  rescue ActiveRecord::ConnectionNotEstablished
    connect_to_database
    retry
  end
end

def connect_to_database(file = nil)
  db_dir = "db"
  db_name = "artifacts.sqlite3"
  
  if file.nil?
    db = File.join(db_dir, db_name)
  else
    db = file
  end

  #Dir.mkdir db_dir unless File.exists? db_dir
  FileUtils.mkdir_p File.dirname db

  (SQLite3::Database.new(db)).close

  ActiveRecord::Base.logger = ::Logger.new('active_record.log')
  ActiveRecord::Base.establish_connection(
  	:adapter => "sqlite3",
  	:database  => db
  )

  ArtifactMigration::RallyArtifacts.create_artifact_classes
end