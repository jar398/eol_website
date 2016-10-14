class SearchController < ApplicationController
  # TODO: Mammoth method, break up.
  def search
    # TODO: we'll want some whitelist filtering here later:
    @q = params[:q]

    default = ! params.has_key?(:only)
    @types = {}
    [ :pages, :collections, :media, :users, :object_terms ].each do |sym|
      @types[sym] = default
    end

    if params.has_key?(:only)
      Array(params[:only]).each { |type| @types[type.to_sym] = true }
    elsif params.has_key?(:except)
      Array(params[:only]).each { |type| @types[type.to_sym] = false }
    end

    @pages = search_class(Page, include: [:page_contents, :native_node, vernaculars: :language ])
    @collections = search_class(Collection)
    @media = search_class(Medium)
    @users = search_class(User)

    # YOU WERE HERE - You just wrote this; not positive it will work. Need to
    # try it at a prompt. Assuming it does, you need to steal the view code from
    # the other trait views (should be mostly a partial) and add that to the
    # search results view.
    @object_terms = if @types[:object_terms]
      # TODO: relocate this. But, ATM, this only makes sense with suggestions:
      suggestions = SearchSuggestion.search { fulltext @q }.results
      suggestion = suggestions.find { |s| s.object_term? }
      traits = TraitBank.by_object_term_uri(suggestion.object_term)
      glossary = TraitBank.glossary(traits)
      TraitBank.sort(traits, @glossary)
    end

    # Doctoring for the view to find matches:
    @q.chop! if params[:q] =~ /\*$/
    @q = @q[1..-1] if params[:q] =~ /^\*/

    respond_to do |fmt|
      fmt.html do
        @empty = true
        [ @pages, @collections, @media, @users ].each do |set|
          @empty = false if set && ! set.results.empty?
        end
      end

      # TODO: JSON results for other types!
      fmt.json do
        render json: JSON.pretty_generate(@pages.results.as_json(
          except: :native_node_id,
          methods: :scientific_name,
          include: {
            preferred_vernaculars: { only: [:string],
              include: { language: { only: :code } } },
            # NOTE I'm excluding a lot more for search than you would want for
            # the basic page json:
            top_image: { only: [ :id, :guid, :owner, :name ],
              methods: [:small_icon_url, :medium_icon_url],
              include: { provider: { only: [:id, :name] },
                license: { only: [:id, :name, :icon_url] } } }
          }
        ))
      end
    end
  end

  private

  def search_class(klass, options = {})
    # NOTE: @q DOES NOT WORK in search blocks, and you can't call external
    # methods.
    if @types[klass.name.tableize.to_sym]
      klass.send(:search, options) do
        if params[:q] =~ /\*$/
          any do
            fulltext params[:q]
            fulltext params[:q].sub(/\*$/, "")
          end
        else
          fulltext params[:q]
        end
        paginate page: params[:page] || 1, per_page: params[:per_page] || 30
      end
    end
  end
end
