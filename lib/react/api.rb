require 'react/native_library'

module React
  # Provides the internal mechanisms to interface between reactrb and native components
  # the code will attempt to create a js component wrapper on any rb class that has a
  # render (or possibly _render_wrapper) method.  The mapping between rb and js components
  # is kept in the @@component_classes hash.

  # Also provides the mechanism to build react elements

  # TOOO - the code to deal with components should be moved to a module that will be included
  # in a class which will then create the JS component for that class.  That module will then
  # be included in React::Component, but can be used by any class wanting to become a react
  # component (but without other DSL characteristics.)
  class API
    @@component_classes = {}

    def self.import_native_component(opal_class, native_class)
      opal_class.instance_variable_set("@native_import", true)
      @@component_classes[opal_class] = native_class
    end

    def self.eval_native_react_component(name)
      component = `eval(name)`
      raise "#{name} is not defined" if `#{component} === undefined`
      is_component_class = `#{component}.prototype !== undefined` &&
                            (`!!#{component}.prototype.isReactComponent` ||
                             `!!#{component}.prototype.render`)
      is_functional_component = `typeof #{component} === "function"`
      is_not_using_react_v13 = `!window.React.version.match(/0\.13/)`
      unless is_component_class || (is_not_using_react_v13 && is_functional_component)
        raise 'does not appear to be a native react component'
      end
      component
    end

    def self.native_react_component?(name = nil)
      return false unless name
      eval_native_react_component(name)
    rescue
      nil
    end

    def self.create_native_react_class(type)
      raise "Provided class should define `render` method"  if !(type.method_defined? :render)
      render_fn = (type.method_defined? :_render_wrapper) ? :_render_wrapper : :render
      # this was hashing type.to_s, not sure why but .to_s does not work as it Foo::Bar::View.to_s just returns "View"
      @@component_classes[type] ||= %x{
        React.createClass({
          displayName: #{type.name},
          propTypes: #{type.respond_to?(:prop_types) ? type.prop_types.to_n : `{}`},
          getDefaultProps: function(){
            return #{type.respond_to?(:default_props) ? type.default_props.to_n : `{}`};
          },
          mixins: #{type.respond_to?(:native_mixins) ? type.native_mixins : `[]`},
          statics: #{type.respond_to?(:static_call_backs) ? type.static_call_backs.to_n : `{}`},
          componentWillMount: function() {
            var instance = this._getOpalInstance.apply(this);
            return #{`instance`.component_will_mount if type.method_defined? :component_will_mount};
          },
          componentDidMount: function() {
            var instance = this._getOpalInstance.apply(this);
            return #{`instance`.component_did_mount if type.method_defined? :component_did_mount};
          },
          componentWillReceiveProps: function(next_props) {
            var instance = this._getOpalInstance.apply(this);
            return #{`instance`.component_will_receive_props(Hash.new(`next_props`)) if type.method_defined? :component_will_receive_props};
          },
          shouldComponentUpdate: function(next_props, next_state) {
            var instance = this._getOpalInstance.apply(this);
            return #{`instance`.should_component_update?(Hash.new(`next_props`), Hash.new(`next_state`)) if type.method_defined? :should_component_update?};
          },
          componentWillUpdate: function(next_props, next_state) {
            var instance = this._getOpalInstance.apply(this);
            return #{`instance`.component_will_update(Hash.new(`next_props`), Hash.new(`next_state`)) if type.method_defined? :component_will_update};
          },
          componentDidUpdate: function(prev_props, prev_state) {
            var instance = this._getOpalInstance.apply(this);
            return #{`instance`.component_did_update(Hash.new(`prev_props`), Hash.new(`prev_state`)) if type.method_defined? :component_did_update};
          },
          componentWillUnmount: function() {
            var instance = this._getOpalInstance.apply(this);
            return #{`instance`.component_will_unmount if type.method_defined? :component_will_unmount};
          },
          _getOpalInstance: function() {
            if (this.__opalInstance == undefined) {
              var instance = #{type.new(`this`)};
            } else {
              var instance = this.__opalInstance;
            }
            this.__opalInstance = instance;
            return instance;
          },
          render: function() {
            var instance = this._getOpalInstance.apply(this);
            return #{`instance`.send(render_fn).to_n};
          }
        })
      }
    end

    def self.create_element(type, properties = {}, &block)
      params = []

      # Component Spec, Normal DOM, String or Native Component
      if @@component_classes[type]
        params << @@component_classes[type]
      elsif type.kind_of?(Class)
        params << create_native_react_class(type)
      elsif React::Component::Tags::HTML_TAGS.include?(type)
        params << type
      elsif type.is_a? String
        return React::Element.new(type)
      else
        raise "#{type} not implemented"
      end

      # Convert Passed in properties
      properties = convert_props(properties)
      params << properties.shallow_to_n

      # Children Nodes
      if block_given?
        [yield].flatten.each do |ele|
          params << ele.to_n
        end
      end
      React::Element.new(`React.createElement.apply(null, #{params})`, type, properties, block)
    end

    def self.clear_component_class_cache
      @@component_classes = {}
    end

    def self.convert_props(properties)
      raise "Component parameters must be a hash. Instead you sent #{properties}" unless properties.is_a? Hash
      props = {}
      properties.map do |key, value|
        if key == "class_name" && value.is_a?(Hash)
          props[lower_camelize(key)] = `React.addons.classSet(#{value.to_n})`
        elsif key == "class"
          props["className"] = value
        elsif ["style", "dangerously_set_inner_HTML"].include? key
          props[lower_camelize(key)] = value.to_n
        elsif React::HASH_ATTRIBUTES.include?(key) && value.is_a?(Hash)
          value.each { |k, v| props["#{key}-#{k.tr('_', '-')}"] = v.to_n }
        else
          props[React.html_attr?(lower_camelize(key)) ? lower_camelize(key) : key] = value
        end
      end
      props
    end

    private

    def self.lower_camelize(snake_cased_word)
      words = snake_cased_word.split('_')
      result = [words.first]
      result.concat(words[1..-1].map {|word| word[0].upcase + word[1..-1] })
      result.join('')
    end
  end
end
