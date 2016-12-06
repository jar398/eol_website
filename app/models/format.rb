class Format < ActiveRecord::Base
  has_many :fields, -> { order(position: :asc) }, inverse_of: :format

  belongs_to :harvest, inverse_of: :formats
  belongs_to :resource, inverse_of: :formats

  enum file_type: [ :csv, :excel, :dwca ]
  enum represents: [ :articles, :attributions, :images, :js_maps, :links,
    :media, :maps, :refs, :sounds, :videos ]

  def copy_to_harvest(new_harvest)
    new_harvest.formats << self.clone
  end
end
