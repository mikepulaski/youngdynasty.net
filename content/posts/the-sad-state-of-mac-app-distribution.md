---
title: "The Sad State of Mac App Distribution"
date: 2019-08-14T10:30:00+02:00
author: Mikey
shortSummary: Distributing outside of the Mac App Store has slowly become a nightmare.
---

Recent versions of macOS have sought to improve the integrity and security of the platform by asserting more control over applications. Since Mac OS X 10.8, applications without a valid signature were no longer opened without user intervention. Now, starting with macOS 10.14.5, the same holds true for apps which aren't notarized by Apple.

As the security of the platform has tightened, the tools used by developers to manage updates have become antiquated and insecure. And with the notarization requirement now in place, it has become even more unmanageable.

## Here's the thing

Let's look at the two most popular (if not only) means of distributing software updates outside of the Mac App Store: [Sparkle](https://github.com/sparkle-project/Sparkle) and [Squirrel](https://github.com/Squirrel/Squirrel.Mac). Both projects are open-source and were written before some, if not all, of the new security practices. They rely on contributors, many of whom make contributions in their free time. They've provided a fantastic, invaluable service to the community.

Now let's look at the ugly truth:

**These Third-party Mac app updaters, used by thousands, rely on security APIs that were deprecated five to eight years ago.[^1][^2]**

Sparkle 2.0 is now in beta after 3 years of development, which aims to support the App Sandbox. However, upon closer inspection, it still relies upon security APIs deprecated 5 years ago.[^2]. Squirrel also relies those same deprecated APIs but there doesn't seem to be any planned development to support the App Sandbox.

How much longer can we expect these APIs to work? Shouldn't they already have been removed?

[^1]: [`AuthorizationExecuteWithPrivileges`](https://developer.apple.com/documentation/security/1540038-authorizationexecutewithprivileg) is used by the current stable Sparkle version. It was deprecated in OS X Lion (10.7).
[^2]: [`SMJobSubmit`](https://developer.apple.com/documentation/servicemanagement/1431084-smjobsubmit) is used by Squirrel and Sparkle 2.0. It was deprecated in macOS Yosemite (10.10).

### Change is hard

Sparkle was created in 2006 and has thousands of applications which rely upon it. Much the same, Squirrel was started in 2014, and is the official updater for [Electron](https://electronjs.org) applications.

To adapt the new security APIs, privileged helpers must be installed to handle the actual update extraction and validation. These helpers _must_ know the code signature of the host application beforehand, otherwise macOS will not authorize the helper to run. This change seems subtle, but in actuality it's extremely difficult to accommodate without completely revisiting the interface between the target application and the updater. How can these updaters possibly know the code signatures for the applications which will embed them? These applications may not even exist yet!

Suffice to say, neither updater can easily adapt to the new security APIs without completely disrupting developer workflow or the applications which depend on them. This could perhaps explain why neither Sparkle or Squirrel have been able to adopt the newer APIs.

## Everyone's hands are tied

It's easy to consider Apple's notary requirements and API deprecations as hurdles meant to coerce developers to use the Mac App Store. It's hard to imagine that's not partially true. However, if that were the sole reason, they would have simply removed the APIs marked as deprecated _years_ ago; yet they haven't. Doing so would have broken the Mac's third-party ecosystem.

It's in the user's best interest to have applications adopt the App Sandbox along with APIs which minimize potential security vulnerabilities. By allowing our apps to use insecure or outdated APIs, or even worse, disabling advancements in security to use them, we're being hostile towards the people using our software.

## Who cares?

Fixing the software updaters takes time (money) which would be better spent on developing a product. This dilemma is inherited and solveable by experienced third-party macOS developers, but how many of us are left? I, for one, make most of my income from writing backend web services. I just happen to really love the platform.

There is also a shift in macOS development: writing cross-platform apps using either [Electron](https://electronjs.org) or [Catalyst](https://developer.apple.com/ipad-apps-for-mac/). Making it easier to write an app for macOS is awesome, but doesn't address the more nuanced issues to keep the ecosystem healthy. For it to prosper, apps don't need to just run on macOS, they need to _be on_ macOS. It's more than what's skin deep, and it needs individual attention.

If done right, though, newcomers don't need to worry about these details and they can continue honing their craft.

## A possible solution

A new (or patched) updater would be composed of a few different components: a framework for Mac apps to consume updates, a tool for developers to distribute updates, and a server to serve feeds.

The end goal would be a ready-to-use framework to apply updates and developer tools to publish and/or manage them.

### A new bundled framework

The bundled framework is perhaps the biggest change.

Application updaters, especially within the App Sandbox, depend on external processes to perform the actual update. The deprecated APIs that mentioned earlier in this post need to be replaced by their successors, which only allow interprocess communication when code signatures are known beforehand.[^3] While this dramatically reduces the exploitable surface area, it's a difficult requirement for shared frameworks to meet: each app using the framework has its own signature which isn't known until runtime.

[^3]: [`SMJobBless`](https://developer.apple.com/documentation/servicemanagement/1431078-smjobbless) is the successor to the deprecated APIs. It installs privileged "jobs" (i.e. update installers) as Mach Services. They are only reachable after code signature requirements specified in each bundle's `Info.plist` are matched, which is difficult to maintain within a public framework.

However, if the framework had an insular design with pre-built releases, this complexity could be nearly removed from scope. The framework along with its components could be signed using the same certificate, at which point it'd be safe to use from any app which bundles it.

Regardless of the need to distribute pre-built binaries, the framework should be open source. It needs to be possible to vet, fork, and make modifications with complete freedom. Because any forks or changes would require it to be rebuilt with different signatures, this wouldn't have an impact on other applications using the official release.[^4]

[^4]: The code signing requirements ensure that apps will only run unmodified code that it ships.

### Other components

The other components, the developer tools and update feed, are "nice to have" features which would make it easy to actually "ship it!" 🐿

The developer tools could do pre-flight checks with Apple's notary and verify the update's signature before updating the feed. The feed could be then updated either dynamically or statically --- the less assumptions made, the better. It's clear to me, though, that people shouldn't have to manage their own servers to distribute updates. [GitHub Releases](https://github.blog/2013-07-02-release-your-software/) might also be an interesting way to power a feed for open source apps.[^5]

[^5]: I've already written an updater, powered by GitHub Releases, for the [`emporter`](https://github.com/youngdynasty/emporter-cli) tool which made deployment drop-dead easy.

### A clean slate

Although it _is_ entirely possible to update the existing projects to properly support the new security advances, it may be best to start over for the sake of simplicity for new and existing projects.

While Squirrel relies on the same code signing mechanism as macOS, its main author is no longer part of the project. This in itself isn't a big deal, but it hasn't had meaningful development for over 18 months. It's also written using _ReactiveCocoa_ which makes the barrier high for those seeking to contribute.

Sparkle, on the other hand, has features which add too much friction to applications which support the new security model on macOS. It requires its feed to include signed hashes of each item, independent of code signing, for validation. If applications _must_ be notarized and code signed, I don't think this is necessary anymore. If code signing and notarization checks succeed, we know with a high degree of confidence that we're not replacing the application with corrupted or compromised code.

Sparkle also supports binary deltas, which is pretty awesome, but complicates how a new updater might do its job. Binary deltas make it much more difficult to deploy feeds as it needs to keep track of previous updates to yield a usable result. Although this could be cool have at some point, needing to support it from the start would add a lot more effort.

Lastly, Sparkle relies on lots of other deprecated APIs not mentioned in this post. Taking all of this into account, it sounds like might need a complete rewrite. Hey, maybe we could call it _Sparkle 3_!

Regardless, the changes are significant enough that even if the existing projects were updated for 2019, the way applications would need to integrate them would be completely different. If you already would need to integrate a new version (potentially with legacy code), what's the difference between that and starting over? Nothing but the extra baggage, which would likely slow down the development process. 😬

## Closing thoughts

I'd love to fix this myself, but I just don't know if I have the time or need for it _yet_. I've shipped [Emporter](https://emporter.app) on the Mac App Store and do want to distribute a version independently, but it may not be economically feasible for me to shift focus at this time.

I would love to hear back from the community and discuss how we can move forward. Don't hesitate to get in touch via [@YoungDynastyNet](https://twitter.com/YoungDynastyNet) or [mikey@youngdynasty.net](mailto:mikey@youngdynasty.net). My DMs are open.
