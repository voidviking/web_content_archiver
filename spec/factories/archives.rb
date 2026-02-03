# frozen_string_literal: true

FactoryBot.define do
  factory :archive do
    sequence(:url) { |n| "https://example.com/page-#{n}" }
    status { :pending }

    trait :pending do
      status { :pending }
    end

    trait :processing do
      status { :processing }
    end

    trait :completed do
      status { :completed }
      content { "<html><body>Archived content</body></html>" }
    end

    trait :failed do
      status { :failed }
      error_message { "Failed to fetch the page" }
    end
  end
end
