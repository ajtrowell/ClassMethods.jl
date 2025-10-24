module MyModule
  using StructMethods: @structmethods

  @structmethods mutable struct MyClass
    value::Int

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

end
