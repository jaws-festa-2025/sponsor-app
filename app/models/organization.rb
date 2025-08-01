class Organization < ApplicationRecord
  has_many :sponsorships, dependent: :destroy
  validates :name, presence: true
  validates :domain, presence: true

  def slug
    domain
  end
end
