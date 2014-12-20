module Ezid
  #
  # Represents an EZID identifier as a resource.
  #
  # Ezid::Identifier delegates access to registered metadata elements through #method_missing.
  #
  # @api public
  #
  class Identifier

    attr_reader :id, :client
    attr_accessor :shoulder, :metadata

    # Attributes to display on inspect
    INSPECT_ATTRS = %w( id status target created )

    # EZID status terms
    PUBLIC = "public"
    RESERVED = "reserved"
    UNAVAILABLE = "unavailable"

    class << self
      attr_accessor :defaults

      # Creates or mints an identifier (depending on arguments)
      # @see #save
      # @return [Ezid::Identifier] the new identifier
      # @raise [Ezid::Error]
      def create(attrs = {})
        identifier = new(attrs)
        identifier.save
      end

      # Retrieves an identifier
      # @return [Ezid::Identifier] the identifier
      # @raise [Ezid::Error] if the identifier does not exist in EZID
      def find(id)
        identifier = new(id: id)
        identifier.reload
      end
    end

    self.defaults = {}

    def initialize(args={})
      @client = args.delete(:client) || Client.new
      @id = args.delete(:id)
      @shoulder = args.delete(:shoulder)
      @deleted = false
      init_metadata(args)
    end

    def inspect
      attrs = if deleted?
                "id=\"#{id}\" DELETED"
              else
                INSPECT_ATTRS.map { |attr| "#{attr}=\"#{send(attr)}\"" }.join(" ")
              end
      "#<#{self.class.name} #{attrs}>"
    end

    def to_s
      id
    end

    # Persist the identifer and/or metadata to EZID.
    #   If the identifier is already persisted, this is an update operation;
    #   Otherwise, create (if it has an id) or mint (if it has a shoulder)
    #   the identifier.
    # @return [Ezid::Identifier] the identifier
    # @raise [Ezid::Error] if the identifier is deleted, or the host responds
    #   with an error status.
    def save
      raise Error, "Cannot save a deleted identifier." if deleted?
      persisted? ? modify : create_or_mint
      reload
    end

    # Updates the metadata
    # @param attrs [Hash] the metadata
    # @return [Ezid::Identifier] the identifier
    def update_metadata(attrs={})
      attrs.each { |k, v| send("#{k}=", v) }
      self
    end

    # Is the identifier persisted?
    # @return [Boolean]
    def persisted?
      return false if deleted?
      !!(id && created)
    end

    # Has the identifier been deleted?
    # @return [Boolean]
    def deleted?
      @deleted
    end

    # Updates the metadata and saves the identifier
    # @param data [Hash] a hash of metadata
    # @return [Ezid::Identifier] the identifier
    # @raise [Ezid::Error]
    def update(data={})
      update_metadata(data)
      save
    end

    # Reloads the metadata from EZID (local changes will be lost!)
    # @return [Ezid::Identifier] the identifier
    # @raise [Ezid::Error]
    def reload
      refresh_metadata
      self
    end

    # Empties the (local) metadata (changes will be lost!)
    # @return [Ezid::Identifier] the identifier
    def reset
      clear_metadata
      self
    end

    # Deletes the identifier from EZID
    # @see http://ezid.cdlib.org/doc/apidoc.html#operation-delete-identifier
    # @return [Ezid::Identifier] the identifier
    # @raise [Ezid::Error]
    def delete
      raise Error, "Only persisted, reserved identifiers may be deleted: #{inspect}." unless deletable?
      client.delete_identifier(id)
      @deleted = true
      reset
    end

    # Is the identifier reserved?
    # @return [Boolean]
    def reserved?
      status == RESERVED
    end

    # Is the identifier public?
    # @return [Boolean]
    def public?
      status == PUBLIC
    end

    # Is the identifier unavailable?
    # @return [Boolean]
    def unavailable?
      status =~ /^#{UNAVAILABLE}/
    end

    # Is the identifier deletable?
    # @return [Boolean]
    def deletable?
      persisted? && reserved?
    end

    # Mark the identifier as unavailable
    # @param reason [String] an optional reason 
    # @return [String] the new status
    def unavailable!(reason = nil)
      raise Error, "Cannot make a reserved identifier unavailable." if persisted? && reserved?
      value = UNAVAILABLE
      value << " | #{reason}" if reason
      self.status = value
    end

    # Mark the identifier as public
    # @return [String] the new status
    def public!
      self.status = PUBLIC
    end

    protected

      def method_missing(method, *args)
        metadata.send(method, *args)
      rescue NoMethodError
        super
      end

    private

      def refresh_metadata
        response = client.get_identifier_metadata(id)
        @metadata = Metadata.new(response.metadata)
      end

      def clear_metadata
        @metadata.clear
      end

      def modify
        client.modify_identifier(id, metadata)
      end

      def create_or_mint
        id ? create : mint
      end

      def mint
        response = client.mint_identifier(shoulder, metadata)
        @id = response.id
      end

      def create
        client.create_identifier(id, metadata)
      end

      def init_metadata(args)
        @metadata = Metadata.new(args.delete(:metadata))
        update_metadata(self.class.defaults.merge(args))
      end

  end
end
