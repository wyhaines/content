---
layout: post
title: "A Not-So-Illustrated Guide to Translating Code From Ruby To Crystal"
date: 2021-03-04 08:00:00 -0700
tags: ruby crystal rewrite
categories: crystal
---
# The Spark

Once upon a time, about three years ago, I had a great idea; I wanted to implement an auto-deployment infrastructure across a bunch of servers that I was running. When a commit was pushed into GitLab/GitHub, if the branch that received the commit was deployed on one of the servers that I was managing, the repository on that server should pull the changes, and then optionally there would be a post-update hook that could be invoked to complete the local deployment.

The deploy hooks for both GitLab and GitHub attach the repository URL to the payload, so what I decided that I needed was a simple way to drop a database onto a given system that could track the git repositories on that system. Ideally, it would be something fast, and something simple enough that it did not require any real ongoing management or resources.

Enter [git-index](https://github.com/wyhaines/git-index). This is a simple [Ruby](https://www.ruby-lang.org/) app that maintains a local [SQLite](https://www.sqlite.org/index.html) database of git repositories, providing a command-line interface to add, list, query, or remove entries. 

One of the things that I like about [Crystal](https://crystal-lang.org/) is that as a compiled language, one can build single binaries for utilities without depending on having the entire installed language at one's disposal. I figured that it might be an interesting exercise to take an hour or two to translate git-index from Ruby to Crystal.

## Typing Empty Arrays

Crystal has a Ruby-inspired syntax, and on a small scale, a lot of Ruby code is also valid Crystal, but there are some notable differences.

One of the first things that one will encounter when porting Ruby to Crystal is how typing changes the way empty arrays and hashes are declared. In Ruby, one does a simple assignment:

```ruby
leftover_argv = []
```

This will result in an error in Crystal, however:

![image](https://www.wyhaines.com/assets/img/posts/2021-03-04-a-not-so-illustrated-guide-to-translating-code-from-ruby-to-crystal/for_empty_arrays.png)

Fortunately, the exception is clear about the problem, and the solution:

```crystal
leftover_argv = [] of String
```

## Instance Variables

The next major gotcha involves [instance variables](https://crystal-lang.org/reference/syntax_and_semantics/methods_and_instance_variables.html). In the original code, it was written to use class methods and to declare class instance variables.  In hindsight, I decided that was a poor choice. So, in this port, I decided to make everything work from an instance of `GitIndex` instead of operating via class methods on `GitIndex` itself.

The implementation of this change is basically identical to how one would do it in Ruby, so I won't go into details there, but there is an important detail to consider in regard to instance variables.

In Ruby, one can declare an instance variable at any point in the code, and it will work with no problems. Ruby is very dynamic in that regard. With Crystal, however, instance variables must be declared at the class level and must be initialized directly either at the class level or in the `#initialize` constructor for the class.

Failing to do so may reward one with the following type of error:

![image](https://www.therelicans.com/remoteimages/uploads/articles/tfe6mt6mqd6ddp3eblwv.png)
 
To do indirect initialization of an instance variable without earning the error message above, the instance variable has to be declared at the class level with a nilable type:

```crystal
class Foo
  @bar : String?     # This is nillable.
  @qux : String = "" # This has a default but is not nilable.
```

In the Ruby version of the code, the following was a fine way to initialize an instance variable for the first time:

```ruby
def run
  @config = Config::parse_command_line
```

In Crystal, that initialization must occur earlier.

There are a few different options. One is to specify the typing information of the instance variable at the class level:

```crystal
struct GitIndex
  @config : Hash(String, Bool | String | Symbol) = Config.parse_command_line
```

That works great and has the advantage that the instance variables that exist in the object definition are all clearly visible. And because the initialization can occur at the class level, there isn't even a need to provide an `#initialize` method.

There is an alternative, where the initialization is done in the argument specification of the `#initialize` method. The actual initialization code only differs from the code above by where it is placed:

```crystal
def initialize(@config : Hash(String, Bool | String | Symbol) = Config.parse_command_line)
end
```

This approach combines the argument specification for the constructor with assignment to the instance variable. I like this approach because it allows the code to have a default configuration handling path, but it also allows someone to circumvent that and to provide a `Config` instance themselves just by changing the location of the initialization.

## Database Access

The only other significant stumbling block to porting this utility to Crystal was porting the code that interacts with the database.

Ruby has a variety of different gems that can be used for database access, with varying levels of abstraction from [gems that offer direct low level](https://www.ruby-toolbox.com/categories/SQL_Database_Adapters) access to a database, to gems which offer a high level ORM, like [ActiveRecord](https://guides.rubyonrails.org/active_record_basics.html) or [Sequel](https://github.com/jeremyevans/sequel), and which typically implement their own mid level abstraction layer.

In the original code, I used the SQLite3 gem directly, which offers a simple API. After creating an instance of the class, one can use `#execute` to run SQL and to perform queries in general.

[Crystal has a standard database interface API](https://crystal-lang.org/reference/database/index.html) as part of the language specification. Different database drivers can implement their own backend capabilities, but they are all accessed through that common database interface API. Unlike the SQLite3 gem, where everything can be done through `#execute`, with the Crystal database API, queries are executed via `#query`, while other SQL is executed via `#execute`.

Also, because of the very dynamic nature of Ruby, the return set of a database query can be iterated over simply as a set of arrays. Because Crystal is typed, however, and Arrays have to be typed, there is a little more work that has to be done on the Crystal side. So, as an example, this code in the Ruby version:

```ruby
def list_records(db)
  puts "hash,path,url"
  db.execute("SELECT hash, path, url FROM repositories") do |row|
    puts row.join(',')
  end
end
```

Looks like this in the Crystal version:

```crystal
def list_records(db)
  puts "hash,path,url"
  db.query("SELECT hash, path, url FROM repositories") do |rs|
    rs.each do
      puts [rs.read(String), rs.read(String), rs.read(String)].join(",")
    end
  end
end
```

The Crystal is a little more verbose for two reasons. First, a query returns a result set that must itself be iterated over to access each of the rows in the result set, and second, each field must be read with typing information provided. Similar changes have to be made in each of the methods that queried data from the database.

## Build It!

You can access the source code, or download a prebuilt Linux x86_64 binary via the GitHub project:

https://github.com/wyhaines/git-index.cr

If you have Crystal installed locally, you can build it:

![image](https://www.therelicans.com/remoteimages/uploads/articles/q74tqpe0j7con1t38cli.png)

## Profit!

While the runtime resource usage of a CLI tool like this isn't super important, it is interesting to illustrate the difference between the Ruby version and the nearly identical Crystal version.

On a real server with 53 indexed repositories, the Ruby version's `time` information when executing `git-index -l` is:

![image](https://www.therelicans.com/remoteimages/uploads/articles/tkcdqhfv8xwbjkxgfsp7.png)

It takes 0.15 seconds to run.

`time -v` can be used to capture memory usage while running, as well:

![image](https://www.therelicans.com/remoteimages/uploads/articles/pap3h1pd1y94grxd7sht.png) 

And while running, it requires 14.36M of RAM.

The Crystal version, on the same machine, with the same data:

![image](https://www.therelicans.com/remoteimages/uploads/articles/rrecrfq5ksi1luqt6jw9.png)

It runs in 0.006 seconds - about 25x faster - and it also only uses 3.98M of RAM.

![image](https://www.therelicans.com/remoteimages/uploads/articles/lrzaxph95c9nf3mbn8jo.png)
 

Crystal is a great language to port your Ruby CLI tools into!

---

I stream on Twitch for The Relicans. [Stop by and follow me at https://www.twitch.tv/wyhaines](https://www.twitch.tv/wyhaines), and feel free to drop in any time. In addition to whatever I happen to be working on that day, I'm always happy to field questions or to talk about anything that I may have written