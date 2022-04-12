---
layout: post
title: "Packing Static Files Into Crystal Binaries"
date: 2021-10-08 08:00:00 -0700
tags: crystal
categories: crystal
---
![Packing](/assets/img/posts/2021-10-24-packing-static-files-into-crystal-binaries/packing.jpg)

Last week, I was hanging out in the [Crystal Discord](https://discord.com/invite/YS7YvQy) when what to my wondering eyes should appear? These words:

```
would be cool
everything in one assembly
a single executable to do everything
actually i dont think crystal can pack images and files into the result executable
```

With the help of Crystal macros, this very thing is quite doable. I did not realize at the time that there was an [existing project](https://github.com/schovi/baked_file_system) that provides a version of this functionality, and so I wrote my own version.

## Baked File System

I should mention the existing project. The `baked_file_system` shard hasn't seen maintenance since Crystal 0.35.1. Running it under Crystal 1.2.1, all of its specs pass, but it does throw an exception (which doesn't cause spec failure). So, it may or may not work out of the box right now, but if it needs fixes, they should be very modest.

The Baked File System seeks to provide a file-system-like-capability for static files that are compiled into the executable. One can treat them, more or less, like read-only files. It also automatically applies compression to the files, sacrificing some speed for space savings. It is a very neat little project, and offers a nice approach to this problem.

## My Version

What I wrote is less ambitious. It doesn't seek, in any way, to emulate a filesystem approach to accessing the data. It simply packs the data into the executable, within structs that are held and organized in a hash-like way, for easy access. Files which are stored in the executable are accessed via the paths that were used when storing them, and there are methods made available to query/search the file store using just fragments of the path.

The end result is a small, fast, lean system that can be used to pack static files into an executable, and to access that data as needed. So let's take a look at just how that works.

# How It Works

Crystal macros write new code at compile time. In most cases, this facility is used to generate code based on arguments passed into the macro. A standard library example of this is [`record`](https://crystal-lang.org/api/latest/toplevel.html#record%28name%2C%2Aproperties%29-macro) macro, which is used to create a new struct, complete with predefined data fields and any methods that the programmer wants to include.

Crystal macros, however, also have several tools to let someone access other sources of data at compile time. One of these is the [`read_file`](https://crystal-lang.org/api/latest/Crystal/Macros.html#read_file%28filename%29%3AStringLiteral-instance-method) method.##

## [`read_file`](https://crystal-lang.org/api/latest/Crystal/Macros.html#read_file%28filename%29%3AStringLiteral-instance-method)

This macro method reads a file and returns at `StringLiteral` with the contents of the file. At its core, this is all that one truly needs to inject the contents of a file into an executable:

{% highlight crystal %}
{% raw %}
file_contents = {{ read_file("/path/to/file") }}
{% endraw %}
{% endhighlight %}

Breaking it down for you, the code inside of the `{{ }}` is macro code, the result of which is inserted at that location, as crystal code. In this case, the macro code uses `read_file` to read the contents of a file, and those contents are inserted *as a string*, at that location.

This is very simple, and for one or even a small handful of files, there would be little reason to reach for any sort of shard to make this easier. However, as with everything, where there is a repeated pattern that involves a lot of the same code, abstractions can make that task more pleasant to work with. That is what the `datapack` shard is for.

## [`Datapack.add`](https://wyhaines.github.io/datapack.cr/Datapack.html#add%28path%2Cnamespace%3D%22default%22%2Cmimetype%3Dnil%29-macro)

When you need to add a clearly defined set of files to the executable, you can use `Datapack.add` for this.

{% highlight crystal %}
Datapack.add("/path/to/file.txt")
{% endhighlight %}

This macro creates a line which would be something like this:

{% highlight crystal %}
Datapack::Data[Path.new("default://path/to/file.txt")] = Datapack::Resource.new(
        path: "/path/to/file.txt",
        data: "if this were the contents of the file, this would be the contents of the file",
        mimetype: "text/plain; charset=utf-8")
{% endhighlight %}

The `add()` macro makes a naive attempt to determine the mimetype of the file, but it only maps about 30 common mime types within the macro, so when in doubt, you can always specify the mimetype yourself:

{% highlight crystal %}
Datapack.add("/path/to/file.txt", mimetype: "text/plain; charset=utf-8")
{% endhighlight %}

Also, take note of the path that is given to the `Resource`: `default://path/to/file.txt`. Every resource that is added to the datapack must have a unique path, and that path can be prefixed with a namespace. The namespace is some label, followed by a colon, and if it is not specified, it will default to `default`.

Namespaces can be useful to categorize assets, and are primarily implemented for programmer convenience. If they are not useful for someone's use case, they can be safely ignored, as the code will automatically ensure that a `default` namespace is applied in that case.

## [`Datapack.add_path`](https://wyhaines.github.io/datapack.cr/Datapack.html#add_path%28path%2C%2Aglobs%2C%2A%2Aoptions%29-macro)

In cases where there are many files to add, or where it is not known at the time that the code it written exactly which files need to be included into the compiled binary, there is another macro that one can use. This macro is `Datapack.add_path`, and it does just what its name suggests, adding all of the files within a given path, that match any of the given [file glob patterns](https://crystal-lang.org/api/1.2.1/File.html#match%3F%28pattern%3AString%2Cpath%3APath%7CString%29%3ABool-class-method).

{% highlight crystal %}
Datapack.add_path("/path/to/files", "**/*.png", "**/*.jpg", "**/*.gif")
{% endhighlight %}

This will add all `png`, `jpg`, and `gif` files within the `/path/to/files` directory and all of its subdirectories to the datapack.

Macro code is extremely limited with regard to what it can do. Other than the `read_file` method which was mentioned earlier, there are no facilities within Crystal macros to interact with the filesystem in any way. However, Crystal does provide an escape-hatch. It provides a [`run`](https://crystal-lang.org/api/1.2.1/Crystal/Macros.html#run%28filename%2C%2Aargs%29%3AMacroId-instance-method) macro method. The method will *compile and execute* the file given as an argument, and whatever is returned from that execution is returned from the `run` call as a `MacroId`.

For the purpose of packing an entire directory, there is a very small utility bundled into the shard that, when compiled, yields a simple script that walks a directory, matching any of the file pattern globs that it was given (and matching **/* if nothing was provided), and then returns both the path to each file, and it's MIME type, as determined by the standard Crystal MIME library. This results in a pretty robust solution for finding files to read, and for determining their MIME types. Any file with a type that still can not be determined will be labeled as `application/octet-stream`.

It is easy to imagine a scenario where one has a complete web site, or some application where, for business or ease-of-distribution purposes, it would be nice if the whole thing could be packaged into a single executable file, with no other dependency on any resources within the filesystem.

As an example, consider this small [Kemal](https://kemalcr.com/) application:

{% highlight crystal %}
require "kemal"
require "datapack"

module Dpex
  VERSION = "0.1.0"
end

Datapack.add_path("./assets","**/*",namespace: "assets")

get "/assets/:path" do |env|
  path = env.params.url["path"]
  resource = Datapack::Data.find?("assets:/./assets/#{path}")
  if resource
    env.response.headers["Content-Type"] = resource.mimetype
    resource.data
  else
    env.response.status = HTTP::Status::NOT_FOUND
  end
end

Kemal.run
{% endhighlight %}

This will compile all of the files which are in the `assets/` directory into the Kemal server's executable, and any access to `/assets/` will be served out of those compiled in files. All that is needed is the compiled executable file.

If you are curious, here is how the performance looks on my desktop, running Ubuntu 20.04 under WSL2.

```
Document Path:          /assets/bar.html
Document Length:        69 bytes

Concurrency Level:      20
Time taken for tests:   0.442 seconds
Complete requests:      10000
Failed requests:        0
Total transferred:      1690000 bytes
HTML transferred:       690000 bytes
Requests per second:    22602.60 [#/sec] (mean)
Time per request:       0.885 [ms] (mean)
Time per request:       0.044 [ms] (mean, across all concurrent requests)
Transfer rate:          3730.31 [Kbytes/sec] received
```

## Searching the Datapack

In addition to the basic Hash-like `#[]` and `#[]=` methods for accessing the datapack, the Datapack shard offers several convenience methods for searching the files stored in the pack. It creates a simple Path based index of all of the files, based on the individual fragments of the path. There is a set of convenience methods that can search this index in order to find files with only partial path information, or to find collections of files under a given namespace or partial path.

The following methods are provided:

* `#[]` - Returns the resource at the given path.
* `#find` - Finds a single file by `Path` or a `String`
* `#find?` - Finds a single file by `Path` or a `String`, returning `nil` if not found
* `#find_all` - Finds all files matching a given `Path` or `String`
* `#find_key` - Finds a single key by a `Path` or `String`
* `#find_key?` - Finds a single key by a `Path` or `String`, returning `nil` if not found
* `#find_all_keys` - Finds all keys matching a given `Path` or `String`

Usage looks like this:

{% highlight crystal %}
file = Datapack.Data["assets:/./assets/bar.html"]
the_same_file = Datapack.find("assets:/bar.html")
asset_keys = Datapack.find_all_keys("assets:")
images = Datapack.find_all("assets:/images")
{% endhighlight %}
## Wrapping Up

Embedding static files within an Crystal executable is a straightfoward process, using a macro and the `read_file` macro method. If you are embedding a lot of files, or you want convenience methods for accessing and searching the files that are embedded, a shard like [datapack.cr] or the older and more filesystem-oriented [baked-file-system](https://github.com/schovi/baked_file_system) is a lot more convenient than writing all of the file reading boilerplate yourself.