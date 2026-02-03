# frozen_string_literal: true

FactoryBot.define do
  factory :resource do
    archive
    sequence(:original_url) { |n| "https://example.com/assets/resource-#{n}.css" }
    sequence(:storage_key) { |n| "assets/#{SecureRandom.hex(8)}/resource-#{n}.css" }
    sequence(:storage_url) { |n| "/archived_assets/#{n}.css" }
    resource_type { :stylesheet }
    content_type { "text/css" }
    file_size { 1024 }

    trait :stylesheet do
      resource_type { :stylesheet }
      content_type { "text/css" }
      sequence(:original_url) { |n| "https://example.com/styles/style-#{n}.css" }
    end

    trait :script do
      resource_type { :script }
      content_type { "application/javascript" }
      sequence(:original_url) { |n| "https://example.com/scripts/script-#{n}.js" }
    end

    trait :image do
      resource_type { :image }
      content_type { "image/png" }
      sequence(:original_url) { |n| "https://example.com/images/image-#{n}.png" }
      file_size { 5120 }
    end

    trait :font do
      resource_type { :font }
      content_type { "font/woff2" }
      sequence(:original_url) { |n| "https://example.com/fonts/font-#{n}.woff2" }
      file_size { 2048 }
    end

    trait :other do
      resource_type { :other }
      content_type { "application/octet-stream" }
      sequence(:original_url) { |n| "https://example.com/assets/file-#{n}.dat" }
    end
  end
end
