class TraitBank
  class Stats
    CheckResult = Struct.new(:valid, :reason) do
      def valid?
        valid
      end

      def self.invalid(reason)
        self.new(false, reason)
      end

      def self.valid
        self.new(true, nil)
      end
    end

    PRED_URIS_FOR_THRESHOLD = Set.new([
      Eol::Uris.habitat_includes,
      Eol::Uris.geographic_distribution,
      Eol::Uris.trophic_level,
      Eol::Uris.ecoregion
    ])
    RECORD_THRESHOLD = 20_000

    class << self
      def obj_counts(query, record_count, limit)
        check_tq_for_counts(query, record_count)
        filter = query.filters.first
        count = query.taxa? ? "distinct page" : "*"
        key = "trait_bank/stats/obj_counts/v1/limit_#{limit}/#{query.to_cache_key}" # increment version number when changing query

        Rails.cache.fetch(key) do
          Rails.logger.info("TraitBank::Stats.object_counts -- running query for key #{key}")
          # Where clause filters for top-level terms or their direct children only
          # WITH DISTINCT is necessary to filter out multiple paths from obj_child to obj (I think?)
          # "WHERE NOT (obj)-[:parent_term*2..]->(:Term)\n"\ removed
          qs = "MATCH #{TraitBank.page_match(query, "page", "")},\n"\
            "(page)-[#{TraitBank::TRAIT_RELS}]->(trait:Trait),\n"\
            "(trait)-[:predicate]->(:Term)-[#{TraitBank.parent_terms}]->(:Term{uri: '#{filter.pred_uri}'}),\n"\
            "(trait)-[:object_term]->(:Term)-[#{TraitBank.parent_terms}]->(obj:Term)\n"\
            "WITH DISTINCT page, trait, obj\n"\
            "WHERE obj.is_hidden_from_select = false\n"\
            "WITH obj, count(#{count}) AS count\n"\
            "RETURN obj, count\n"\
            "ORDER BY count DESC\n"\
            "LIMIT #{limit}"
          results = TraitBank.query(qs)
          TraitBank.results_to_hashes(results, "obj")
        end
      end

      def check_measurement_query_common(query)
        if query.predicate_filters.length != 1
          return CheckResult.invalid("query must have a single predicate filter")
        end

        uri = query.predicate_filters.first.pred_uri
        predicate = TermNode.find(uri)

        if predicate.nil?
          return CheckResult.invalid("failed to retrieve a Term with uri #{uri}")
        end

        if predicate.type != "measurement"
          return CheckResult.invalid("predicate type must be 'measurement'")
        end

        if query.object_term_filters.any?
          return CheckResult.invalid("query must not have any object term filters")
        end

        if query.numeric_filters.any?
          return CheckResult.invalid("query must not have any numeric filters")
        end
        
        if query.range_filters.any?
          return CheckResult.invalid("query must not have any range filters")
        end

        CheckResult.valid
      end

      def check_query_valid_for_histogram(query, record_count)
        common_result = check_measurement_query_common(query)
        return common_result if !common_result.valid?

        if !query.filters.first.units_for_pred?
          return CheckResult.invalid("query predicate does not have numerical values")
        end

        CheckResult.valid
      end


      def check_query_valid_for_counts(query, record_count)
        common_result = check_measurement_query_common(query)
        return common_result if !common_result.valid?

        if query.filters.first.units_for_pred?
          return CheckResult.invalid("query predicate has numerical values")
        end

        if (
            query.clade.present? &&
            PRED_URIS_FOR_THRESHOLD.include?(uri) &&
            record_count > RECORD_THRESHOLD
        )
          return CheckResult.invalid("count exceeds threshold for uri")
        end

        CheckResult.valid
      end

      private
      def check_tq_for_counts(query, record_count)
        result = check_query_valid_for_counts(query, record_count)

        if !result.valid
          raise TypeError.new(result.reason)
        end
      end
    end
  end
end
