module ApplicationHelper
  def prep_for_api(query)
    query = query.where(["created_at > ?", Time.at(params[:since].to_i)]) if params[:since]
    query = query.page(params[:page] || 1).per(params[:per] || 1000)
  end

  def meta_data_to_json(json, meta)
    json.eol_pk "#{meta.class.name}-#{meta.id}"
    if meta.is_a?(Reference)
      # TODO: we should probably make this URI configurable:
      json.predicate 'http://eol.org/schema/reference/referenceID'
      body = meta.body || ''
      body += " <a href='#{meta.url}'>link</a>" unless meta.url.blank?
      body += " #{meta.doi}" unless meta.doi.blank?
      json.literal body
    else
      json.predicate meta.predicate_term.try(:uri)
      json.units meta.units_term.try(:uri) if meta.respond_to?(:units_term)
      json.statistical_method meta.statistical_method_term.try(:uri) if meta.respond_to?(:statistical_method_term)
      json.value_uri meta.object_term.try(:uri)
      json.measurement meta.measurement if meta.respond_to?(:measurement)
      json.literal meta.literal
      json.sex meta.sex_term.uri if meta.respond_to?(:sex_term) && meta.sex_term
      json.lifestage meta.lifestage_term.uri if meta.respond_to?(:lifestage_term) && meta.lifestage_term
      json.source meta.source if meta.respond_to?(:source)
    end
  end
end
