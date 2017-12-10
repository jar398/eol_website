class TraitBank::Slurp
  class << self
    delegate :query, to: TraitBank

    def load_csvs(resource)
      config = load_csv_config(resource)
      config.each { |filename, file_config| load_csv(filename, file_config) }
    end

    # TODO: (eventually) target_scientific_name: row.target_scientific_name
    def load_csv_config(resource)
      { "traits_#{resource.id}.csv" =>
        { 'Page' => [:page_id],
          'Trait' => %i[eol_pk resource_pk sex lifestage statistical_method source value_literal value_num\
                        object_page_id scientific_name],
          wheres: {
            # This will be applied to ALL rows:
            "1=1" => {
              matches: {
                predicate: 'Term { uri: row.predicate }',
                resource: "Resource { resource_id: #{resource.id} }"
              },
              merges: [
                [:page, :trait, :trait],
                [:trait, :predicate, :predicate],
                [:trait, :supplier, :resource]
              ],
            }, # default
            "#{is_blank('row.value_uri')} AND #{is_not_blank('row.units')}" =>
            {
              matches: { units: 'Term { uri: row.units }' },
              merges: [ [:trait, :units_term, :units] ]
            },
            "#{is_not_blank('row.value_uri')} AND #{is_blank('row.units')}" =>
            {
              matches: { object_term: 'Term { uri: row.value_uri }' },
              merges: [ [:trait, :object_term, :object_term] ]
            }
          }
        },

        "meta_traits_#{resource.id}.csv" =>
        {
          'MetaData' => %i[eol_pk sex lifestage statistical_method source value_literal value_num],
          wheres: {
            "1=1" => { # ALL ROWS
              matches: {
                trait: 'Trait { eol_pk: row.trait_eol_pk }',
                predicate: 'Term { uri: row.predicate }'
              },
              merges: [
                [:trait, :metadata, :metadata],
                [:metadata, :predicate, :predicate]
              ],
            }, # default
            "#{is_blank('row.value_uri')} AND #{is_not_blank('row.units')}" =>
            {
              matches: { units: 'Term { uri: row.units }' },
              merges: [ [:metadata, :units_term, :units] ]
            },
            "#{is_not_blank('row.value_uri')} AND #{is_blank('row.units')}" =>
            {
              matches: { object_term: 'Term { uri: row.value_uri }' },
              merges: [ [:metadata, :object_term, :object_term] ]
            }
          }
        }
      }
    end

    def load_csv(filename, config)
      wheres = config.delete(:wheres)
      nodes = config # what's left.
      wheres.each do |clause, where_config|
        load_csv_where(clause, filename: filename, config: where_config, nodes: nodes)
      end
    end

    def load_csv_where(clause, options = {})
      filename = options[:filename]
      config = options[:config]
      nodes = options[:nodes] # NOTE: this is neo4j "nodes", not EOL "Node"; unfortunate collision.
      merges = Array(config[:merges])
      matches = config[:matches]
      head =
        <<~LOAD_CSV_QUERY_HEAD
          USING PERIODIC COMMIT LOAD CSV WITH HEADERS FROM '#{Rails.configuration.eol_web_url}/#{filename}' AS row
          WITH row WHERE #{clause}
        LOAD_CSV_QUERY_HEAD
      # First, build all of the nodes:
      nodes.each { |label, attributes| build_nodes(label: label, attributes: attributes, head: head) }
      # Then the merges, one at a time:
      merges.each { |triple| merge_triple(triple: triple, head: head, nodes: nodes, matches: matches) }
    end

    def build_nodes(options)
      label = options[:label]
      attributes = options[:attributes].dup
      head = options[:head]
      name = label.downcase
      pk = attributes.shift # Pull the first attribute off...
      pk_val = autocast_val("row.#{pk}")
      q = "#{head}MERGE (#{name}:#{label} { #{pk}: #{pk_val} })"
      attribute_sets = []
      attributes.each do |attribute|
        value = autocast_val("row.#{attribute}")
        q << set_attribute(name, attribute, value, 'CREATE')
        q << set_attribute(name, attribute, value, 'MATCH')
      end
      query(q)
    end

    # NOTE: This code automatically makes integers out of any attribute ending in "_id" or "_num". BE AWARE!
    def autocast_val(value)
      # NOTE: This code automatically makes integers out of any attribute ending in "_id" or "_num". BE AWARE!
      value = "toInt(#{value})" if value =~ /_(num|id)$/
      value
    end

    def merge_triple(options)
      triple = options[:triple]
      head = options[:head]
      nodes = options[:nodes]
      matches = options[:matches]
      # merges: [ [:trait, :units_term, :units] ]
      # NOTE: #to_s to make matching simpler.
      subj = triple[0].to_s
      pred = triple[1].to_s
      obj  = triple[2].to_s
      q = head
      # MATCH any required nodes:
      nodes.each do |label, attributes|
        name = label.downcase
        next unless subj == name || obj == name
        pk = attributes.first
        pk_val = autocast_val("row.#{pk}")
        q += "\nMATCH (#{name}:#{label} { #{pk}: #{pk_val} })"
      end
      # MATCH any ... uhhh... matches required:
      matches.each do |name, match|
        # matches: { object_term: ':Term { uri: row.value_uri }' },
        name = name.to_s
        next unless subj == name || obj == name
        q += "\nMATCH (#{name}:#{match})"
      end
      # Then merge the triple:
      query("#{q}\nMERGE (#{subj})-[:#{pred}]->(#{obj})")
    end

    def set_attribute(name, attribute, value, on_set)
      "\nON #{on_set} SET #{name}.#{attribute} = #{value}"
    end

    def is_not_blank(field)
      "(#{field} IS NOT NULL AND TRIM(#{field}) <> '')"
    end

    def is_blank(field)
      "(#{field} IS NULL OR TRIM(#{field}) = '')"
    end
  end
end