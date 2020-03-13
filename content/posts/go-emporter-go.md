---
title: Go, Emporter, Go!
date: 2020-03-13
draft: true
author: Mikey
shortSummary: Emporter uses Go, Docker and Kubernetes to deliver a rock-solid native macOS app.
---

A little over a year ago, I launched [Emporter](https://emporter.app) to help web developers on the Mac live-share their web projects, without needing to deploy code or manage their own server(s). **Emporter** means _to take away_ in French: developers use it to share their projects "on the go". If you're familiar with _ngrok_, it's like that but with a native UI that designers can use, too.

Here's the twist: Emporter is really a collection of services and components, all of which are written in Go. The Mac app is nothing more than a wrapper around an embedded Go client library. The server-side code is fault-tolerant, horizontally scalable, and available in multiple regions --- but most importantly, it's written in tandem with the client such that _everything_ is testable.

It sounds crazy, but advances in tooling made it possible for me release a stable, fully functional version in just a few months of my free time. To celebrate its first anniversary, I'm stoked to share about how I wrote Emporter and what I learned from it.

## Let's Go!

Go makes it easy to write simple, reliable software with clear patterns for concurrency. Its simplicity is a feature: there is no type hierarchy or generics. It has fast compile times, runs anywhere, and has an awesome standard library. It's also very opinionated: packages requires well-defined file (and code) structure, plus it has its own linting/formatting tools. As a result, I find that projects written in Go are maintainable and easy to understand.

**Each major Emporter component is written in Go.** In short, the Mac app leverages native frameworks and languages (AppKit, Swift) to interface with an embedded, cross-platform Go library. It's not as hacky as you think: it's even distributed on the Mac App Store. I've also written an article about [embedding Go in Swift]({{< ref "./writing-mac-apps-in-go" >}}), which includes a sample project.

The decision to write a native Mac app using Go is atypical --- I'm not really aware of others who've done this. However, it's ended up beind a _huge_ win: it's easy for me to move fast during development while producing a stable, performant product.

To better understand its merits, we need to dive deep into Emporter's service architecture. Doing so will give us a clear picture of how features and fixes move gracefully from development to production in a completely controlled environment.

## The actors at play

To explain Emporter's topology, let's consider the different actors staged by Emporter. The **client** Mac app communicates with **provider** services to yield URL(s) accessed by the **consumer**.[^1]

[^1]: Now say that three times, as fast as you can!

When a URL is accessed by a consumer, the provider must find the client and ask it for the resource being requested. Each actor is reliant on the other: if the client disconnects, the provider has nothing to give consumers. If the provider is unreachable, neither client nor consumer can connect. And if there is no consumer, well, there's not much to do.

It's worth noting that each actor is ephemeral. Clients or consumers can connect liberally, while providers may be taken offline during maintenance or when there is less demand. In short, Emporter's job is to bring order to absolute chaos --- something which is expressed in Go quite naturally.

## Provider services

The provider is composed of multiple services, some of which are running redundantly. Each service has a specialized purpose with different resource requirements. It's important that they remain stateless for a few reasons:

1. Services can scale up or down, depending on demand
2. Service instances may be different when a client reconnects
3. Services may exist on different servers
4. Servers can go offline for maintenance
5. It's a good area to develop expertise 😇

In other words, the lifecycle of each service is indeterminate and may be short-lived. In order for the provider to act as a whole, services need to be able to communicate with each other in a meaningful way.

To do this, we need some chewing gum, a paperclip, and a few strands of unicorn hair to glue it together. Or, you know, proven technology created and maintained by people way smarter than me.

### Redis

[Redis](https://redis.io) is used by each service as an in-memory data store and a message broker to handle real-time events. The two most important things stored in Redis is which client can provide contents for a given URL, and which services are healthy.

When initializing, each service enters a _service loop_ which registers itself with Redis. This service loop has two purposes: to make the service's state readable to others in the cluster (to route requests), and to handle unexpected failures gracefully.

State for each service has an expiration time (TTL) set which is extended periodically while the service loop is in a healthy state. When a service prepares to go offline, its data is purged after its connections are drained. If the service becomes unhealthy, its data will be evicted because its TTL will have expired (and the service loop will exit, causing the service to relaunch).

Redis is the back-bone of Emporter's services: it functions as a registry for services and their URLs. To keep latency low, each region runs its own instance of Redis. Consequently, the data stored in Redis is region-specific and exists only in memory. This setup works beautifully out-of-the-box.

### Postgres

Postgres has over 30 years of active development with a strong reputation for its reliability, performance, and features.
I think the most under-appreciated feature is [NOTIFY](https://www.postgresql.org/docs/current/sql-notify.html), which also makes it a robust solution for handling event streams.

Emporter is configured such that each region shares access to the same Postgres instance, effectively making it a global store. In effect, this gives services reliable storage plus means of communicating across regional boundaries, in real-time, as needed.

In short, Emporter's services need to persist data (and receive events) for:

1. Certificates used by TLS handshakes
2. App Store receipts used to verify subscriptions
3. Complaints used to deny access to the service

Whenever a region's certificate is updated, each service needs notified. The new certificate should be dynamically added to the service's listener so that clients can use the new certificate without interruption. The old certificate should continue to work until it actually expires, especially because there still may be active connections using it.

Likewise, when a complaint is acknowledged, each service also needs to be notified so that the offending client can be forced offline. Because the complaint is persisted, subsequent connection attempts should fail.

Postgres provides sane commands with clear approaches to handle these kinds of scenarios gracefully and predictably, without extensions or extra configuration. It's so good.

## Streamlined development and deployment

If I've lost you a little bit, all is forgiven --- TL;DR, there are a lot of moving parts. If Emporter's infrastructure (and code) wasn't managed properly, it'd be a nightmare to develop and keep its services online. Plus, if it wasn't a joy to work on, it'd be a pretty shitty side project. 😅

Keeping things maintainable has come down to three things: creating a stable environment, programmatically asserting behavior within it, and deploying _exact_ replicas of the environment when appropriate.

Believe it or not, advances in tooling has made this entire process a breeze, resulting in a rock-solid and easily maintainable project. I'm excited to share it!

### Automated environments (Docker)

[Docker](https://www.docker.com) is used to automatically create 100% reproducible environments, while Docker Compose provides a simple way to compose services using YAML. Docker Compose makes running multiple, isolated services just a matter of choosing which ports to expose, or where to mount a directory to share data.

Docker has official images for tons of popular software, including Redis and Postgres. If Docker doesn't have an official image for something, it's likely that either its authors or someone else have created one... not that it's difficult to create one yourself.

For example, [Let's Encrypt](https://letsencrypt.org) provides certificates used by Emporter's services to establish TLS connections, which renew automatically based on periodic "auth challenges" that Emporter must solve. The software provided by Let's Encrypt is not only open-source, but it has its own Docker Compose environment maintained by its authors.[^2] In short, I was able run _Let's Encrypt_ locally in a matter of seconds by simply running `docker-compose up`. Now I can locally solve auth challenges in a "real" environment and assert its behavior from anywhere in my stack.

With Docker, my local environment matches production without custom scripts or manual setup. The surface area for unexpected issues is much smaller because there is no difference between the two environments, granted I use the same images in production. And if I test and assert behavior programatically, then I can have confidence in shipping a rock-solid product.

[^2]: [Boulder](https://github.com/letsencrypt/boulder) is the ACME-based certificate authority ran by Let's Encrypt.

### Unit test all the things!

Testing is a natural component of Go's tooling -- it's as simple as defining functions with a _Test_ prefix in a file with a _\_test_ suffix. Every feature, bug or potential issue in Emporter has a test written for it, which helps maintain velocity as the project matures.

As you may recall, every major component is written in Go. From code, servers can be configured on-the-fly to create extremely specific test cases which can also be used to assert client behaviors. These servers are quick and easy to setup/teardown between each test and they're identical to what runs in production, due in part to the reproducible environment. Much the same, the clients used in tests are exactly what's embedded within the Mac app.

As a result, I know _exactly_ how every component behaves when:

1. There are network issues (servers die, clients timeout, etc)
2. Let's Encrypt challenges succeed or fail (plus its effect on clients)
3. "Bad" clients connect (outdated, blacklisted, etc)
4. Race conditions occur in the stack (in or out of process)
5. Event-driven data is pushed across the stack (globally or regionally)
6. Resource pools are completely drained

With Go (plus the reproducible environment), test-driven development seems less like a chore and more of a way _move fast and **not** break things_. I really can't think of a single scenario which would have been quicker to troubleshoot by hand as opposed to reproducing the issue in code and writing a test for it.

### Deployment (Kubernetes)

While Docker lets me create reproducible environments which are deployable anywhere, the last thing I want to do is... deployment. I'd hate to feel like I was constantly "on call" for what I consider to be a side project. So I decided to give [Kubernetes](https://kubernetes.io) a try, and holy shit, it is awesome!

Kubernetes the automates deployment, scaling, and management of (Docker) containers in production environments, based on the same principles which allow Google to run billions of containers a week. I'm obviously not suggesting that I expect Emporter will _need_ to meet such a high demand --- it's most certainly a niche market. However, cloud providers offer a managed Kubernetes service, some of which only require you to pay for the servers (nodes) in the cluster.[^3] Shut up and take my money!

In effect, all I had to do is write a few service definitions for Kubernetes, and deployment was taken care of for me. These definitions are quite powerful: I can define health checks, automatic scaling, resource requirements, and more. It handles rolling updates, too, so services stay online even when new versions are deployed.

It's worth noting that Docker's desktop app ships with Kubernetes, so I'm still able to tweak definitions before applying them to production. That said, I haven't really needed to update the original definitions used for the intitial deployment. It's been remarkably stable.

The main draw back to using Kubernetes is that there is overhead associated with running the cluster, which is disproportionate for small projects like Emporter. However, I think the trade-off is worth it: for an extra ~\$70/month, I don't have to spend _any_ recurring time on infrastructure or lose sleep to keep my services online.

## That's all, folks

Emporter has been an awesome side project because I was able to solve technical problems that I had a genuine interest in solving. Recent advances in tooling allowed me to focus on writing and shipping code, rather than fighting invisible battles.

It's been the ideal project to add to my portfolio because it shows off nearly my entire skillset: web/backend engineering, native Apple development, and UX design. Although not a success financially, my initial motivation for the project was to be able to _ship something_ that represents _me_.

_If you think I'd be an asset for you (or your team), shoot an email to [mikey@youngdynasty.net](mailto:mikey@youngdynasty.net). Or, if you want to keep in touch, I'm [@YoungDynastyNet](https://twitter.com/YoungDynastyNet) on Twitter. My DMs are open._ 🥰

[^3]: At the time, I chose Google Cloud Provider (GCP), but they recently announced that they'll start charging multi-regional configurations. I'll likely move away from GCP within the next month or so, which shouldn't be a huge deal given I can run my stack anywhere.
