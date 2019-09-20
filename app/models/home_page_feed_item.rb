class HomePageFeedItem < ActiveRecord::Base
  belongs_to :home_page_feed, :inverse_of => :items
  belongs_to :page
  validates_presence_of :home_page_feed

  def fields
    home_page_feed.fields
  end
end
