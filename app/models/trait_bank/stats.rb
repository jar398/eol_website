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
    MIN_RECORDS_FOR_HIST = 4
    OBJ_COUNT_LIMIT_PAD = 5

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
            "LIMIT #{limit + OBJ_COUNT_LIMIT_PAD}"
          results = TraitBank.query(qs)
          filter_identical_count_descendants(TraitBank.results_to_hashes(results, "obj"), limit)
        end
      end

      # XXX: this isn't very performant, but the assumption is that that the filtering case is rare
      def filter_identical_count_descendants(results, limit)
        prev_count = nil
        objs_to_check = {}
        objs_for_count = []

        results.each do |row|
          if row[:count] != prev_count
            if objs_for_count.length > 1
              objs_to_check[prev_count] = objs_for_count
            end

            prev_count = row[:count]
            objs_for_count = [row[:obj][:uri]]
          else 
            objs_for_count << row[:obj][:uri]
          end
        end

        objs_to_filter = []
        objs_to_check.each do |_, objs|
          objs.each do |obj|
            objs.each do |other_obj|
              next if obj == other_obj
              objs_to_filter << obj if TraitBank::Terms.term_descendant_of_other?(obj, other_obj)
            end
          end 
        end

        filtered = results.reject { |r| objs_to_filter.include?(r[:obj][:uri]) }
        filtered[0..limit]
      end

      # Returns:
      # bi: bucket index
      # bw: bucket width
      # c: count of records/pages in bucket
      # u: units term
      def histogram(query, record_count)
        check_tq_for_histogram(query, record_count)

        key = "trait_bank/stats/histogram/v1/#{query.to_cache_key}" # increment version number when changing query
        Rails.cache.fetch(key) do
          filter = query.filters.first

          wheres = ["t.normal_measurement IS NOT NULL"]
          wheres << "toFloat(t.normal_measurement) >= #{filter.num_val1}" if filter.num_val1.present?
          wheres << "toFloat(t.normal_measurement) <= #{filter.num_val2}" if filter.num_val2.present?

          count = query.record? ? "*" : "DISTINCT rec.page"

          buckets = [Math.sqrt(record_count), 20].min.ceil
          TraitBank.query(%Q[
            MATCH #{TraitBank.page_match(query, "page", "")},
            (tgt_p:Term{ uri: '#{filter.pred_uri}'}),
            (page)-[#{TraitBank::TRAIT_RELS}]->(t:Trait)-[:predicate]->(:Term)-[#{TraitBank.parent_terms}]->(tgt_p),
            (t)-[:normal_units_term]->(u:Term)
            WITH page, u, toFloat(t.normal_measurement) AS m
            WHERE #{wheres.join(" AND ")}
            WITH u, collect({ page: page, val: m }) as recs, max(m) AS max, min(m) AS min
            WITH u, recs, max, min, max - min AS range
            WITH u, recs, #{self.num_fn_for_range("max", "ceil")} AS max,
            #{self.num_fn_for_range("min", "floor")} AS min
            WITH u, recs, max, min, max - min AS range
            WITH u, recs, max, min, CASE WHEN range < .001 THEN 1 ELSE (
            #{self.num_fn_for_range("range", "ceil", "/ #{buckets}")}
            ) END AS bw
            UNWIND recs as rec
            WITH rec, u, min, bw, floor((rec.val - min) / bw) AS bi
            WITH rec, u, min, bw, CASE WHEN bi = #{buckets} THEN bi - 1 ELSE bi END as bi
            WITH u, min, bi, bw, count(#{count}) AS c
            WITH u, collect({ min: min, bi: bi, bw: bw, c: c}) as units_rows
            ORDER BY reduce(total = 0, r in units_rows | total + r.c) DESC
            LIMIT 1
            UNWIND units_rows as r
            WITH u, r.min as min, r.bi as bi, r.bw as bw, r.c as c
            RETURN u, min, bi, bw, c
            ORDER BY bi ASC
          ])
        end
      end

      def num_fn_for_range(var, fn, add_op = nil)
        base_case  = add_op.nil? ?
          "#{fn}(#{var})" :
          "#{fn}(#{var} #{add_op})"

        %Q(
          CASE WHEN #{num_fn_for_range_case(0.002, 10000, fn, var, add_op)} ELSE (
            CASE WHEN #{num_fn_for_range_case(0.02, 1000, fn, var, add_op)} ELSE (
              CASE WHEN #{num_fn_for_range_case(0.2, 100, fn, var, add_op)} ELSE (
                CASE WHEN #{num_fn_for_range_case(2, 10, fn, var, add_op)} ELSE (
                  #{base_case}
                ) END
              ) END
            ) END
          ) END
        )
      end

      def num_fn_for_range_case(cutoff, coef, fn, var, add_op)
        fn_part = add_op.nil? ?
          "#{fn}(#{var} * #{coef}) / #{coef}" :
          "#{fn}((#{var} * #{coef}) #{add_op}) / #{coef}"

        "range < #{cutoff} THEN #{fn_part}"
      end

      #  "WITH ms, init_max, min, bw, (init_max - min) % bw as rem\n"\
      #  "WITH ms, min, bw, CASE WHEN rem = 0 THEN init_max ELSE init_max + bw - rem END AS max\n"\

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

        CheckResult.valid
      end

      def check_query_valid_for_histogram(query, record_count)
        if record_count < MIN_RECORDS_FOR_HIST
          return CheckResult.invalid("record count doesn't meet minimum of #{MIN_RECORDS_FOR_HIST}")
        end

        common_result = check_measurement_query_common(query)
        return common_result if !common_result.valid?

        if !query.filters.first.units_for_pred?
          return CheckResult.invalid("query predicate does not have numerical values")
        end

        if !TraitBank::Terms.any_direct_records_for_pred?(query.filters.first.pred_uri)
          return CheckResult.invalid("predicate does not have any directly associated records")
        end

        CheckResult.valid
      end


      def check_query_valid_for_counts(query, record_count)
        common_result = check_measurement_query_common(query)
        return common_result if !common_result.valid?

        filter = query.filters.first
        uri = filter.pred_uri

        if filter.units_for_pred?
          return CheckResult.invalid("query predicate has numerical values")
        end

        if filter.numeric?
          return CheckResult.invalid("query must not be numeric")
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

      def check_tq_for_histogram(query, record_count)
        result = check_query_valid_for_histogram(query, record_count)

        if !result.valid
          raise TypeError.new(result.reason)
        end
      end
    end
  end
end

