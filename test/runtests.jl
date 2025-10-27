using Test
using DocStringExtensions
#include(joinpath(@__DIR__, "..", "docstringextensions_mount", "src", "DocStringExtensions.jl"))
const DSE = DocStringExtensions

using StructMethods
using Base.Docs: Binding, meta

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

  function adjust!(self::MyClass, delta::Int; scale::Int=1)
    self.value += delta * scale
    return self.value
  end

  function MyClass(value::Int)
    obj = new(
      value,
      () -> describe(obj),
      new_value -> set_value!(obj, new_value),
      (delta; scale = 1) -> adjust!(obj, delta; scale=scale),
    )
    return obj
  end
end

end # module VanillaExample

module MacroExample
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

  function adjust!(self::MyClass, delta::Int; scale::Int=1)
    self.value += delta * scale
    return self.value
  end
end

end # module MacroExample

module DefaultMacroExample
using StructMethods: @structmethods

@structmethods struct DefaultClass
  x::Int = 41
  y::String = "hello"
end

end # module DefaultMacroExample

module DocMacroExample
using StructMethods: @structmethods

"""Dog struct doc.

$(Main.DSE.FIELDS)
"""
@structmethods mutable struct Dog
  """Dog name doc"""
  name::String = "Fido"

  """Dog age doc"""
  age::Int = 0

  """Return the age in dog years."""
  function dog_years(self::Dog)
    self.age * 7
  end
end

end # module DocMacroExample

function Base.show(io::IO, obj::VanillaExample.MyClass)
  print(io, "$(typeof(obj))(")
  print(io, obj.value)
  print(io, ")")
end

@testset "StructMethods @structmethods macro" begin
  vanilla = VanillaExample.MyClass(10)
  macro_based = MacroExample.MyClass(10)

  @test vanilla.value == 10
  @test macro_based.value == 10

  @test vanilla.describe() == "MyClass(10)"
  @test macro_based.describe() == "MyClass(10)"

  @test fieldnames(VanillaExample.MyClass) == fieldnames(MacroExample.MyClass)
  @test repr(vanilla) == "Main.VanillaExample.MyClass(10)"
  @test repr(macro_based) == "Main.MacroExample.MyClass(10)"

  @test vanilla.set_value!(20) === vanilla
  @test macro_based.set_value!(20) === macro_based

  @test vanilla.value == 20
  @test macro_based.value == 20

  @test vanilla.adjust!(2; scale=3) == 26
  @test macro_based.adjust!(2; scale=3) == 26

  @test vanilla.value == 26
  @test macro_based.value == 26

  @test vanilla.adjust!(4) == 30
  @test macro_based.adjust!(4) == 30

  macro_keyword = MacroExample.MyClass(value=99)
  @test macro_keyword.value == 99

  defaulted = DefaultMacroExample.DefaultClass()
  @test defaulted.x == 41
  @test defaulted.y == "hello"

  partial_override = DefaultMacroExample.DefaultClass(x=10)
  @test partial_override.x == 10
  @test partial_override.y == "hello"

  @test DefaultMacroExample.DefaultClass(5, "world").x == 5

  doc_meta = meta(DocMacroExample)
  dog_binding = Binding(DocMacroExample, :Dog)
  @test haskey(doc_meta, dog_binding)
  dog_doc = first(values(doc_meta[dog_binding].docs))
  buf = IOBuffer()
  DSE.format(DSE.FIELDS, buf, dog_doc)
  fields_output = String(take!(buf))
  @test occursin("`name`", fields_output)
  @test occursin("Dog name doc", fields_output)
  @test occursin("`age`", fields_output)
  @test occursin("Dog age doc", fields_output)

  dog_years_binding = Binding(DocMacroExample, :dog_years)
  @test haskey(doc_meta, dog_years_binding)
  dog_years_doc = first(values(doc_meta[dog_years_binding].docs))
  method_text = join(String.(dog_years_doc.text))
  @test occursin("Return the age in dog years", method_text)
end
