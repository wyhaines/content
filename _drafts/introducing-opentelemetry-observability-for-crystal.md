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



OpenTelemetry generally requires a small amount of up-front configuration in order to make the best use of it. You will generally want to provide a *service_name*, a *service_version*, and *exporter* when initializing the API.