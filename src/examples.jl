using StructMethods

@structmethods mutable struct Dog
  name = "name"
  age = 0
  get_dog_years(self::Dog) = self.age * 7
end


function run_example()
  println("Run Example")
  d_default = Dog()
  show(d_default)
  fiddo = Dog(name="Fiddo", age=5)
  println()
  println("$(fiddo) Dog years: $(fiddo.get_dog_years())")
end

