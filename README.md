# funlib
A collection of functional-programming style functions that can be chained

Below is an example (with some simple test data) that shows how the funlib can be used. Do note that the funlib uses deferred execution meaning that the evaluation of an expression is delayed until its realized value is actually required.
```lua
local funlib = require('funlib')

local dataset = {
    { name = "John", age = 42, city = "New York" },
    { name = "Sophie", age = 19, city = "San Francisco" },
    { name = "Lucas", age = 27, city = "Miami" },
    { name = "Emily", age = 33, city = "New York" },
    { name = "Michael", age = 38, city = "Dallas" },
    { name = "Isabella", age = 23, city = "Denver" },
    { name = "Henry", age = 29, city = "Boston" },
    { name = "Olivia", age = 45, city = "New York" },
    { name = "Jack", age = 26, city = "Phoenix" },
    { name = "Emma", age = 31, city = "New York" },
    { name = "Noah", age = 35, city = "Los Angeles" },
    { name = "Mia", age = 40, city = "Houston" },
    { name = "Liam", age = 22, city = "Philadelphia" },
    { name = "Grace", age = 36, city = "Las Vegas" },
    { name = "Aiden", age = 24, city = "Orlando" },
    { name = "Ava", age = 37, city = "San Diego" },
    { name = "James", age = 28, city = "Seattle" },
    { name = "Ella", age = 25, city = "Miami" },
    { name = "Ethan", age = 32, city = "Boston" },
    { name = "Chloe", age = 21, city = "New York" }
}

local func = funlib.create(dataset)
    :where(function(x) return x.age > 25 and x.city == "New York" end)
    :select(function(x) return { name = x.name, age = x.age } end)
    :sortByDescending(function(x) return x.age end)
```

The above will store a chain of functions that finds every person over the age of 40, living in New York, sorted by age descending. To actually get a result from this function chain, the function chain must be used in some way. For instance, turning it into a table using the toTable function. Or otherwise, iterating over the chain using funlib.pairs

```lua
for _, person in funlib.pairs(func) do
    print("Name: " .. person.name .. ", Age: " .. person.age)
end
```

This will output the following:
```
Name: Olivia, Age: 45
Name: John, Age: 42
Name: Emily, Age: 33
Name: Emma, Age: 31
```
