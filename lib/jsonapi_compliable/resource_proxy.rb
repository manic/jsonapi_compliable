module JsonapiCompliable
  class ResourceProxy
    include Enumerable

    attr_reader :resource, :query, :scope

    def initialize(resource, scope, query, payload: nil, single: false, raise_on_missing: false)
      @resource = resource
      @scope = scope
      @query = query
      @payload = payload
      @single = single
      @raise_on_missing = raise_on_missing
    end

    def single?
      !!@single
    end

    def raise_on_missing?
      !!@raise_on_missing
    end

    def errors
      data.errors
    end

    def [](val)
      data[val]
    end

    def jsonapi_render_options(opts = {})
      opts[:meta]   ||= {}
      opts[:expose] ||= {}
      opts[:expose][:context] = JsonapiCompliable.context[:object]
      opts
    end

    def to_jsonapi(options = {})
      options = jsonapi_render_options(options)
      Renderer.new(self, options).to_jsonapi
    end

    def to_json(options = {})
      Renderer.new(self, options).to_json
    end

    def to_xml(options = {})
      Renderer.new(self, options).to_xml
    end

    def data
      @data ||= begin
        records = @scope.resolve
        if records.empty? && raise_on_missing?
          raise JsonapiCompliable::Errors::RecordNotFound
        end
        records = records[0] if single?
        records
      end
    end
    alias :to_a :data

    def each(&blk)
      to_a.each(&blk)
    end

    def stats
      @stats ||= @scope.resolve_stats
    end

    def save(action: :create)
      validator = persist do
        @resource.persist_with_relationships \
          @payload.meta(action: action),
          @payload.attributes,
          @payload.relationships
      end
      @data, success = validator.to_a
      success
    end

    def destroy
      validator = @resource.transaction do
        model = @resource.destroy(@query.filters[:id])
        model.instance_variable_set(:@__serializer_klass, @resource.serializer)
        validator = ::JsonapiCompliable::Util::ValidationResponse.new \
          model, @payload
        validator.validate!
        @resource.before_commit(model, :destroy)
        validator
      end
      @data, success = validator.to_a
      success
    end

    def update_attributes
      save(action: :update)
    end

    def include_hash
      @payload ? @payload.include_hash : @query.include_hash
    end

    def fields
      query.fields
    end

    def extra_fields
      query.extra_fields
    end

    private

    def persist
      @resource.transaction do
        ::JsonapiCompliable::Util::Hooks.record do
          model = yield
          validator = ::JsonapiCompliable::Util::ValidationResponse.new \
            model, @payload
          validator.validate!
          validator
        end
      end
    end
  end
end