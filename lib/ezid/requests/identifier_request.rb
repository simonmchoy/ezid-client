require_relative "request"

module Ezid
  # @abstract
  # @api private
  class IdentifierRequest < Request
    attr_reader :identifier

    def path
      "/id/#{identifier}"
    end

    def handle_args(*args)
      @identifier = args.first
    end
  end
end
