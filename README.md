= Rally Artifact Migration

Rally Artifact Migration utility.

== Installation Instructions

=== Mac OS X

* Install Xcode (for compiling SQLite3)
* From the command line type: sudo gem install ram-latest.gem --no-rdoc --no-ri

=== Ubuntu

* Install GCC (for compiling SQLite3)
* sudo apt-get install libsqlite3-dev
* sudo gem install ram-latest.gem --no-rdoc --no-ri

=== Windows

* Not sure about prereqs, but you need to be able to install SQLite3
* From the command line type: gem install ram-latest.gem --no-rdoc --no-ri

== Configuration Options
=== General
* username <STRING>                                    | Sets the username                                                                | source.username "youraccount@domain.com"
* password <STRING>                                    | Sets the password                                                                | source.password "S3cr3t"
* server <STRING>                                      | Sets the server                                                                  | source.server "https://rally1.rallydev.com"
* workspace_oid <INTEGER>                              | Set which workspace to migrate                                                   | source.workspace_oid 123456
* project_scope_up <BOOLEAN>                           |                                                                                  | source.project_scope_up false
* project_scope_down <BOOLEAN>                         |                                                                                  | source.project_scope_down false
* version <STRING>                                     | Webservice API Version                                                           | source.version "1.36"$* 
* migrate_type <TYPE_SYMBOL>                           | Add a type to be migrated                                                        | source.migrate_type :defect$* 
* dont_migrate_type <TYPE_SYMBOL>                      | Removes a type to be migrated                                                    | target.dont_migrate_type :test_case_results$* 
* migrate_ee_types                                     | Migrates all types available under the Enterprise Edition (excepted Attachments) | target.migrate_ee_types$* 
* migrate_ue_types                                     | Migrates all types available under the Unlimited Edition (excepted Attachments   | source.migrate_ue_types$* 
* migrate_attachments                                  | Instructs RAM to migrate attachments (WSAPI Version >=1.32)                      | source.migrate_attachments$* 
* migrate_projects                                     | Instructs RAM to migrate project information                                     | source.migrate_projects$* 
* migrate_project_children                             | Instructs RAM to migrate child projects of projects added with add_project_oid   | source.migrate_child_projects$* 
* migrate_project_permissions                          | Copy the project permissions                                                     | target.migrate_project_permissions$* 

=== Source Only Options
add_project_oid <INTEGER>                            | Adds a project to be migrated                                                    | source.add_project_oid 654321

=== Target Only Options
map_project_oid :from => <INTEGER>, :to => <INTEGER> | Map a project in the source to an already created project in the target          | target.map_project_oid :from => 12345, :to => 45678
map_username :from => <STRING>, :to => <STRING>      | Map a username in the source workspace to a user in the destination workspace    | target.map_username :from => "jim@acme.com", :to => "tim@acme.com"


== Release Notes

* Custom fields that contain special characters are not migrated.
* Custom fields that have multiple capital letters in a row are not migrated.
* PI States are not migrated
* DynaTypes are not supported

=== 0.6.5
* [FEATURE] Added option to target configuration 'map_artifact' that take the form `target.map_artifact :type => :RALLY_TYPE_NAME, :from => 1111, :to => 2222`

=== 0.6.4
* [BUG] Fixed attachment issue.

=== 0.6.3
* [BUG] ReRanking was broken when I moved to the new RallyJsonAPI.  Added a new import phase to compensate.

=== 0.6.2
* [FEATURE] Added migrate_project_permissions flag.  This was originally implicit with the migrate_project flag, but it made since to split them out

=== 0.6.1
* [FEATURE] Added migrate_child_projects configuration option.  Specifying a parent project with migrate_project along with this new flag will export/import a project tree

=== 0.6.0
* [FEATURE] Migrated most of import task to use the new RallyJsonAPI
* [FEATURE] Changed Attachment import to use new Attachment create and AttachmentContent create endpoints
* [BUG] A major issue cropped up with the RallyRestAPI that necessitated a change to the new RallyJsonAPI

=== 0.5.x
* Dead version.  Tried to modularize it for multi-threaded import.  Results were not favorable :)

=== 0.4.3
* [FEATURE] Added ability to specify location of database in config file
* [FEATURE] Added --reset option to CLI.  Option resets the transaction log (main usefulness is for testing and demo data loading)

=== 0.4.2
* [FEATURE] Changed default WSAPI from 1.28 to 1.29
* [FEATURE] Added support for new Attachment Endpoint
* [BUG] Fixed random issues when trying to continue on import error

=== 0.4.1
* [FEATURE] Changed default WSAPI from 1.27 to 1.28
* [BUG] The attribute on Portfolio Items to designate type was changed to "Portfolio Item Type". RAM now uses the new attribute name.

=== 0.4.0
* [FEATURE] Added RPM support
* [FEATURE] Migrate Projects
* [FEATURE] Migrate User Permissions (not users)
* [FEATURE] Continue import on error if possible (new table that will list which artifacts were partially imported)
* [FEATURE] Renamed ArtifactMigration::TYPICAL_TYPES to ArtifactMigration::EE_TYPES
* [FEATURE] Renamed ArtifactMigration::VALID_TYPES to ArtifactMigration::UE_TYPES
* [FEATURE] Added :portfolio_item to ArtifactMigration::UE_TYPES
* [BUG] Fixed verification issue where source was used instead of target (Thx Barry and Dave)

=== 0.3.4

* [BUG] Fixed WebLink not handled properly during import
* [FEATURE] Enhanced Console output.  Progress bar for each phase.
* [FEATURE] Publish events (using Event Emitter pattern) for each phase.

=== 0.3.3

* [FEATURE] ConfigurationDefinition.map_username_by_csv added. Options are  :file, :from_column, :to_column.
* [FEATURE] ConfigurationDefinition.default_username added.  Allows a default user to be used if a user in the source workspace was not moved to the target workspace.
* [FEATURE] Debug log enabled by default in example config file.
* [BUG] Custom field mapping in ConfigurationDefintion was not working.
* [BUG] Ignore field in target configuration was not used.

=== 0.3.2

* [BUG] Dependency issue when Rails 2.x is installed

=== 0.3.1

* [BUG] Attachment import doesn't work if the user's Default Workspace is not set to the config's target workspace
* [BUG] Failed Attachment import is not detected.  Outputs success message

=== 0.3.0

* [FEATURE] Config option 'migrate_attachments' added
* [FEATURE] Export Attachments
* [FEATURE] Import Attachments

=== 0.2.2

* [BUG] RQM not detected
* [BUG] ArtifactMigration::Version string not used in X-RallyIntegration-Version header

=== 0.2.1

* [FEATURE] Uses X-RallyIntegration-* headers for integration tracking
* [BUG] Arrays serialized with to_s instead of to_json

=== 0.2.0

* [FEATURE] Added ability to migrate Test Sets

=== 0.1.0

Initial release.  Can migrate most types of artifacts from one project to another.


== Contributing to ram
 
* Email Colin (cobrien@rallydev.com)

== Copyright

Copyright (c) 2011 Rally Software. See LICENSE.txt for
further details.

