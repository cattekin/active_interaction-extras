module ActiveInteraction::Extras::ModelFields
  extend ActiveSupport::Concern

  # returns hash of all model fields and their values
  def model_fields(model_name)
    fields = self.class.model_field_cache[model_name]
    inputs.slice(*fields)
  end

  # returns hash of only changed model fields and their values
  def changed_model_fields(model_name)
    model_fields(model_name).select do |field, _value|
      any_changed?(field)
    end
  end

  # returns hash of only given model fields and their values
  def given_model_fields(model_name)
    model_fields(model_name).select do |field, _value|
      given?(field)
    end
  end

  class Context < SimpleDelegator
    attr_accessor :from_model_name
    attr_accessor :model_field_cache
    attr_accessor :prefix

    def custom_filter_attribute(name, opts = {})
      from_model_name = self.from_model_name

      if prefix
        name = "#{from_model_name}_#{name}".to_sym
        model_field_cache[from_model_name] = model_field_cache[from_model_name] << :prefix
      end

      model_field_cache[from_model_name] = model_field_cache[from_model_name] << name

      __getobj__.send __callee__, name, opts
    end

    alias interface custom_filter_attribute
    alias date custom_filter_attribute
    alias time custom_filter_attribute
    alias date_time custom_filter_attribute
    alias integer custom_filter_attribute
    alias decimal custom_filter_attribute
    alias float custom_filter_attribute
    alias string custom_filter_attribute
    alias symbol custom_filter_attribute
    alias object custom_filter_attribute
    alias hash custom_filter_attribute
    alias file custom_filter_attribute
    alias boolean custom_filter_attribute
    alias array custom_filter_attribute
  end

  # checks if value was given to the service and the value is different from
  # the one on the model
  def any_changed?(*fields)
    fields.any? do |field|
      model_field = self.class.model_field_cache_inverse[field]
      value_changed = true

      if model_field
        name_on_model = name_on_model(model_field, field)
        value_changed = send(model_field).send(name_on_model) != send(field)
      end

      given?(field) && value_changed
    end
  end

  # overwritten to pre-populate model fields
  def populate_filters(_inputs)
    super.tap do
      self.class.filters.each do |name, filter|
        next if given?(name)

        model_field = self.class.model_field_cache_inverse[name]
        next if model_field.nil?

        name_on_model = name_on_model(model_field, name)

        value = public_send(model_field)&.public_send(name_on_model)
        public_send("#{name}=", filter.clean(value, self))
      end
    end
  end

  def name_on_model(model_name, input)
    if self.class.model_field_cache[model_name].include? :prefix
      input.to_s.gsub("#{model_name}_", '').to_sym
    else
      input
    end
  end

  class_methods do
    def model_field_cache
      @model_field_cache ||= Hash.new { [] }
    end

    def model_field_cache_inverse
      @model_field_cache_inverse ||= model_field_cache.each_with_object({}) do |(model, fields), result|
        fields.each do |field|
          result[field] = model
        end
      end
    end

    # Default values from the model in the other field
    #
    #  object :user
    #  model_fields(:user) do
    #    string :first_name
    #    string :last_name
    #  end
    #
    # >> interaction.new(user: User.new(first_name: 'John')).first_name
    # => 'John'
    #
    def model_fields(model_name, opts = {}, &block)
      if block
        ref_model_field_cache = model_field_cache
        opts.reverse_merge!(default: nil, permit: true, prefix: nil)

        with_options opts do
          context = Context.new(self)
          context.prefix = opts[:prefix]
          context.from_model_name = model_name
          context.model_field_cache = ref_model_field_cache

          context.instance_exec(&block)
        end
      end

      model_field_cache[model_name]
    end
  end
end
