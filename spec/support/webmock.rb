# frozen_string_literal: true

require "webmock/rspec"

# Disable all real HTTP connections in tests.
# Use stub_request(...) in specs that need HTTP.
WebMock.disable_net_connect!(allow_localhost: true)
