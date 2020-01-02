require "http"

class TermNames::WikidataAdapter
  include TermNames::ResponseCheck

  ID_CAPTURE_REGEX = /https?:\/\/www\.wikidata\.org\/wiki\/(?<id>Q\d+)/
  BASE_URL = "http://www.wikidata.org/wiki/Special:EntityData/"

  def self.name
    "wikidata"
  end

  def initialize
    @storage = TermNames::NameStorage.new
  end

  def uri_regexp
    "https?:\/\/www\.wikidata\.org\/.*"
  end

  def preload(uris, locales)
    uris.each do |uri|
      id = (matches = uri.match(ID_CAPTURE_REGEX)) ? matches[:id] : nil
      next if id.nil?

      response = HTTP.follow.get(BASE_URL + id + ".json")
      next if !check_response(response)
      labels_by_locale = response.parse.dig("entities", id, "labels")

      locales.each do |locale|
        value = labels_by_locale.dig(locale.to_s, "value")
        next if value.nil?
        @storage.set_value_for_locale(locale, uri, value) 
      end
    end

    sleep 1 # throttle api calls
  end

  def names_for_locale(locale)
    @storage.names_for_locale(locale)
  end
end
