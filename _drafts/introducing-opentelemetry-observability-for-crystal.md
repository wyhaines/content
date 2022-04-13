# Introducing OpenTelemetry Observability for Crystal

## Wait. Crystal?

If you have not heard of Crystal before, it deserves a quick introduction. Crystal is a general-purpose, object-oriented programming language, with a syntax that is heavily influenced by Ruby, with a sprinkling of influence from Go and others. It is a compiled language with static type-checking, but it features a powerful type inference system that eliminates much of the need to write explicit typing. It's not a stretch to say that Crystal provides all of the productivity of a language like Ruby, all of the benfits of static type checking (without most of the disadvantages), and exceptional performance that is competitive with the fastest high level languages available today.

If Crystal is new to you, after you finish reading here, you may want to take a look at the [Crystal Book](https://crystal-lang.org/reference/1.4/index.html) to learn more about the language.

## So, Observability?

Crystal is a fairly mature language, currently at version 1.4.0. There are companies running core systems on Crystal, and offering products implemented with Crystal. However, I saw some comments in a chat forum last year that highlighted one of the things that is holding some people back from a larger adoption of Crystal in production systems.

The problem was [observability](https://newrelic.com/topics/what-is-observability). Observability is proactively collecting, visualizing, and applying intelligence to information collected from your systems to let you understand both what your system is doing, and why it is doing it.

At the simplest end of things, logging provides a vehicle for observability, but log files alone have considerable drawbacks if they are the sole source of observability information in a system. Logs are difficult to manage, search, and monitor, and even small production systems are complicated, and the problems aren't always captured by the logs that are generated.

Filling this gap are observability platforms. If you build an application using Ruby on Rails, you can, with just a few additional lines in your project, add observability to your project. As it runs, data will be delivered to a backend platform to allow you to know what is what is fast, what is slow, and what is failing. You can dig into the collected information to move from what is broken to why it is broken. This ability makes it far more accessible to maintain production systems, and that makes it almost indispensable for many teams.

Crystal, while fairly mature, had not received a lot of attention from existing observability platforms. There is no proprietary observability agent for Crystal from New Relic or any of the other top observability providers. Observability, however, as highlighted in the conversation that I observed, is a crucial tool for many production systems, particularly customer-facing production systems.

## OpenTelemetry?

Over the last decade and a half, there have been a number of platforms built to provide observability. New Relic created the category of APM -- Application Performance Monitoring -- in 2008, and since that time the landscape has fractured with every unique provider having it's own approach and it's own protocol for collecting observability data. Out of this proprietary landscape, something new grew -- OpenTelemetry.

[OpenTelemetry](https://developer.newrelic.com/opentelemetry-masterclass) is a new, open source standard for instrumentation, that is supported by a large developer community composed of end users, cloud providers, and observability leaders including New Relic.

OpenTelemetry puts the application owners into control of their instrumentation. They can choose their observability platform provider based on the features of the platform, rather than the features of their instrumentation or telemetry collection protocols, and can even use an open source platform like [Jaeger](https://www.jaegertracing.io/) to collect and view their data. OpenTelemetry implementations are not vendor specific, and are portable between different platforms.

## Introducing Observability for Crystal Applications

There are a lot of moving parts in OpenTelemetry. The basics of it are readily understood, but the full spectrum of features and capabilities is deeply complex. I started working on the constellation of capabilities to implement a solid OpenTelemetry framework for Crystal more than half a year ago. Some of those subprojects are incomplete, and there is a lot left to do, but the project as a whole has finally come together well enough that it is ready for others to start using it, as well.

So let's take a look at what that really means. How does one implement OpenTelemetry based observability within your Crystal software, and what does that mean? What capabilities does that deliver?

## How To Instrument Your Application

The first approach to instrumenting your Crystal code is to leverage the [OpenTelemetry API](https://github.com/wyhaines/opentelemetry-api.cr) to manually insert instrumentation where you need it.

Let's look at a small example. Consider a small service, built with just the Crystal standard library, that responds to HTTP GET requests by calculating the nth Fibonacci number. The code below isn't the most terse way to do it in Crystal, but it's structured in a way that would reasonably lend itself towards being expanded into a larger, more complex service.

#### **`fibonacci.cr`**
```crystal
require "http/server"
require "big/big_int"

class Fibonacci
  VERSION = "1.0.0"
  private getter finished : Channel(Nil) = Channel(Nil).new

  def fibonacci(x)
    a, b = x > 93 ? {BigInt.new(0), BigInt.new(1)} : {0_u64, 1_u64}

    (x - 1).times do
      a, b = b, a + b
    end
    a
  end

  def run
    spawn(name: "Fibonacci Server") do
      server = HTTP::Server.new([
        HTTP::ErrorHandler.new,
        HTTP::LogHandler.new,
        HTTP::CompressHandler.new,
      ]) do |context|
        n = context.request.query_params["n"]?

        if n && n.to_i > 0
          answer = fibonacci(n.to_i)
          context.response << answer.to_s
          context.response.content_type = "text/plain"
        else
          context.response.respond_with_status(400,
            "Please provide a positive integer as the 'n' query parameter")
        end
      end

      server.bind_tcp "0.0.0.0", 5000
      server.listen
    end

    self
  end

  def wait
    finished.receive
  end
end

```

To run this, you might have a second file that does something like this:

#### **`server.cr`**
```crystal
require "./fibonacci"
Fibonacci.new.run.wait
```

The full code for this small, uninstrumented application can be viewed at [https://github.com/newrelic-experimental/mcv3-apps/tree/kh.add-crystal-example-20220412/Uninstrumented/crystal](https://github.com/newrelic-experimental/mcv3-apps/tree/kh.add-crystal-example-20220412/Uninstrumented/crystal).

If you pull the code from that repository, you can follow the instructions there to run it. The TL;DR is:

```bash
crystal build -p -s -t --release src/server.cr
./server
```

### Instrumenting Your Application

OpenTelemetry generally requires a small amount of up-front configuration in order to make the best use of it. You will generally want to provide a *service_name*, a *service_version*, and *exporter* when initializing the API.

So, let's require the instrumentation package in `fibonacci.cr`, and add it's configuration to `server.cr`:

#### **`fibonacci.cr`**
```crystal
require "http/server"
require "big/big_int"
require "opentelemetry-api"

```

#### **`server.cr`**
```crystal
require "./fibonacci"

OpenTelemetry.configure do |config|
  config.service_name = "Fibonacci Server"
  config.service_version = Fibonacci::VERSION
  config.exporter = OpenTelemetry::Exporter.new(variant: :http) do |exporter|
    exporter = exporter.as(OpenTelemetry::Exporter::Http)
    exporter.endpoint = "https://otlp.nr-data.net:4318/v1/traces"
    headers = HTTP::Headers.new
    headers["api-key"] = ENV["NEW_RELIC_LICENSE_KEY"]?.to_s
    exporter.headers = headers
  end
end

Fibonacci.new.run.wait
```

The above code block does three things. It sets the service_name and the service_version in the configuration, and then it defines the exporter to use. There are a variety of exporters that are provided. Some, are just used for testing, like the `:stdout` exporter (dumps the OpenTelemetry data to STDOUT, as JSON). Some can be used for testing or for piping the OpenTelemetry data to another service, like the `:io`, and some are used for sending the data to your backend observability platform of choice, like New Relic. The `:http` variant, with a class name of `OpenTelemetry::Exporter::Http`, is used to deliver data using the `OTLP/HTTP` protocol.

Using that protocol with New Relic requires providing a license key so that the New Relic data ingest systems can deliver that data to the correct account. The other code attaches a set of custom HTTP headers to the exporter, which will be set on every request, and sets one of those headers to be the license key, which is assumed to be stored within the `NEW_RELIC_LICENSE_KEY` environment variable.

The only step that is left is to add some actual instrumentation. OpenTelemetry Traces operate off of a data model where a `Trace` is essentially a container for other data, one portion of which is an array of `Span`s. A `Span` is a unit of work, with a distinct start and end time, a name, and some other metadata, as well as an option set of attributes and events. Thus, a trace is composed of one or more spans.

If we want to collect data on how long it takes to calculate the Fibonacci numbers, as well as what numbers are being calculated, we can instrument the `fibonacci` method to do this:

#### **`fibonacci.cr`**
```crystal
def fibonacci(x)
  trace = OpenTelemetry.trace # Get the current trace or start a new one
  trace.in_span("Calculate Fibonacci ##{x}") do |span|
    a, b = x > 93 ? {BigInt.new(0), BigInt.new(1)} : {0_u64, 1_u64}

    (x - 1).times do
      a, b = b, a + b
    end

    span["fibonacci.n"] = x
    span["fibonacci.result"] = a

    a
  end
end
```

That is all that you need to do. Now, if you recompile the code, and start the server with your license key:

```base
NEW_RELIC_LICENSE_KEY=<your license key> ./server
```

Any time a request comes into the server that results in the calculation of a fibonacci number, a trace will be created, and it will be sent back to New Relic, where it can be viewed in New Relic One.

### What About Errors, And Everything Else?

One thing that might occur to you is that the above only traces a small part of the whole process. This is true, and if you wanted to instrument the rest of it, and capture errors, you could write more custom instrumentation, and even write patches to the standard library to instrument its internals, or an instrumentation handler that can be injected into the HTTP request handler chain for an application. That's a lot of writing, though.

The OpenTelemetry Instrumentation package, however, provides many prebuilt instrumentation packages that can be installed into your application just by requiring them.

To do this, first change the require block at the top of the `fibonacci.cr` file to:

#### **`fibonacci.cr`**
```crystal
require "http/server"
require "big/big_int"
require "opentelemetry-instrumentation"

```

Then, instead of doing what we showed above, to instrument your `#fibonacci` method, you can do so more concisely by adding the following block to your `server.cr` file:


#### **`server.cr`**
```crystal
class Fibonacci
  trace("fibonacci") do
    OpenTelemetry.trace.in_span("fibonacci(#{x})") do |span|
      span["fibonacci.n"] = x
      result = previous_def
      span["fibonacci.result"] = result.to_s
    end
  end
end
```

This time, when you run the server, the auto-instrumentation will instrument the entire HTTP::Server request/response cycle, and it will also instrument the `Log` class provided by the standard library, so that any generated logs from the application get added to the spans where they occur, as events (in the future these will be first class OpenTelemetry Log records).
