class News < ActiveRecord::Base
  
  include ActionView::Helpers::DateHelper
  
  validates :title, length: {maximum: 128}
  validates :summary, length: {maximum: 256}
  has_many :media_objects

  belongs_to :user
  alias_attribute :owner, :user
  
  validates_presence_of :title
  
  def to_hash(recurse = false)
    h = {
      id: self.id,
      featuredMediaId: self.featured_media_id,
      name: self.title,
      url: UrlGenerator.new.news_url(self),
      path: UrlGenerator.new.news_path(self),
      hidden: self.hidden,
      timeAgoInWords: time_ago_in_words(self.created_at),
      createdAt: self.created_at.strftime("%B %d, %Y")
    }
    
    if recurse
      h.merge! ({
        content: self.content
      });
    end
    
    if self.featured_media_id != nil
      h.merge!({mediaSrc: self.media_objects.find(self.featured_media_id).tn_src})
    end
    
    h
  end
  
end
