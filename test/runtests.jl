using Test
using ClassMethods

module VanillaExample

mutable struct MyClass
    value::Int
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

end # module VanillaExample

module MacroExample
using ClassMethods: @class

@class mutable struct MyClass
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

end # module MacroExample

@testset "ClassMethods @class macro" begin
    vanilla = VanillaExample.MyClass(10)
    macro_based = MacroExample.MyClass(10)

    @test vanilla.value == 10
    @test macro_based.value == 10

    @test vanilla.describe() == "MyClass(10)"
    @test macro_based.describe() == "MyClass(10)"

    @test VanillaExample.describe(vanilla) == "MyClass(10)"
    @test MacroExample.describe(macro_based) == "MyClass(10)"

    @test vanilla.set_value!(20) === vanilla
    @test macro_based.set_value!(20) === macro_based

    @test vanilla.value == 20
    @test macro_based.value == 20

    @test vanilla.adjust!(2; scale = 3) == 26
    @test macro_based.adjust!(2; scale = 3) == 26

    @test vanilla.value == 26
    @test macro_based.value == 26

    @test vanilla.adjust!(4) == 30
    @test macro_based.adjust!(4) == 30
end

