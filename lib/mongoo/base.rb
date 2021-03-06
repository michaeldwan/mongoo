module Mongoo
  class UnknownAttributeError < Exception; end
  
  class Base
    
    include Mongoo::Changelog
    include Mongoo::Persistence
    include Mongoo::Modifiers
    
    include ActiveModel::Validations
    
    extend ActiveModel::Callbacks
    extend ActiveModel::Naming
    
    define_model_callbacks :insert, :update, :remove

    # Should we allow unknown attributes added to the document?
    #   Set this to false to skip verification and allow dynamic document attributes.
    class_attribute :verify_attributes
    self.verify_attributes = true
    
    def self.attribute(name, opts={})
      raise ArgumentError.new("missing :type") unless opts[:type]
      self.attributes[name.to_s] = opts
      define_attribute_methods
      true
    end
    
    def self.attributes
      Mongoo::ATTRIBUTE_META[self.to_s] ||= {}
    end
    
    def self.attributes_tree
      tree = {}
      self.attributes.each do |name, opts|
        parts = name.split(".")
        curr_branch = tree
        while part = parts.shift
          if !parts.empty?
            curr_branch[part.to_s] ||= {}
            curr_branch = curr_branch[part.to_s]
          else
            curr_branch[part.to_s] = opts[:type]
          end
        end
      end
      tree
    end
    
    def self.define_attribute_methods
      define_method("id") do
        get("_id")
      end
      define_method("id=") do |val|
        set("_id", val)
      end
      
      self.attributes_tree.each do |name, val|
        if val.is_a?(Hash)
          define_method(name) do
            AttributeProxy.new(val, [name], self)
          end
        else
          define_method(name) do
            get(name)
          end
          define_method("#{name}=") do |val|
            set(name, val)
          end
        end
      end
    end
    
    def self.known_attribute?(k)
      k == "_id" || self.attributes[k.to_s]
    end
    
    def initialize(hash={}, persisted=false)
      @persisted = persisted
      init_from_hash(hash)
      set_persisted_mongohash((persisted? ? mongohash.deep_clone : nil))
    end
    
    def ==(val)
      if val.class.to_s == self.class.to_s
        if val.persisted?
          val.id == self.id
        else
          self.mongohash.raw_hash == val.mongohash.raw_hash
        end
      end
    end
    
    def known_attribute?(k)
      self.class.known_attribute?(k)
    end
    
    def read_attribute_for_validation(key)
      get_attribute(key)
    end
    
    def get_attribute(k)
      unless known_attribute?(k)
        raise UnknownAttributeError, k
      end
      mongohash.dot_get(k.to_s)
    end
    alias :get :get_attribute
    alias :g   :get_attribute
    
    def set_attribute(k,v)
      unless known_attribute?(k)
        if self.respond_to?("#{k}=")
          return self.send("#{k}=", v)
        else
          raise UnknownAttributeError, k
        end
      end
      unless k.to_s == "_id" || v.nil?
        field_type = self.class.attributes[k.to_s][:type]
        v = Mongoo::AttributeSanitizer.sanitize(field_type, v)
      end
      mongohash.dot_set(k.to_s,v)
    end
    alias :set :set_attribute
    alias :s   :set_attribute
    
    def unset_attribute(k)
      mongohash.dot_delete(k); true
    end
    alias :unset :unset_attribute
    alias :u :unset_attribute
    
    def set_attributes(k_v_pairs)
      k_v_pairs.each do |k,v|
        set_attribute(k,v)
      end
    end
    alias :sets :set_attributes
    
    def get_attributes(keys)
      found = {}
      keys.each { |k| found[k.to_s] = get_attribute(k) }
      found
    end
    alias :gets :get_attributes
    
    def unset_attributes(keys)
      keys.each { |k| unset_attribute(k) }; true
    end
    alias :unsets :unset_attributes
    
    def attributes
      mongohash.to_key_value
    end
    
    def merge!(hash)
      if hash.is_a?(Mongoo::Mongohash)
        hash = hash.raw_hash
      end
      hash.deep_stringify_keys!
      hash = mongohash.raw_hash.deep_merge(hash)
      set_mongohash( Mongoo::Mongohash.new(hash) )
      mongohash
    end
        
    def init_from_hash(hash)
      unless hash.is_a?(Mongoo::Mongohash)
        hash = Mongoo::Mongohash.new(hash)
      end
      verify_attributes_in_mongohash(hash) if self.class.verify_attributes
      set_mongohash hash
    end
    protected :init_from_hash
    
    def set_mongohash(mongohash)
      @mongohash = mongohash
    end
    protected :set_mongohash
    
    def mongohash
      @mongohash
    end
    
    def set_persisted_mongohash(hash)
      @persisted_mongohash = hash
    end
    protected :set_persisted_mongohash
    
    def persisted_mongohash
      @persisted_mongohash
    end
    
    def verify_attributes_in_mongohash(hash)
      known_keys = self.class.attributes.keys
      known_keys << "_id"
      hash.dot_list.each do |k|
        unless known_keys.include?(k)
          k.split(".").each do |part|
            if opts = self.class.attributes[part]
              if opts[:type] == :hash
                known_keys << k
              end
            end
          end
          unless known_keys.include?(k)
            raise Mongoo::UnknownAttributeError, k.to_s
          end
        end
      end
    end # verify_attributes_in_mongohash
  end
end