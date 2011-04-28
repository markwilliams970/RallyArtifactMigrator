=begin

This file takes care of creating the database if it does not already exist and establishes a connection via ActiveRecord

=end

require 'sqlite3'
require 'active_record'

db_dir = "db"
db_name = "artifacts.sqlite3"

Dir.mkdir db_dir unless File.exists? db_dir

(SQLite3::Database.new(File.join(db_dir, db_name))).close

ActiveRecord::Base.logger = ::Logger.new('active_record.log')
ActiveRecord::Base.establish_connection(
	:adapter => "sqlite3",
	:database  => File.join(db_dir, db_name)
)

ArtifactMigration::RallyArtifacts.create_artifact_classes