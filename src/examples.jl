using StructMethods
using DocStringExtensions

export Dog, Cat, run_example

"Doc Added to Dog"
@structmethods mutable struct Dog
  name = "name"
  age = 0
  get_dog_years(self::Dog) = self.age * 7
end


"Cat docs"
@kwdef mutable struct Cat
  "name doc"
  name = "name"
  age = 0
  lives = 9
  remove_life(self::Cat) = self-=1
end


function run_example()
  println("Run Example")
  d_default = Dog()
  show(d_default)
  fiddo = Dog(name="Fiddo", age=5)
  println()
  println("$(fiddo) Dog years: $(fiddo.get_dog_years())")
end

