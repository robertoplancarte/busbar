# frozen_string_literal: true

module Busbar
  module OneRoster
    # Describes one OneRoster 1.2 CSV file: its exact header, how each column is
    # typed, and which other files it references.
    #
    # Column lists follow the 1EdTech OneRoster 1.2 CSV binding:
    # https://standards.1edtech.org/oneroster/specifications/standards/v1p2/csv
    FileSpec = Struct.new(
      :file,        # "users.csv"
      :schema,      # :users, the BusBar schema key
      :columns,     # exact header, in order
      :required,    # columns that must have a value (in addition to sourcedId)
      :references,  # { column => schema } for sourcedId references
      :multi_value, # columns holding comma-separated lists
      :enums,       # { column => [allowed values] }; "ext:" terms are always allowed
      :dates,       # YYYY-MM-DD columns
      :booleans,    # true/false columns
      :years,       # YYYY columns
      keyword_init: true
    ) do
      def field_name(column) = OneRoster.field_name(column)
      def fields = columns.map { |c| field_name(c) }
    end

    COMMON = %w[sourcedId status dateLastModified].freeze

    STATUS_VALUES = %w[active tobedeleted].freeze

    ROLE_VALUES = %w[
      aide counselor districtAdministrator guardian parent principal proctor
      relative siteAdministrator student systemAdministrator teacher
    ].freeze

    # Rostering files, in dependency order: every reference points at a file that
    # appears earlier in this list (or at the same file, for parent/agent links).
    # Gradebook and resource files (lineItems, results, resources, ...) are
    # recognised but not imported by this version; see UNSUPPORTED_FILES.
    FILE_SPECS = [
      FileSpec.new(
        file: "orgs.csv", schema: :orgs,
        columns: COMMON + %w[name type identifier parentSourcedId],
        required: %w[name type],
        references: { "parentSourcedId" => :orgs },
        multi_value: [],
        enums: { "type" => %w[department school district local state national] },
        dates: [], booleans: [], years: []
      ),
      FileSpec.new(
        file: "academicSessions.csv", schema: :academic_sessions,
        columns: COMMON + %w[title type startDate endDate parentSourcedId schoolYear],
        required: %w[title type startDate endDate schoolYear],
        references: { "parentSourcedId" => :academic_sessions },
        multi_value: [],
        enums: { "type" => %w[gradingPeriod semester schoolYear term] },
        dates: %w[startDate endDate], booleans: [], years: %w[schoolYear]
      ),
      FileSpec.new(
        file: "courses.csv", schema: :courses,
        columns: COMMON + %w[schoolYearSourcedId title courseCode grades orgSourcedId subjects subjectCodes],
        required: %w[title orgSourcedId],
        references: { "schoolYearSourcedId" => :academic_sessions, "orgSourcedId" => :orgs },
        multi_value: %w[grades subjects subjectCodes],
        enums: {}, dates: [], booleans: [], years: []
      ),
      FileSpec.new(
        file: "classes.csv", schema: :classes,
        columns: COMMON + %w[title grades courseSourcedId classCode classType location schoolSourcedId
                             termSourcedIds subjects subjectCodes periods],
        required: %w[title courseSourcedId classType schoolSourcedId termSourcedIds],
        references: { "courseSourcedId" => :courses, "schoolSourcedId" => :orgs,
                      "termSourcedIds" => :academic_sessions },
        multi_value: %w[grades termSourcedIds subjects subjectCodes periods],
        enums: { "classType" => %w[homeroom scheduled] },
        dates: [], booleans: [], years: []
      ),
      FileSpec.new(
        file: "users.csv", schema: :users,
        columns: COMMON + %w[enabledUser username userIds givenName familyName middleName identifier
                             email sms phone agentSourcedIds grades password userMasterIdentifier
                             preferredGivenName preferredMiddleName preferredFamilyName
                             primaryOrgSourcedId pronouns],
        required: %w[enabledUser givenName familyName],
        references: { "agentSourcedIds" => :users, "primaryOrgSourcedId" => :orgs },
        multi_value: %w[userIds agentSourcedIds grades],
        enums: {}, dates: [], booleans: %w[enabledUser], years: []
      ),
      FileSpec.new(
        file: "demographics.csv", schema: :demographics,
        columns: COMMON + %w[birthDate sex americanIndianOrAlaskaNative asian blackOrAfricanAmerican
                             nativeHawaiianOrOtherPacificIslander white demographicRaceTwoOrMoreRaces
                             hispanicOrLatinoEthnicity countryOfBirthCode stateOfBirthAbbreviation
                             cityOfBirth publicSchoolResidenceStatus],
        required: [],
        # A demographics record shares its sourcedId with the user it describes.
        references: { "sourcedId" => :users },
        multi_value: [],
        enums: {},
        dates: %w[birthDate],
        booleans: %w[americanIndianOrAlaskaNative asian blackOrAfricanAmerican
                     nativeHawaiianOrOtherPacificIslander white demographicRaceTwoOrMoreRaces
                     hispanicOrLatinoEthnicity],
        years: []
      ),
      FileSpec.new(
        file: "roles.csv", schema: :roles,
        columns: COMMON + %w[userSourcedId roleType role beginDate endDate orgSourcedId userProfileSourcedId],
        required: %w[userSourcedId roleType role orgSourcedId],
        references: { "userSourcedId" => :users, "orgSourcedId" => :orgs },
        multi_value: [],
        enums: { "roleType" => %w[primary secondary], "role" => ROLE_VALUES },
        dates: %w[beginDate endDate], booleans: [], years: []
      ),
      FileSpec.new(
        file: "enrollments.csv", schema: :enrollments,
        columns: COMMON + %w[classSourcedId schoolSourcedId userSourcedId role primary beginDate endDate],
        required: %w[classSourcedId schoolSourcedId userSourcedId role],
        references: { "classSourcedId" => :classes, "schoolSourcedId" => :orgs, "userSourcedId" => :users },
        multi_value: [],
        enums: { "role" => %w[administrator proctor student teacher] },
        dates: %w[beginDate endDate], booleans: %w[primary], years: []
      )
    ].freeze

    # Files the 1.2 binding defines that this extension does not import yet.
    # A package may contain them; they are reported as skipped, not rejected.
    UNSUPPORTED_FILES = %w[
      categories.csv classResources.csv courseResources.csv lineItemLearningObjectiveIds.csv
      lineItems.csv lineItemScoreScales.csv resources.csv resultLearningObjectiveIds.csv
      results.csv resultScoreScales.csv scoreScales.csv userProfiles.csv userResources.csv
    ].freeze

    MANIFEST_FILE = "manifest.csv"

    def self.file_spec(file) = FILE_SPECS.find { |s| s.file == file }
    def self.schema_spec(schema) = FILE_SPECS.find { |s| s.schema == schema.to_sym }

    # "sourcedId" -> "sourced_id", "primaryOrgSourcedId" -> "primary_org_sourced_id"
    def self.field_name(column)
      column.gsub(/([a-z\d])([A-Z])/, '\1_\2').downcase
    end
  end
end
