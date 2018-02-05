# For connecting to the website Database. NOTE: This code is not especially concerned about SQL-injection, as the data
# are all either from a trusted database or from a trusted resource file. NOTHING HERE COMES FROM USERS.
class WebDb < ActiveRecord::Base
  self.abstract_class = true
  cfg = ActiveRecord::Base.configurations[Rails.env]
  # TODO: pull from "web" namespace... and start using secrets in this codebase too... :\
  cfg['host']     = Rails.application.secrets.db['host']
  cfg['database'] = Rails.application.secrets.db['name']
  cfg['username'] = Rails.application.secrets.db['username']
  cfg['password'] = Rails.application.secrets.db['password']
  cfg['port']     = Rails.application.secrets.db['port']
  establish_connection cfg

  class << self
    def now
      Time.now.to_s(:db)
    end

    def columns(table)
      response = connection.exec_query("DESCRIBE #{table}")
      names = response.rows.map(&:first)
      names.map(&:to_sym)
    end

    def raw_create(table, hash)
      vals = hash.values.map { |val| quote_value(val) }
      connection.exec_insert("INSERT INTO #{table} (#{hash.keys.join(', ')}) VALUES (#{vals.join(',')})", 'SQL', vals)
      WebDb.connection.last_inserted_id(table)
    end

    def quote_value(val)
      return 'NULL' if val.nil?
      return val if val.is_a?(Numeric)
      return 1 if val.is_a? TrueClass
      return 0 if val.is_a? FalseClass
      "'#{val.to_s.gsub(/'/, "''")}'"
    end

    # Ranks need to be updated as soon as they are inserted, argh...
    def raw_create_rank(name)
      id = raw_create('ranks', { name: name })
      connection.exec_update("UPDATE ranks SET treat_as = #{id} WHERE ID = #{id}", 'SQL', [id, id])
      id
    end

    def map_ids(table, field)
      response = connection.exec_query("SELECT id, #{field} FROM #{table}")
      map = {}
      response.rows.each do |row|
        map[row[1]] = row[0]
      end
      map
    end

    def remove_resource_data(table, resource_id)
      connection.execute("DELETE FROM #{table} WHERE resource_id = #{resource_id}")
    end

    def import_csv(file, table, cols = nil)
      q = ['LOAD DATA']
      q << 'LOCAL' unless Rails.env.development?
      q << "INFILE '#{file}'"
      q << 'REPLACE ' unless cols
      q << "INTO TABLE `#{table}`"
      q << "(#{cols.join(',')})" if cols
      begin
        connection.execute(q.join(' '))
      rescue => e
        puts e.message
        debugger
        1
      end
    end

    def resource_id(resource)
      id = find_by_repo_id(:resources, resource.id)
      return id unless id.nil?
      create_resource(resource)
    end

    def partner_id(partner)
      id = find_by_repo_id(:partners, partner.id)
      return id unless id.nil?
      create_partner(partner)
    end

    def create_resource(resource)
      common_fields = %i[nodes_count name abbr description notes is_browsable]
      create_from_object(resource, common_fields) do |hash|
        hash[:has_duplicate_nodes] = !resource.might_have_duplicate_taxa?
        hash[:partner_id] = partner_id(resource.partner)
        hash[:repository_id] = resource.id
      end
    end

    def create_partner(partner)
      common_fields = %i[name abbr short_name homepage_url description links_json]
      create_from_object(partner, common_fields) do |hash|
        hash[:repository_id] = partner.id
      end
    end

    def create_from_object(object, common_fields, &block)
      hash = {}
      common_fields.each do |field|
        hash[field] = object[field]
      end
      yield(hash) if block
      hash[:updated_at] = hash[:created_at] = now
      table = object.class.table_name
      raw_create(table, hash)
      connection.last_inserted_id(table)
    end

    def find_by_repo_id(table, id)
      rows = connection.exec_query("SELECT id FROM `#{table}` WHERE repository_id = #{id} LIMIT 1").rows
      rows.empty? ? nil : rows[0][0]
    end
  end
end