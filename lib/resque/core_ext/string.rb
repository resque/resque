class String
  # Tries to find a constant with the name specified in the argument string.
  #
  #   'Module'.constantize     # => Module
  #   'Test::Unit'.constantize # => Test::Unit
  #
  # The name is assumed to be the one of a top-level constant, no matter
  # whether it starts with "::" or not. No lexical context is taken into
  # account:
  #
  #   C = 'outside'
  #   module M
  #     C = 'inside'
  #     C               # => 'inside'
  #     'C'.constantize # => 'outside', same as ::C
  #   end
  #
  # NameError is raised when the name is not in CamelCase or the constant is
  # unknown.
  def constantize
    names = self.split('::')
    names.shift if names.empty? || names.first.empty?

    names.inject(Object) do |constant, name|
      if constant == Object
        constant.const_get(name)
      else
        candidate = constant.const_get(name)
        args = Module.method(:const_defined?).arity != 1 ? [false] : []
        next candidate if constant.const_defined?(name, *args)
        next candidate unless Object.const_defined?(name)

        # Go down the ancestors to check it it's owned
        # directly before we reach Object or the end of ancestors.
        constant = constant.ancestors.inject do |const, ancestor|
          break const    if ancestor == Object
          break ancestor if ancestor.const_defined?(name, *args)
          const
        end

        # owner is in Object, so raise
        constant.const_get(name, false)
      end
    end
  end unless String.respond_to?(:constantize)
end