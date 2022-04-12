---
layout: post
title: "alias_method for the Crystal Language"
date: 2021-10-08 08:00:00 -0700
tags: crystal
categories: crystal
---
# alias_method for the Crystal Language

Crystal, as a matter of language design, [discourages method aliases](https://github.com/crystal-lang/crystal/wiki/FAQ#why-are-aliases-discouraged). The tl;dr from that link is that it is a bad idea because:

* multiple names for the same method implies having more to learn to understand arbitrary code.
* creating classes which implement an interface that has aliases requires that one also implement all of those aliases.
* unnecessary aliases slow down compilation speed and increase executable size.
* where aliases exist, people waste time on trivialities like `collect` or `map`?

However, there are sometimes occasions when being able to trivially make method aliases is undeniably useful. The use cases are varied, but it could be as simple as wanting to map two different, but common ways to refer to a method to the same code, or as trivial as wanting to have a short name for a method that is normally referenced by a longer name, or maybe one wants to write a DSL that has native-language-appropriate method names, or one wants to intercept a method call or form a method-call-chain without using `previous_def`, or a myriad of other reasons that may not immediately be obvious.

It's arguable that any of these use cases have reasons why one might not want to do them, but, if one is sitting there thinking, "Yeah, but I just really wish that I could alias methods in Crystal!", read on to learn about doing exactly that.

## The Easiest Thing

By far the easiest approach is to just manually create a new method that calls the old method. Crystal's classes can be reopened, so one can add one's own code to them. Consider this simple class:

{% highlight crystal %}
class MyThing
  def original_method
    # Important Stuff Here
  end
end
{% endhighlight %}

It's a trivial thing to write a new method that calls the old one:

{% highlight crystal %}
class MyThing
  def om
    original_method
  end
end
{% endhighlight %}

If there are many methods to be aliased, and some take arguments, or blocks, or have specific type definitions, this might result in a lot of typing, but this approach is absolutely the most direct approach for creating method aliases.

A Crystal macro can be written which will make all of this a little easier, however. The macro can handle a lot of that repeated boilerplate coding for us.

{% highlight crystal %}
{% raw %}
macro alias_method(to, from)
  def {{to.id}}(*args, **dargs)
    {{from.id}}(*args, **dargs)
  end
end
{% endraw %}
{% endhighlight %}

That's cool. It's really simple. It makes use of the [splat (*)](https://crystal-lang.org/reference/syntax_and_semantics/splats_and_tuples.html) and the [double splat (**)](https://crystal-lang.org/reference/syntax_and_semantics/splats_and_tuples.html#double-splats-and-named-tuples) to capture the arguments, and then send them along to the original method.

And, it will work:

{% highlight crystal %}
{% raw %}
macro alias_method(to, from)
  def {{to.id}}(*args, **dargs)
    {{from.id}}(*args, **dargs)
  end
end 

class MyThing
  def add(x, y)
    x + y
  end

  alias_method suma, add
end

thing = MyThing.new

puts thing.suma(123, 456)
puts thing.suma(x: 789, y: 101112)
{% endraw %}
{% endhighlight %}

```
❯ crystal run foo.cr
579
101901
```

This approach has some drawbacks, though. First, a simple macro like that won't work for class methods. It's very easy to create a separate macro for class methods, however.

{% highlight crystal %}
{% raw %}
macro class_alias_method(to, from)
  def self.{{to.id}}(*args, **dargs)
    {{from.id}}(*args, **dargs)
  end
end
{% endraw %}
{% endhighlight %}

The more significant problem is that it won't work for methods take blocks.

{% highlight crystal %}
class MyThing
  def add(x, y)
    x + y
  end

  def do_with(arg, &block : Int32 -> Int32)
    block.call(arg)
  end

  alias_method suma, add
  alias_method con, do_with
end

thing = MyThing.new

puts thing.suma(x: 789, y: 101112)
puts(thing.con(8) {|x| x * x})
{% endhighlight %}

```
❯ crystal run foo.cr
Showing last frame. Use --error-trace for full trace.

In foo.cr:24:12

 24 | puts(thing.con(8) {|x| x * x})
                 ^--
Error: 'MyThing#con' is not expected to be invoked with a block, but a block was given
```

Crystal macros can be overloaded just like Crystal methods, so maybe it'll work to create a macro that can handle both cases?

{% highlight crystal %}
{% raw %}
macro alias_method(to, from)
  def {{to.id}}(*args, **dargs)
    {{from.id}}(*args, **dargs)
  end

  def {{to.id}}(*args, **dargs, &block)
   {{from.id}}(**args, **dargs, &block)
  end
end 
{% endraw %}
{% endhighlight %}

```
❯ crystal run foo.cr
Showing last frame. Use --error-trace for full trace.

In foo.cr:27:12

 27 | puts(thing.con(8) {|x| x * x})
                 ^--
Error: wrong number of block arguments (given 1, expected 0)
```

That would be really nice, but Crystal's type inference does not extend to captured blocks. One must specify the type information on the arguments going into a block and being returned from a block, when one writes a method that will capture a block. The macro doesn't handle any of this, however. So while our original method looks like this:

{% highlight crystal %}
def do_with(arg, &block : Int32 -> Int32)
  block.call(arg)
end
{% endhighlight %}

The alias that the macro writes looks like this:

{% highlight crystal %}
def com(*args, **dargs, &block)
  do_with(**args, **dargs, &block)
end
{% endhighlight %}

And that just won't work the way that we wish that it would.

I would argue that an `alias_method` implementation that can not handle captured blocks (or methods that yield), is a crippled implementation, though, so what can be done?

## `Def#args`

The macro class that represents a method definition ASTNode [has an #args method](https://crystal-lang.org/api/latest/Crystal/Macros/Def.html#args:ArrayLiteral(Arg)-instance-method) that can be used to access the arguments to the method.

On the same note, the macro `Def` class also defines an `#accepts_block?` which can be used to determine whether the method will take a block. If it does, a call to `Def#block_arg` will return any _defined_ block argument. In the case of a method that yields, `#accepts_block?` returns true while `#block_arg` returns a `Nop`.

This can be used to access an argument list for a method:

{% highlight crystal %}
arguments = method.args
{% endhighlight %}

Unfortunately, this has some limitations, because of the way that Crystal method arguments operate. The `Def#args` method will not return any information on any block argument for the method. It does not return a double splat argument, if one exists, and any single splat argument appears as a normal argument in the argument list. So, for example, a method with an argument list like this:

{% highlight crystal %}
def foo(x, *args, **dargs, &block); end
{% endhighlight %}

Would result in a list returned from `Def#args` that looks something like:

{% highlight crystal %}
["x", "args"]
{% endhighlight %}

It is incomplete.

## `Def#block_arg`, `Def#splat_index`, and `Def#double_splat` Methods

Fortunately, Crystal provides all of the tools necessary to faithfully recreate all of the details of a method definition.

{% highlight crystal %}
method_args = method.args
method_args[si] = "*#{method_args[si]}" if si = method.splat_index
method_args << "**#{method.double_splat}" if ds = method.double_splat
method_args << "&#{method.block_arg.id}" if method.accepts_block? && method.block_arg
{% endhighlight %}

## Starting To Put It Together

With this part of the puzzle figured out, let's try to build an MVP for a macro that will allow us to create method aliases. We'll start with the wrapper, and some basic data that we need to do the rest of the work:

{% highlight crystal %}
{% raw %}
macro alias_method(new, old)
  {%
    method_name = old.name
    if old.receiver.is_a?(Nop)
      receiver = @type
    else
      receiver = old.receiver.resolve.class
    end

    new_method_name = new.name
    if new.receiver.is_a?(Nop)
      new_receiver = @type
    else
      new_receiver = new.receiver.resolve.class
    end
  %}
end
{% endraw %}
{% endhighlight %}

That code will provide handles to access the `Def` objects that represent the original and the new methods. It will also provide a handle to the class/module/struct that the method is defined in, in the case of class methods.

Crystal supports method overloading. This means that a single method name can refer to multiple method definitions. Creating a method alias actually means creating aliases for all of the method definitions overloaded onto a single name.

Let's add some code to access those methods (if they exist), as well as a version of the code that we discussed earlier, that provides all of the information necessary to faithfully recreate the method signatures.

{% highlight crystal %}
{% raw %}
macro alias_method(new, old)
  {%
    # [ PREVIOUS CODE ]

    methods = receiver ? receiver.methods.select { |m| m.name.id == method_name } : [] of Nil
  %}
  {% for method in methods %}
  {%
    method_args = method.args
    method_arg_names = method.args.map &.name.id

    if si = method.splat_index
      method_args[si] = "*#{method_args[si]}"
      method_arg_names[si] = "*#{method_arg_names[si]}"
    end

    if ds = method.double_splat
      method_args << "**#{method.double_splat}"
      method_arg_names << "**#{method.double_splat.name}"
    end

    if method.accepts_block?
      method_args << "&#{method.block_arg.id}"
      method_arg_names << "&#{method.block_arg.name.id}"
    end
  %}
  {% end %}
end
{% endraw %}
{% endhighlight %}

This looks promising. Unlike the earlier discussion of method arguments, you can see above that there are two different lists of args. This is because an `Arg`, when ouput to a string, includes type information, and while that is needed to declare a method, it is not needed when creating a call to the method. Thus, we need two lists -- one with that information, and one that is only composed of the argument name: `method_args` and `method_arg_names`.

It will also iterate over all of the overloads for any given method.

## Other considerations

Next comes the real meat of this code. It is time to build an alias. There are a few considerations to take into account before we write that code, though. If we look at Ruby, from which Crystal draws much of its syntactical inspiration, one can do something like this:

{% highlight ruby %}
class Foo
  def foo
    7
  end

  alias_method :bar, :foo
end

puts Foo.new.foo
# => 7

puts Foo.new.bar
# => 7

class Foo; remove_method :foo; end

puts Foo.new.bar
# => 7
{% endhighlight %}

The original method can be removed, and the alias remains functional. With Ruby, once a method is aliased, the method alias is every bit as valid as the original method.

Crystal doesn't provide any mechanism for undefining a method, once it is defined. There may be use cases where it would make sense to be able to do something like this in Crystal, but it is less straightforward. In order to make something like this work in Crystal, the original version of a method that is being aliased would have to be recreated under a different, unique name. Following that, the original method would be rewritten as an alias to the new, unique method name, along with any other aliases.

This would then allow any of the methods, either the original or an alias, to be subsequently rewritten to do something such as throwing a `NoMethodError` when called.

This is, in fact, the approach that the actual [`alias_method`](https://github.com/wyhaines/alias_method.cr) shard takes, but the implementation of it introduces some complexity that is beyond what will be covered in this article. So, for the implementation being presented here (which will have some other shortcomings which will be discussed later), the simpler approach will be pursued. Method aliases will depend on the continued existence of an intact primary method, and will simply provide alternative names for the primary method.

The other consideration is that Crystal has several levels of visibility for methods. By default, they are public, but methods can also be private, meaning that they can only be invoked without a receiver, or with `self` as the receiver, or protected, meaning that they can only be invoked on instances of the same type or in the same namespace (class, struct, module, etc.) as the current type.

So, when constructing aliases, the macro will have to ensure that it recreates the correct visibility of the primary method. This information, as with the argument information, is available from the `Def` instance of a method, via the `Def#visibility` method.'

It may seem like a lot of competing concerns, but let's see how it looks when expressed as code.

{% highlight crystal %}
{% raw %}
    # Code continued from above ...

    if method.accepts_block?
      method_args << "&#{method.block_arg.id}"
      method_arg_names << "&#{method.block_arg.name.id}"
    end

    # Here is the new stuff. This puts all of the pieces together to form
    # a call to the original method.
    call_original_method = [
      receiver == @type ? "".id : "#{receiver.id.gsub(/\.class/, "").gsub(/:Module/, "")}.".id ,
      method_name.id,
      !method_args.empty? ? "(".id : "".id,
      method_arg_names.join(", ").id,
      !method_args.empty? ? ")".id : "".id
    ].join("")
  %}
  {{
    method.visibility.id == "public" ? "".id : method.visibility.id
  }} def {{
           new_receiver == @type ? "".id : "#{new_receiver.id.gsub(/\.class/, "").gsub(/:Module/, "")}.".id
         }}{{
             new_method_name.id
           }}{{
               !method_args.empty? ? "(".id : "".id
             }}{{
                 method_args.join(", ").id
               }}{{
                   !method_args.empty? ? ")".id : "".id
                 }}{{
                     method.return_type.id != "" ? " : #{method.return_type.id}".id : "".id
                   }}
    {{ call_original_method.id }}
  end
  {% end %}
end
{% endraw %}
{% endhighlight %}

## Done

That's it. That is a fully functional macro for creating method aliases. It will work for most crystal methods. So, the code that was presented early in the article? No problems with this version of aliasing:

```
❯ crystal run mvp.cr
101901
64
```

It will handle methods with and without arguments, arbitrarily typed arguments, public, private, and protected methods, block captures, class methods, and methods with specified return types. It also handles methods that use single splat or double splat arguments. It can even alias class methods to instance methods.

The one thing that it does not handle are methods that yield. There is a whole other an of worms that is opened when dealing with those methods. It also depends on the stability of the primary method. That is, if an alias is declared, and the class is reopened, and the primary method is re-written, the alias(es) will point to the rewritten method, and not to the functionality that existed at the time that the alias was declared.

## But, At What Cost?

It would seem logical that method aliases are going to be slower than calling the original methods. After all, one is calling one method, only to have it call a second method. And it is true that when compiling code in development mode, it is slower. However, the compiler is very good at optimization, and when one builds with the `--release` flag, calling an alias becomes just as fast as calling the primary method directly.

Here are some benchmarks. First, the unoptimized difference in performance:
```
Warning: benchmarking without the `--release` flag won't yield useful results
   aliased add (suma) 164.15M (  6.09ns) (± 7.79%)  0.0B/op   1.12× slower
        unaliased add 184.38M (  5.42ns) (± 7.85%)  0.0B/op        fastest
aliased do_with (con) 124.49M (  8.03ns) (± 6.67%)  0.0B/op   1.48× slower
    unaliased do_with 134.95M (  7.41ns) (± 6.97%)  0.0B/op   1.37× slower
```

What the method is doing internally has far more weight with regard to performance than the actually calling of the method, so even for these rather trivial methods, the performance difference is modest. When looking at the optimized case, however:

```
   aliased add (suma) 828.26M (  1.21ns) (± 7.49%)  0.0B/op        fastest
        unaliased add 820.11M (  1.22ns) (± 6.86%)  0.0B/op   1.01× slower
aliased do_with (con) 812.80M (  1.23ns) (± 9.19%)  0.0B/op   1.02× slower
    unaliased do_with 797.39M (  1.25ns) (± 9.85%)  0.0B/op   1.04× slower
Execute:                           00:00:28.590101900 ( 107.20MB)
```

The difference essentially disappears. There is little development performance cost to aliases, and there is no production performance cost.

# Final Thoughts

The general philosophy of Crystal is that there is only one name for any given method. However, there are times when it makes sense to violate this philosophy, whether because one is starting the process of deprecating an old method, or just because it makes sense in the context of some other feature or requirement of a given shard. Regardless of the reason, though, Crystal natively provides the tools for potent extensions of its default capabilities.

A fully implemented version of this shard can be found at [https://github.com/wyhaines/alias_method.cr](https://github.com/wyhaines/alias_method.cr).