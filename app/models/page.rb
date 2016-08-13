class Page < ActiveRecord::Base
  belongs_to :native_node, class_name: "Node"
  belongs_to :moved_to_page, class_name: "Page"

  has_many :nodes, inverse_of: :page

  has_many :vernaculars, inverse_of: :page
  has_many :preferred_vernaculars, -> { where(is_preferred: true) },
    class_name: "Vernacular"
  has_many :scientific_names, inverse_of: :page
  has_one :scientific_name, -> { where(is_preferred: true) },
    class_name: "ScientificName"

  has_many :page_contents, -> { visible.not_untrusted }
  has_many :maps, through: :page_contents, source: :content, source_type: "Map"
  has_many :articles, through: :page_contents,
    source: :content, source_type: "Article"
  has_many :media, through: :page_contents,
    source: :content, source_type: "Medium"
  has_many :links, through: :page_contents,
    source: :content, source_type: "Link"
  has_many :images, -> { where(subclass: Medium.subclasses[:image]) },
    through: :page_contents, source: :content, source_type: "Medium"
  has_many :videos, -> { where(subclass: Medium.subclasses[:videos]) },
    through: :page_contents, source: :content, source_type: "Medium"
  has_many :sounds, -> { where(subclass: Medium.subclasses[:sounds]) },
    through: :page_contents, source: :content, source_type: "Medium"

  has_many :all_page_contents, -> { order(:position) }
  has_many :all_maps, through: :all_page_contents, source: :content, source_type: "Map"
  has_many :all_articles, through: :all_page_contents,
    source: :content, source_type: "Article"
  has_many :all_media, through: :all_page_contents,
    source: :content, source_type: "Medium"
  has_many :all_links, through: :all_page_contents,
    source: :content, source_type: "Link"
  has_many :all_images, -> { where(subclass: Medium.subclasses[:image]) },
    through: :all_page_contents, source: :content, source_type: "Medium"
  has_many :all_videos, -> { where(subclass: Medium.subclasses[:videos]) },
    through: :all_page_contents, source: :content, source_type: "Medium"
  has_many :all_sounds, -> { where(subclass: Medium.subclasses[:sounds]) },
    through: :all_page_contents, source: :content, source_type: "Medium"

  # Will return an array, even when there's only one, thus the plural names.
  has_many :top_maps, -> { limit(1) }, through: :page_contents, source: :content,
    source_type: "Map"
  has_many :top_articles, -> { limit(1) }, through: :page_contents,
    source: :content, source_type: "Article"
  has_many :top_links, -> { limit(6) }, through: :page_contents,
    source: :content, source_type: "Link"
  has_many :top_images,
    -> { where(subclass: Medium.subclasses[:image]).limit(6) },
    through: :page_contents, source: :content, source_type: "Medium"
  has_many :top_videos,
    -> { where(subclass: Medium.subclasses[:videos]).limit(1) },
    through: :page_contents, source: :content, source_type: "Medium"
  has_many :top_sounds,
    -> { where(subclass: Medium.subclasses[:sounds]).limit(1) },
    through: :page_contents, source: :content, source_type: "Medium"

  scope :preloaded, -> do
    includes(:scientific_name, :preferred_vernaculars, :page_contents)
  end

  scope :all_preloaded, -> do
    includes(:scientific_names, :vernaculars, :images,
      :videos, :sounds, :articles, :maps, :links)
  end

  # Can't (easily) use clever associations here because of language.
  def name(language = nil)
    language ||= Language.english
    preferred_vernaculars.find { |v| v.language_id == language.id }
  end

  # Without touching the DB:
  # NOTE: not used or spec'ed yet.
  def media_count
    page.page_contents.select { |pc| pc.content_type == "Medium" }.size
  end

  # TODO: we want to be able to order and limit these! :S
  # NOTE: not used or spec'ed yet.
  def traits
    TraitBank.page_traits(id)
  end
end
