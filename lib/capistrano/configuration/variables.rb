require 'thread'

module Capistrano
  class Configuration
    module Variables
      def self.included(base) #:nodoc:
        %w(initialize respond_to? method_missing).each do |m|
          base_name = m[/^\w+/]
          punct     = m[/\W+$/]
          base.send :alias_method, "#{base_name}_without_variables#{punct}", m
          base.send :alias_method, m, "#{base_name}_with_variables#{punct}"
        end
      end

      # The hash of variables that have been defined in this configuration
      # instance.
      attr_reader :variables

      def scope(scope_name, &block)
        old_scope = @scope
        @scope = scope_name
        result = yield
        @scope = old_scope
        result
      end

      # Set a variable to the given value.
      def set(variable, *args, &block)
        if variable.to_s !~ /^[_a-z]/
          raise ArgumentError, "invalid variable `#{variable}' (variables must begin with an underscore, or a lower-case letter)"
        end

        if !block_given? && args.empty? || block_given? && !args.empty?
          raise ArgumentError, "you must specify exactly one of either a value or a block"
        end

        if args.length > 1
          raise ArgumentError, "wrong number of arguments (#{args.length} for 1)"
        end

        value = args.empty? ? block : args.first
        sym = variable.to_sym
        protect(sym) {
          if @scope
            @variables[@scope] ||= {}
            @variables[@scope][sym] = value
          else
            @variables[sym] = value
          end
        }
      end

      alias :[]= :set

      # Removes any trace of the given variable.
      def unset(variable)
        sym = variable.to_sym
        protect(sym) do
          if @scope
            if @original_procs[@scope] && @original_procs[@scope][sym]
              @original_procs[@scope].delete(sym)
              @original_procs.delete(@scope) if @original_procs[@scope].empty?
            else
              @original_procs.delete(sym)
            end
            if @variables[@scope] && @variables[@scope][sym]
              @variables[@scope].delete(sym)
              @variables.delete(@scope) if @variables[@scope].empty?
            else
              @variables.delete(sym)
            end
          else
            @original_procs.delete(sym)
            @variables.delete(sym)
          end
        end
      end

      # Returns true if the variable has been defined, and false otherwise.
      def exists?(variable)
        (@scope && @variables[@scope] && @variables[@scope].key?(variable.to_sym)) || @variables.key?(variable.to_sym)
      end

      # If the variable was originally a proc value, it will be reset to it's
      # original proc value. Otherwise, this method does nothing. It returns
      # true if the variable was actually reset.
      def reset!(variable)
        sym = variable.to_sym
        protect(sym) do
          if @scope && @original_procs[@scope] && @original_procs[@scope].key?(sym)
            @variables[@scope] ||= {}
            @variables[@scope][sym] = @original_procs[@scope].delete(sym)
            true
          elsif @original_procs.key?(sym)
            @variables[sym] = @original_procs.delete(sym)
            true
          else
            false
          end
        end
      end

      # Access a named variable. If the value of the variable responds_to? :call,
      # #call will be invoked (without parameters) and the return value cached
      # and returned.
      def fetch(variable, *args)
        if !args.empty? && block_given?
          raise ArgumentError, "you must specify either a default value or a block, but not both"
        end

        sym = variable.to_sym
        protect(sym) do
          if @scope
            if !exists?(variable)
              return args.first unless args.empty?
              return yield(variable) if block_given?
              raise IndexError, "`#{variable}' not found"
            end

            if @variables[@scope] && @variables[@scope].respond_to?(:call)
              @original_procs[@scope] ||= {}
              @variables[@scope] ||= {}
              @original_procs[@scope][sym] = @variables[@scope][sym]
              @variables[@scope][sym] = @variables[@scope][sym].call
            elsif @variables[sym].respond_to?(:call)
              @original_procs[sym] = @variables[sym]
              @variables[sym] = @variables[sym].call
            end
          else
            if !@variables.key?(sym)
              return args.first unless args.empty?
              return yield(variable) if block_given?
              raise IndexError, "`#{variable}' not found"
            end

            if @variables[sym].respond_to?(:call)
              @original_procs[sym] = @variables[sym]
              @variables[sym] = @variables[sym].call
            end
          end
        end

        (@scope && @variables[@scope] && @variables[@scope][sym]) || @variables[sym]
      end

      def [](variable)
        fetch(variable, nil)
      end
      
      def variables_has_key?(key)
        (@scope && @variables[@scope] && @variables[@scope].has_key?(key)) || @variables.has_key?(key)
      end

      def initialize_with_variables(*args) #:nodoc:
        initialize_without_variables(*args)
        @scope = nil
        @variables = {}
        @original_procs = {}
        @scoped_variable_locks = {}
        @variable_locks = Hash.new { |h,k| h[k] = Mutex.new }

        set :ssh_options, {}
        set :logger, logger
      end
      private :initialize_with_variables

      def protect(variable)
        if @scope && @scoped_variable_locks[@scope] && @scoped_variable_locks[@scope][variable.to_sym]
          @scoped_variable_locks[@scope] ||= Hash.new { |h,k| h[k] = Mutex.new }
          @scoped_variable_locks[@scope][variable.to_sym].synchronize { yield }
        else
          @variable_locks[variable.to_sym].synchronize { yield }
        end
      end
      private :protect

      def respond_to_with_variables?(sym, include_priv=false) #:nodoc:
        variables_has_key?(sym) || respond_to_without_variables?(sym, include_priv)
      end

      def method_missing_with_variables(sym, *args, &block) #:nodoc:
        if args.length == 0 && block.nil? && variables_has_key?(sym)
          self[sym]
        else
          method_missing_without_variables(sym, *args, &block)
        end
      end
    end
  end
end