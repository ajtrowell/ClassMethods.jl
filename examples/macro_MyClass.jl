module MyModule
  @class mutable struct MyClass
    myInt::Int

    function print_int(self::MyClass)
      println("hello, I have myInt: $(self.myInt)")
    end

    function set_int!(self::MyClass, new_int::Int)
      self.myInt = new_int
    end
  end
end
