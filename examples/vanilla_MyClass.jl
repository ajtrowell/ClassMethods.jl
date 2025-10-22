module MyModule
  mutable struct MyClass
    value::Int

    # method fields stored directly on the struct
    const describe::Function
    const set_value!::Function
    const adjust!::Function

    function describe(self::MyClass)
      return "MyClass($(self.value))"
    end

    function set_value!(self::MyClass, new_value::Int)
      self.value = new_value
      return self
    end

    function adjust!(self::MyClass, delta::Int; scale::Int = 1)
      self.value += delta * scale
      return self.value
    end

    function MyClass(value::Int)
      obj = new(
        value,
        () -> describe(obj),
        new_value -> set_value!(obj, new_value),
        (delta; scale = 1) -> adjust!(obj, delta; scale = scale),
      )
      return obj
    end
  end

  function demo()
    obj = MyClass(10)
    println(obj.describe())
    obj.set_value!(20)
    println("After set_value!: $(obj.value)")
    println("Adjustment result: $(obj.adjust!(2; scale = 3))")
    println("Final value: $(obj.value)")
    return obj
  end

  function Base.show(io::IO, obj::MyModule.MyClass)
    print(io, "$(typeof(obj))($(obj.value))")
  end

end
