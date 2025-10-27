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

module TypedDocMacroExample
using StructMethods: @structmethods

"""Cat struct doc.

$(Main.DSE.TYPEDFIELDS)
"""
@structmethods mutable struct Cat
  """Cat sound doc"""
  sound::String = "meow"

  """Docstring for speak::Function"""
  speak(self::Cat) = self.sound
end

end # module TypedDocMacroExample

module ClosureMacroExample
using StructMethods: @structmethods

@structmethods mutable struct Fox
  name::String

  """Return a howl string with an optional suffix."""
  howl = (self::Fox; suffix="!") -> self.name * suffix

  reset! = (self::Fox, value::String) -> begin
    self.name = value
    return self
  end
end

end # module ClosureMacroExample

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

  typed_meta = meta(TypedDocMacroExample)
  cat_binding = Binding(TypedDocMacroExample, :Cat)
  @test haskey(typed_meta, cat_binding)
  cat_doc = first(values(typed_meta[cat_binding].docs))
  cat_fields = cat_doc.data[:fields]
  @test cat_fields[:sound] == "Cat sound doc"
  @test cat_fields[:speak] == "Docstring for speak::Function"

  typed_buf = IOBuffer()
  DSE.format(DSE.TYPEDFIELDS, typed_buf, cat_doc)
  typed_output = String(take!(typed_buf))
  @test occursin("`sound::String`", typed_output)
  @test occursin("Cat sound doc", typed_output)
  @test occursin("`speak::Function`", typed_output)
  @test occursin("Docstring for speak::Function", typed_output)

  speak_binding = Binding(TypedDocMacroExample, :speak)
  @test haskey(typed_meta, speak_binding)
  speak_doc = first(values(typed_meta[speak_binding].docs))
  speak_text = join(String.(speak_doc.text))
  @test occursin("Docstring for speak::Function", speak_text)

  closure_obj = ClosureMacroExample.Fox("red")
  @test closure_obj.howl() == "red!"
  @test closure_obj.howl(; suffix="!!") == "red!!"
  @test closure_obj.reset!("scarlet") === closure_obj
  @test closure_obj.name == "scarlet"

  closure_meta = meta(ClosureMacroExample)
  howl_binding = Binding(ClosureMacroExample, :howl)
  @test haskey(closure_meta, howl_binding)
  howl_doc = first(values(closure_meta[howl_binding].docs))
  howl_text = join(String.(howl_doc.text))
  @test occursin("Return a howl string", howl_text)
end
