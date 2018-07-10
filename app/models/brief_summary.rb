# At the time of writing, this was an implementation of
# https://github.com/EOL/eol_website/issues/5#issuecomment-397708511 and
# https://github.com/EOL/eol_website/issues/5#issuecomment-402848623
class BriefSummary
  def initialize(page)
    @page = page
    @sentences = []
    @a1_name = nil
    @a2_node = nil
    @a2_name = nil
  end

  # NOTE: this will only work for these specific ranks (in the DWH). This is by design (for the time-being). # NOTE: I'm
  # putting species last because it is the most likely to trigger a false-positive. :|
  def english
    # There's really nothing to do if there's no minimal ancestor:
    return '' if a1.nil?
    if is_family?
      family
    elsif is_genus?
      genus
    elsif is_species?
      species
    end
    return '' if @sentences.empty?
    @sentences.join(' ')
  end

  # [name clause] is a[n] [A1] in the family [A2].
  def species
    # taxonomy sentence:
    # TODO: this assumes perfect coverage of A1 and A2 for all species, which is a bad idea. Have contingencies.
    what = a1
    family = a2
    if family
      @sentences << "#{name_clause} is a species of #{what} in the family #{a2}."
    else
      # We may have a few species that don't have a family in their ancestry. In those cases, shorten the taxonomy
      # sentence: [name clause] is a[n] [A1].
      @sentences << "#{name_clause} is a species of #{what}."
    end
    # If the species [is extinct], insert an extinction status sentence between the taxonomy sentence
    # and the distribution sentence. extinction status sentence: This species is extinct.
    @sentences << 'This species is extinct.' if is_it_extinct?
    # If the species [is marine], insert an environment sentence between the taxonomy sentence and the distribution
    # sentence. environment sentence: "It is marine." If the species is both marine and extinct, insert both the
    # extinction status sentence and the environment sentence, with the extinction status sentence first.
    @sentences << 'It is marine.' if is_it_marine?
    # Distribution sentence: It is found in [G1].
    @sentences << "It is found in #{g1}." if g1
  end

  # [name clause] is a genus in the [A1] family [A2].
  #
  def genus
    family = a2
    if family
      @sentences << "#{name_clause} is a genus of #{a1} in the family #{family}."
    else
      @sentences << "#{name_clause} is a family of #{a1}."
    end
    # We may have a few genera that don't have a family in their ancestry. In those cases, shorten the taxonomy sentence:
    # [name clause] is a genus in the [A1]
  end

  # [name clause] is a family of [A1].
  #
  # This will look a little funny for those families with "family" vernaculars, but I think it's still acceptable, e.g.,
  # Rosaceae (rose family) is a family of plants.
  def family
    @sentences << "#{name_clause} is a family of #{a1}."
  end

  # NOTE: Landmarks on staging = {"no_landmark"=>0, "minimal"=>1, "abbreviated"=>2, "extended"=>3, "full"=>4} For P.
  # lotor, there's no "full", the "extended" is Tetropoda, "abbreviated" is Carnivora, "minimal" is Mammalia. JR
  # believes this is usually a Class, but for different types of life, different ranks may make more sense.

  # A1: Use the landmark with value 1 that is the closest ancestor of the species. Use the English vernacular name, if
  # available, else use the canonical.
  def a1
    return @a1_name if @a1_name
    @a1 ||= @page.ancestors.reverse.find { |a| a.minimal? }
    return nil if @a1.nil?
    @a1_name = @a1.vernacular&.singularize
    @a1_name ||= @a1.canonical
    # A1: There will be nodes in the dynamic hierarchy that will be flagged as A1 taxa. If there are vernacularNames
    # associated with the page of such a taxon, use the preferred vernacularName.  If not use the scientificName from
    # dynamic hierarchy. If the name starts with a vowel, it should be preceded by an, if not it should be preceded by
    # a.
  end

  # A2: Use the name of the family (i.e., not a landmark taxon) of the species. Use the English vernacular name, if
  # available, else use the canonical. -- Complication: some family vernaculars have the word "family" in then, e.g.,
  # Rosaceae is the rose family. In that case, the vernacular would make for a very awkward sentence. It would be great
  # if we could implement a rule, use the English vernacular, if available, unless it has the string "family" in it.
  def a2
    return @a2_name if @a2_name
    return nil if a2_node.nil?
    @a2_name = a2_node.vernacular
    @a2_name = nil if @a2_name && @a2_name =~ /family/i
    @a2_name ||= a2_node.canonical_form
  end

  def a2_node
    @a2_node ||= @page.ancestors.reverse.find { |a| a.abbreviated? }
  end

  # Geographic data (G1) will initially be sourced from a pair of measurement types:
  # http://rs.tdwg.org/dwc/terms/continent, http://rs.tdwg.org/dwc/terms/waterBody (not yet available, but for testing
  # you can use: http://rs.tdwg.org/ontology/voc/SPMInfoItems#Distribution) Some taxa may have multiple values, and
  # there may be some that have both continent and waterBody values. If there is no continent or waterBody information
  # available, omit the second sentence.
  # TODO: these URIs are likely to change, check with JH again when you get back to these.
  def g1
    @g1 ||= values_to_sentence(['http://rs.tdwg.org/dwc/terms/continent', 'http://rs.tdwg.org/dwc/terms/waterBody', 'http://rs.tdwg.org/ontology/voc/SPMInfoItems#Distribution'])
  end

  def name_clause
    @name_clause ||=
      if @page.vernacular
        "#{@page.canonical} (#{@page.vernacular.string})"
      else
        @page.canonical
      end
  end

  # ...has a value with parent http://purl.obolibrary.org/obo/ENVO_00000447 for measurement type
  # http://eol.org/schema/terms/Habitat
  def is_it_marine?
    if @page.has_checked_marine?
      @page.is_marine?
    else
      marine =
        has_data(predicates: ['http://eol.org/schema/terms/Habitat'],
                 values: ['http://purl.obolibrary.org/obo/ENVO_00000447'])
      @page.update_attribute(:has_checked_marine, true)
      # NOTE: this DOES NOT WORK without the true / false thing. :|
      @page.update_attribute(:is_marine, marine ? true : false)
      marine
    end
  end

  def has_data(options)
    recs = []
    gather_terms(options[:predicates]).each do |term|
      next if @page.grouped_data[term].nil?
      next if @page.grouped_data[term].empty?
      recs += @page.grouped_data[term]
    end
    recs.compact!
    return nil if recs.empty?
    values = gather_terms(options[:values])
    return nil if values.empty?
    return true if recs.any? { |r| r[:object_term] && values.include?(r[:object_term][:uri]) }
    return false
  end

  def gather_terms(uris)
    terms = []
    Array(uris).each { |uri| terms += TraitBank.descendants_of_term(uri).map { |t| t['uri'] } }
    terms.compact
  end

  # has value http://eol.org/schema/terms/extinct for measurement type http://eol.org/schema/terms/ExtinctionStatus
  def is_it_extinct?
    if @page.has_checked_extinct?
      @page.is_extinct?
    else
      # NOTE: this relies on #displayed_extinction_data ONLY returning an "exinct" record. ...which, as of this writing,
      # it is designed to do.
      @page.update_attribute(:has_checked_extinct, true)
      if @page.displayed_extinction_data # TODO: this method doesn't check descendants yet.
        @page.update_attribute(:is_extinct, true)
        return true
      else
        @page.update_attribute(:is_extinct, false)
        return false
      end
    end
  end

  # Print all values, separated by commas, with “and” instead of comma before the last item in the list.
  def values_to_sentence(uris)
    values = []
    uris.flat_map { |uri| gather_terms(uri) }.each do |term|
      @page.grouped_data[term].each do |trait|
        if trait.key?(:object_term)
          values << trait[:object_term][:name]
        else
          values << trait[:literal]
        end
      end
    end
    values.any? ? values.uniq.to_sentence : nil
  end

  # TODO: it would be nice to make these into a module included by the Page class.
  def is_species?
    is_rank?('r_species')
  end

  def is_family?
    is_rank?('r_family')
  end

  def is_genus?
    is_rank?('r_genus')
  end

  # NOTE: the secondary clause here is quite... expensive. I recommend we remove it, or if we keep it, preload ranks.
  # NOTE: Because species is a reasonable default for many resources, I would caution against *trusting* a rank of
  # species for *any* old resource. You have been warned.
  def is_rank?(rank)
    if @page.rank
      @page.rank.treat_as == rank
    else
      @page.nodes.any? { |n| n.rank&.treat_as == rank }
    end
  end

  def rank_or_clade(node)
    node.rank.try(:name) || "clade"
  end

  # Note: this does not always work (e.g.: "an unicorn")
  def a_or_an(word)
    %w(a e i o u).include?(word[0].downcase) ? "an #{word}" : "a #{word}"
  end
end
