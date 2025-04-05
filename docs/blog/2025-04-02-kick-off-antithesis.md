---
slug: kick-off-antithesis
title: Cardano / Antithesis Project Kick-off
authors: [abailly]
tags: [infra]
---

Today, April 2nd, 2025 was the date of the official kick-off for the Cardano/Antithesis project. Already involved in testing and monitoring the Cardano network infrastructure, the [Cardano Foundation](https://cardanofoundation.org) has decided to dedicate resources to evaluate if and how [Antithesis](https://antithesis.com) could increase the reach and level of quality assurance the network needs.

This post introduces the project, its motivations, scope, ambitions, and timeline.

<!-- truncate -->

## Why this project?

The teams implementing the [cardano-node](https://github.com/IntersectMBO/cardano-node) have developed over the years an extensive set of tools, including sophisticated [simulation](https://hackage.haskell.org/package/io-sim) and [model-based](https://hackage.haskell.org/package/quickcheck-dynamic) testing systems

Testing distributed systems at scale is a hard problem, poses unique challenges in terms of tools, scenarios generation, reproducibility, failure analysis, and it requires deep expertise and a significant investment to be effective.

As exemplified by the continued successes of [Jepsen](https://jepsen.io) reports over the past decade, rigorous system-level blackbox testing with fault injections and sophisticated traces analysis can uncover subtle concurrency bugs and security vulnerabilities. However, such tests can quickly be expensive to setup even with virtualised infrastructure, take a lot of time to execute, and are hard to reproduce.

Simulation testing, whereby a piece of software is tested in an environment which _simulates_ its actual execution target to provide better control and allow exploring a lot of scenarios including fault injections, is a quite old technique. The success the [FoundationDB](https://www.foundationdb.org) team had applying this technique sparked the development of [Antithesis](https://antithesis.com), a generic platform for simulation testing of distributed systems.

As the ecosystem grows to include new and different "nodes" in the network like [Dolos](https://github.com/txpipe/dolos), [Dingo](https://github.com/blinklabs-io/dingo), [Amaru](https://github.com/pragma-org/amaru), and many tools and systems building on Cardano core infrastructure, the need arises to investigate how to provide similar system-level testing tools in a language-agnostic way, tools that could be used by the whole community to investigate more scenarios in a more diverse environment.

## What is Antithesis?

In short, Antithesis is a platform combining:

1. A _deterministic hypervisor_ that can run nearly arbitrary pieces of software, emulating the full complexity of the underlying operating system and network, including the ability to simulate the passing of time,
2. _Property-based testing_ and _fuzzing_ to deterministically generate complex test scenarios and check observable properties of the system-under-test, with the ability to _reproduce_ failures,
3. Analysis and reporting tools to help troubleshoot issues signaled by tests run.

The team is responsible for packaging the system-under-test as a "cluster" of containers running and interacting within the simulated environment provided by the platform, for providing test clients and scenarios to explore, and for defining "interesting" properties to verify.

Here is a diagram from [antithesis' website](https://antithesis.com/product/what_is_antithesis/) summarizing how the platform works:

![](https://antithesis.com/img_opt/igPT-jsSII-2034.webp)

## What is this project about?

While we strongly believe in the effectiveness of this approach especially as new components get developed, network grows, and new features are added to the protocol, and Antithesis has already been adopted by industry leaders like Confluent or Ethereum, we want to understand how this investment can yield value to the Cardano community _as a whole_ in a perennial way.

The long-term goal of this project is therefore to collectively build and maintain a testing infrastructure that can benefit the ecosystem and most notably those parties involved in the development and maintenance of the Cardano infrastructure: Nodes, protocols, and related tools. We envision this infrastructure to be governed through an open and transparent process which is yet to be defined, and to be funded by the _community_ through whatever channels seem the most effective, whether it is grants, dedicated treasury withdrawals, infrastructure budget, contributions and fees...

In the short-term however, we need to experiment with the platform, understand what are its capabilities and limits, what it requires from the system-under-test in order to be the most effective, how powerful it is to find and troubleshoot bugs and security vulnerabilities, and more generally openly and candidly build a strong case for the governing bodies of the Cardano ecosystem to decide whether or not this investment shall be pursued.

The phases and coarse-grained timeline of the project are documented in the [README](https://github.com/cardano-foundation/antithesis), and this blog post marks the beginning of the _Proof-of-Concept_ period during which will collaborate with Antithesis to assess the tool.

## Why should you care?

As already stated, the goal of this project is to evaluate whether the Cardano community, as a whole, could benefit from the continuous availability of Antithesis as a testing infrastructure. This means that if you have some expertise on Cardano, its components, the network, the protocol, and if you have ideas on properties we should be testing, scenarios we should investigate, faults and adversarial behaviours we should be prepared to face, we would be more than happy to hear from you!

Concretely, this means that we expect from _you_ as a Cardano enthusiast to help us with:

* Improving infrastructure code (eg. docker images, containers, compose files) we use to run tests, and defining particular setups to test,
* Defining and designing [test](https://antithesis.com/docs/test_templates/) that explore "interesting" scenarios,
* Stating and refining properties that need to old, in specific or generic cases,
* Documenting the expected behaviour in such a way that can easily lead to test generations, for example under the umbrella of teh [Cardano Blueprint](https://github.com/cardano-scaling/cardano-blueprint) project,
* Troubleshooting bugs and security vulnerabilities, following our [Security policy](https://github.com/cardano-foundation/antithesis/security/policy),
* ...
