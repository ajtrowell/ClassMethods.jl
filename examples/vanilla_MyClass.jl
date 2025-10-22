module MyModule
  mutable struct MyClass
    myInt::Int

    # we have these `const` fields since Julia 1.8
    const print_int::Function
    const set_int!::Function

    function print_int(self::MyClass)
      println("hello, I have myInt: $(self.myInt)")
    end

    function set_int!(self::MyClass, new_int::Int)
      self.myInt = new_int
      return self
    end

    function MyClass(int::Int)
      obj = new(
        int,
        ()->print_int(obj),
        (new_int,)->set_int!(obj, new_int),
      )
      return obj
    end
  end
end
