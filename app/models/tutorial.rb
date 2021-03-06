require 'nokogiri'

class Tutorial < ActiveRecord::Base
  
  include ActionView::Helpers::DateHelper
  include ActionView::Helpers::SanitizeHelper

  has_many :media_objects
  
  validates_presence_of :title
  validates_presence_of :user_id
  
  validates :title, length: {maximum: 128}
  
  has_many :media_objects
  belongs_to :user
  
  alias_attribute :name, :title
 
  alias_attribute :owner, :user
  
  def self.search(search, include_hidden = false)
    res = if search
        where('lower(title) LIKE lower(?)', "%#{search}%")
    else
        all
    end
    
    if include_hidden
      res
    else
      res.where({hidden: false})
    end
  end
  
  def to_hash(recurse = true)
    h = {
      id: self.id,
      name: self.name,
      featured: self.featured,
      path: UrlGenerator.new.tutorial_path(self),
      url: UrlGenerator.new.tutorial_url(self),
      hidden: self.hidden,
      timeAgoInWords: time_ago_in_words(self.created_at),
      createdAt: self.created_at.strftime("%B %d, %Y"),
      ownerName: self.owner.name,
      ownerUrl: UrlGenerator.new.user_url(self.owner)
    }
    
    if self.featured_media_id != nil
      h.merge!({mediaSrc: self.media_objects.find(self.featured_media_id).tn_src})
    end
    
    if recurse
      h.merge! ({
        mediaObjects: self.media_objects.map {|o| o.to_hash false},
        owner:        self.owner.to_hash(false)
      })
    end
    h
  end
end
