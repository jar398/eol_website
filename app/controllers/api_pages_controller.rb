class ApiPagesController < LegacyApiController
  def index
    respond_to do |format|
      set_default_params
      get_pages
      if @pages.empty?
        return raise ActionController::RoutingError.new('Not Found')
      end
      format.json { render json: @pages }
      format.xml do
        if @pages.keys.first.is_a?(Integer)
          # XML cannot use integers as tags!
          @pages = @pages.values
        end
        render xml: @pages.to_xml
      end
    end
  end

  def pred_prey
    page = Page.find(params[:id])

    respond_to do |format|
      format.json do
        render json: (Rails.cache.fetch("pages/#{page.id}/pred_prey_json", expires: 1.day) do
          if !page.rank&.r_species? # all nodes must be species, so bail
            { nodes: [], links: [] }
          else
            relationships = TraitBank.pred_prey_comp_for_page(page)
            prey_ids = Set.new
            predator_ids = Set.new
            competitor_ids = Set.new

            links = relationships.map do |row|
              if row[:type] == "prey"
                prey_ids.add(row[:target])
              elsif row[:type] == "predator"
                predator_ids.add(row[:source])
              elsif row[:type] == "competitor"
                competitor_ids.add(row[:source])
              else
                raise "unrecognized relationship type in result: #{row[:type]}"
              end

              {
                source: row[:source],
                target: row[:target],
                sourceType: row[:type] == "predator" ? "predator" : "selfOrCompetitor" # links are treated differently based on this in the visualization
              }
            end

            all_ids = Set.new([page.id])
            all_ids.merge(prey_ids).merge(predator_ids).merge(competitor_ids)
            nodes = {}
            ids_to_remove = Set.new

            pages = Page.where(id: all_ids.to_a).includes(:native_node).map do |page|
              [page.id, page]
            end.to_h

            pages_to_nodes([page.id], :source, pages, nodes, ids_to_remove)
            pages_to_nodes(prey_ids, :prey, pages, nodes, ids_to_remove)
            pages_to_nodes(predator_ids, :predator, pages, nodes, ids_to_remove)
            pages_to_nodes(competitor_ids, :competitor, pages, nodes, ids_to_remove)

            nodes_to_keep = Set.new([page.id]) # always keep the source node

            links = links.select do |link|
              keep = !ids_to_remove.include?(link[:source]) && !ids_to_remove.include?(link[:target])
              if keep
                nodes_to_keep.add(link[:source])
                nodes_to_keep.add(link[:target])
              end
              keep
            end

            node_result = nodes.values.select do |node|
              nodes_to_keep.include? node[:id]
            end

            {
              nodes: node_result,
              links: links
            }
          end
        end)
      end
    end
  end

  private

  def set_default_params
    params[:batch] ||= false
    params[:images_per_page] ||= 0
    limit_param(:images_per_page)
    params[:images_page] ||= 1
    params[:videos_per_page] ||= 0
    limit_param(:videos_per_page)
    params[:videos_page] ||= 1
    params[:sounds_per_page] ||= 0
    limit_param(:sounds_per_page)
    params[:sounds_page] ||= 1
    params[:maps_per_page] ||= 0
    limit_param(:maps_per_page)
    params[:maps_page] ||= 1
    params[:texts_per_page] ||= 0
    limit_param(:texts_per_page)
    params[:texts_page] ||= 1
    params[:details] ||= false
    params[:common_names] ||= false
    params[:synonyms] ||= false
    params[:references] ||= false
    params[:taxonomy] ||= true
    params[:vetted] ||= 0
    params[:language] ||= 'en'
    params.dup.each do |name, value|
      params[name] = false if value == 'false'
    end
    # Valid Options: 'cc-by, cc-by-nc, cc-by-sa, cc-by-nc-sa, pd, na, all'
    @licenses =
      if params[:licenses] && params[:licenses] !~ /\ball\b/
        ids = []
        params[:licenses].split('|').each do |name|
          ids += get_license_ids(name)
        end
        ids.sort.uniq
      else
        nil
      end
  end

  def get_pages
    @pages = {}
    Page.where(id: params[:id].split(/\D+/)).
         includes(native_node: :scientific_names, scientific_names: [:resource, :taxonomic_status], nodes: {references: :referent}).
         find_each do |page|
           @pages[page.id] = build_page(page)
         end
    if @pages.size == 1 && !params[:batch]
      @pages = { taxonConcept: @pages.values.first }
    end
  end

  def get_license_ids(name)
    licenses = License.where('1=1')
    licenses =  if name.match(/^cc-/)
                  licenses = licenses.where('name LIKE "cc%" OR name LIKE "%creativecommons%"')
                  # NOTE: that funny looking pattern is the MySQL version of a word boundary, /\b/ to Rubyists.
                  licenses.where("name REGEXP '[[:<:]]#{name.sub(/^cc-/, '')}(-[[:digit:]]|[^-]|$)'")
                elsif name == 'pd'
                  licenses.where('name LIKE "%publicdomain%" OR name LIKE "%public domain%"')
                elsif name == 'na'
                  licenses.where('name LIKE "%no known%" OR name LIKE "%not applicable%"')
                else
                  nil
                end
    licenses ? licenses.pluck(:id) : []
  end

  def build_page(page)
    node = page.safe_native_node
    @return_hash = {
      identifier: page.id,
      scientificName: node.preferred_scientific_name.verbatim,
      richness_score: page.page_richness
    }
    if params[:synonyms]
      @return_hash["synonyms"] = page.scientific_names.includes(:resource).map do |name|
        relation = name&.taxonomic_status&.name || ''
        resource = name&.resource&.name || ''
        { synonym: name.verbatim, relationship: relation, resource: resource }
      end.sort {|a,b| a[:synonym] <=> b[:synonym] }.uniq
    end

    if params[:common_names]
      @return_hash[:vernacularNames] = []
      page.vernaculars.each do |name|
        @return_hash[:vernacularNames] << {
          vernacularName: name.string,
          language: name&.language&.group || 'en', # Yes, the API defaulted to EN.
          eol_preferred: name.is_preferred?
        }
      end
    end

    if params[:references]
      # Sorry, yes, this is black magic. :\ Fortunately, I don't think many people (if any) *use* this:
      @return_hash[:references] = page.nodes.map { |n| n.references.flat_map(&:referent).map(&:body) }.
        flatten.compact.uniq!
    end

    add_taxonomy_to_page(@return_hash, page) if params[:taxonomy]

    @return_hash[:dataObjects] = []
    add_text(page) if params[:texts_per_page].positive?
    @return_hash[:licenses] = License.where(id: @licenses).map { |l| "#{l.name} (#{l.id})" } if @licenses
    add_media(page.media.images, params[:images_page], params[:images_per_page]) if params[:images_per_page].positive?
    add_media(page.media.videos, params[:videos_page], params[:videos_per_page]) if params[:videos_per_page].positive?
    # Maps don't include the main GBIF Image, ATM. :\
    add_media(page.media.maps, params[:maps_page], params[:maps_per_page]) if params[:maps_per_page].positive?
    add_media(page.media.sounds, params[:sounds_page], params[:sounds_per_page]) if params[:sounds_per_page].positive?
    @return_hash.delete(:dataObjects) if @return_hash[:dataObjects].empty?
    @return_hash
  end

  def add_text(page)
    return nil if params[:vetted] == '3' || params[:vetted] == '4'
    offset = ((params[:texts_page].to_i || 1 ) - 1) * params[:texts_per_page]
    page.articles.limit(params[:texts_per_page]).offset(offset).each do |article|
       article_hash = {
        identifier: article.guid,
        dataObjectVersionID: article.id,
        dataType: 'http://purl.org/dc/dcmitype/Text',
        dataSubtype: '',
        vettedStatus: 'Trusted',
        dataRatings: [],
        dataRating: '2.5', # this is faked for now per Yan Wang's request.
        subject: article.sections&.map(&:name)
      }
      add_details_to_data_object(article_hash, article)
      @return_hash[:dataObjects] << article_hash
    end
  end

  def add_media(starting_filter, page, per_page)
    return nil if params[:vetted] == '3' || params[:vetted] == '4'
    images = starting_filter.includes(:image_info, :language, :license, :location, :resource, attributions: :role, references: :referent)
    images = images.where(license_id: @licenses) if @licenses
    offset = ((page.to_i || 1 ) - 1) * per_page
    images.limit(per_page).offset(offset).each do |image|
      type = if image.video?
        'http://purl.org/dc/dcmitype/MovingImage'
      elsif image.sound?
        'http://purl.org/dc/dcmitype/Sound'
      else
        'http://purl.org/dc/dcmitype/StillImage'
      end
      image_hash = {
        identifier: image.guid,
        dataObjectVersionID: image.id,
        dataType: type,
        dataSubtype: image.format,
        vettedStatus: 'Trusted',
        dataRatings: [],
        mediumType: image.subclass,
        dataRating: '2.5', # this is faked for now per Yan Wang's request.
        mimeType: 'image/jpeg'
      }
      if (info = image.image_info)
        (h, w) = info.original_size.split('x')
        image_hash[:height] = h if h
        image_hash[:width] = w if w
        image_hash[:crop_x] = info.crop_x * image_hash[:width] / 100.0 unless info.crop_x.blank? ||
          image_hash[:width].blank?
        image_hash[:crop_y] = info.crop_y * image_hash[:height] / 100.0  unless info.crop_y.blank? ||
          image_hash[:height].blank?
        # TODO:
        # image_hash[:crop_height] = info.crop_height * image_hash[:height] / 100.0  unless info.crop_height.blank? ||
        #   image_hash[:height].blank?
        image_hash[:crop_width] = info.crop_w * image_hash[:width] / 100.0  unless info.crop_w.blank? ||
          image_hash[:width].blank?
      end

      add_details_to_data_object(image_hash, image)

      @return_hash[:dataObjects] << image_hash
    end
  end

  def limit_param(name)
    params[name] = params[name].to_i
    params[name] = 100 if params[name] > 100
  end

  NODE_GROUP_PRIORITIES = {
    competitor: 1,
    prey: 2,
    predator: 3,
    source: 4
  }

  def pred_prey_node(page, group)
    if page.rank&.r_species? && page.icon
      {
        label: page.vernacular_or_sci_notags,
        labelWithItalics: page.name,
        id: page.id,
        group: group,
        icon: page.icon,
        x: 0, # for convenience of the visualization JS
        y: 0
      }
    else
      nil
    end
  end

  def pages_to_nodes(page_ids, group, pages, nodes, pages_wo_data)
    page_ids.each do |id|
      node = pred_prey_node(pages[id], group)
      if node
        already_added = nodes[id]

        if (
          (
           already_added &&
           NODE_GROUP_PRIORITIES[already_added[:group]] < NODE_GROUP_PRIORITIES[node[:group]]
          ) ||
          already_added.nil?
        )
          nodes[id] = node
        end
      else
        pages_wo_data.add(id)
      end
    end
  end
end