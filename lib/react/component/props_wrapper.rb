module React
  module Component

    def deprecated_params_method(name, *args, &block)
      React::Component.deprecation_warning"Direct access to param `#{name}`.  Use `params.#{name}` instead."
      params.send(name, *args, &block)
    end

    class PropsWrapper
      attr_reader :component

      def self.define_param(name, param_type)
        if param_type == Observable
          define_method("#{name}") do
            value_for(name)
          end
          define_method("#{name}!") do |*args|
            current_value = value_for(name)
            if args.count > 0
              props[name].call args[0]
              current_value
            else
              # rescue in case we in middle of render... What happens during a
              # render that causes exception?
              # Where does `dont_update_state` come from?
              props[name].call current_value unless @dont_update_state rescue nil
              props[name]
            end
          end
        elsif param_type == Proc
          define_method("#{name}") do |*args, &block|
            props[name].call(*args, &block) if props[name]
          end
        else
          define_method("#{name}") do
            fetch_from_cache(name) do
              if param_type.respond_to? :_react_param_conversion
                param_type._react_param_conversion props[name], nil
              elsif param_type.is_a?(Array) &&
                param_type[0].respond_to?(:_react_param_conversion)
                props[name].collect do |param|
                  param_type[0]._react_param_conversion param, nil
                end
              else
                props[name]
              end
            end
          end
        end
      end

      def initialize(component)
        @component = component
      end

      def [](prop)
        props[prop]
      end

      private

      def fetch_from_cache(name)
        last, value = cache[name]
        return value if last.equal?(props[name])
        yield.tap do |value|
          cache[name] = [props[name], value]
        end
      end

      def cache
        @cache ||= Hash.new { |h, k| h[k] = [] }
      end

      def props
        component.props
      end

      def value_for(name)
        self[name].instance_variable_get("@value") if self[name]
      end
    end
  end
end
