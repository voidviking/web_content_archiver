# frozen_string_literal: true

class Resource < ApplicationRecord
  # Associations
  belongs_to :archive

  # Enums
  enum :resource_type, {
    stylesheet: 0,
    script: 1,
    image: 2,
    font: 3,
    other: 4
  }, prefix: true

  # Validations
  validates :original_url, presence: true
  validates :resource_type, presence: true
end
