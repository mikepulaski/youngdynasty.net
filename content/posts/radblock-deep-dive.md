---
title: Diving Deep into RadBlock
date: 2020-02-13
author: Mikey
shortSummary: RadBlock, for Safari, is up to 200 times faster than its competition. The secret? It's quite boring.
---

I should preface this by saying that I'm a huge fan of Safari. It feels super light, has a minimal interface and it doesn't eat away at my battery -- even if I'm streaming Netflix for a few hours (don't judge me).

About two years ago, Safari changed how its extensions worked: they must now be written using Apple's native frameworks. And some time last year, Safari stopped loading extensions which didn't migrate to the new system. I immediately experienced a fall out --- my favorite browser became... shitty.

The ad blocker which I had been using for years became unusable, and its replacement(s) paled in comparison. These replacements were "native" applications, yet they demanded too much of my attention -- why on earth would I want to run another app alongside Safari to use an extension? And why was it now my responsibility to keep it up-to-date?

Logically, the people most likely to write extensions for the web are... web developers. I don't mean that in a bad way... hey, I'm a web developer, too! The problem is, though, that Apple-native code is a much different discipline, and requires the _savoir-faire_ to make things _rad_. It's easy to write native code which accidentally eats up memory, or uses too much computing power. The struggle is real.

Fortunately, I have quite a lot of experience writing native code for Apple's platform. This resulted in a new blocker for Safari, called [RadBlock](https://radblock.app), which is **up to 200x faster** than its competition.[^1] And it most certainly doesn't require an application to run alongside it (aside from its initial installation).

Let's take a deep dive! 🤙

# Overview

There are at least three components associated with a Safari Content Blocker: the blocker itself, an app extension (to show a UI within Safari), and an application to bundle everything together. In practice, each component runs in isolation within its own process, which means that the right hand doesn't know what the left hand is doing. To form a complete product, though, it's pretty important that each part can coordinate with the other in a meaningful way.

Generally speaking, this is called **inter-process communication (IPC)**, and Apple's frameworks provide six different, incompatible ways to do this.[^2] It's also worth noting that some of these approaches do not work from within Safari extensions, are unavailable on all platforms, or are incompatible within the App Sandbox.

# An ode to the boring

I wrote several different prototypes to see what would be the most feasible way to handle IPC, in terms of the path of least resistance. I'm happy to say, the solution(s) ended up being quite boring.

Boring is good. Boring means that it's been around for a long time. Boring means that its limitations are well known and there are plenty of horror stories explaining why it sucks. The longer I've been a programmer, the less I appreciate clever solutions. Boring is not clever. Boring is maintainable.

So, grab a cup of coffee... here are the boring components that glue together [RadBlock](https://radblock.app). ☕️

# NSUserDefaults for small things

`NSUserDefaults` is used to store key-value pairs across app launches. If you've ever written an app, you've probably used it. It's hardly a reason to write a blog post, you might say.

I might have agreed, had it not been for this little gem from _NSUserDefaults.h_:

> NSUserDefaults can be observed using Key-Value Observing for any key stored in it. Using `NSKeyValueObservingOptionPrior` to observe changes from **other processes** or devices will behave as though [it] was not specified.

That last sentence was rather unassuming, but it mentions something rather important: _other processes_. This means that [RadBlock](https://radblock.app) can write and read `NSUserDefaults` values across multiple processes, and each of its processes will be able to observe for changes using **Key-Value Observing (KVO)**.

_It's. So. Boring._

By the way, I couldn't find any real mention of its IPC layer _anywhere_ in the documentation, so thanks to whoever at Apple wrote that comment in the header. 🙃

# SQLite for big things

Out of the box, SQLite handles concurrency for you across multiple processes.[^3] It's very well documented, ships on all of Apple's platforms, and has a simple API. But why does [RadBlock](https://radblock.app) need it?

Values stored in `NSUserDefaults` are persisted using [property lists](https://en.wikipedia.org/wiki/Property_list), which basically means that all of its contents must be rewritten when something changes. If you have a list of exceptions for a blocker rule, modifying a single entry implies that _all_ of its siblings _at minimum_ need to be rewritten to reflect that change.

SQLite helps us solve this problem gracefully with very minimal impact to the code base. The main downside is that each [RadBlock](https://radblock.app) component can't observe changes from outside of its process, but it can still leverage `NSUserDefaults` for some hints on doing the right thing.

Oh, and SQLite is nearly 20 years old. Don't you dare say it's not boring.

# Bundling it up

Now that I found a sensible way to manage models across different processes, it made a lot of sense to bundle it in a framework. By doing so, [RadBlock](https://radblock.app) was granted quite a lot of flexibility -- there's fundamentally no difference between whitelisting a site (or updating its rules) from within the app's preferences or the Safari extension. Wrapping all of its internals in a framework also made it portable to all of Apple's ecosystem, too.

When it came time to choose a language for Xcode's "New Framework" wizard, I had to think about it for a few minutes. This might get spicy.

## Swift? Objective-C?

Let me preface this section by saying that I've been writing Swift for quite awhile and that I haven't written Objective-C in years. I also think that all computer languages are terrible, but for different reasons.[^5]

As previously stated, there are at minimum 3 components in a Safari Content Blocker. And for whatever reason, I often need to do a "clean build" so that Safari reloads my changes while under development. Even during the proof of concept, this became quite tedious, because Swift seemed to take awhile to compile. And because of the way the Swift compiler bundles its results, changes were often not picked up by Safari. It killed my productivity.

Another pain point I found while prototyping was integrating SQLite's C APIs with Swift. If you've ever used a C API with Swift, you probably know what I'm talking about -- `UnsafeMutableBufferPointer` hell. There are Swift packages which "make it Swifty", but I don't really care about having an opinionated third-party abstraction[^6] on top of a simple, heavily documented API.

I think Swift is great for a variety of reasons, and I missed having typed enums, errors and defer statements.

**Yes, I chose Objective-C.**

As of writing, [RadBlock](https://radblock.app) has over _9 dependent targets_ which compile in _4 seconds_[^7] from a clean build folder. It takes less than a second to compile when modifying a single source file if there's derived data.

And yes, you guessed it... Objective-C is boring. SDKs aside, I'm pretty sure [RadBlock](https://radblock.app) would compile with Xcode 4.2 -- when automatic reference counting (ARC) was introduced.

# So why is RadBlock so fast?

If you're familiar with the Safari Content Blocker API, then you know it's literally the equivalent of "load _this_ JSON file". Yes, this entire "deep dive" was to basically manage a _rules.json_ file. Like, the thing that you parse in JavaScript by calling `JSON.parse`. The irony isn't lost on me. This whole "native" thing is slightly ridiculous.

Putting that aside, Apple's frameworks don't offer a way to stream JSON, or to update a Content Blocker's rules modularly. If a rule set updates, or you whitelist a website, you essentially have to reparse every single rule, and update every blocker with its new rules _in their entirety_. The JSON files are quite big, I might add... it can take upwards of 10 seconds to parse a single list with your CPU completely pegged. It's a horrible use of CPU and memory.

I don't really want to give away _all_ of the secret sauce, but one of the special ingredients is "the cloud". Remember when this article started, I said I was a web developer? I'm keeping the server-side dream alive -- there are backend services I wrote which do all of the heavy lifting so that your Mac doesn't have to do the work. There are some exceptions to this, of course, like when you add something to the whitelist. Your data never leaves your device, so [RadBlock](https://radblock.app) does some clever stuff to merge the differences from within the app.

Tangentially related: [RadBlock](https://radblock.app) uses [CloudKit](https://developer.apple.com/icloud/cloudkit/) as its service provider,[^8] which means that it doesn't even have network access. It really is designed with your privacy in mind.

# Conclusion

Using a boring tech stack was the key to making [RadBlock](https://radblock.app) efficient, responsive, and fully autonomous within Safari. The application itself is nothing more than a preferences window. Its extension can fully update its rules automatically without any user intervention. And it's super fast. It's designed to be something you forget about having.

It's currently in private beta, but getting a copy is super easy if you follow [@RadBlockApp](https://twitter.com/radblockapp) on Twitter. I'm really looking for this thing to be battle-tested, so please help spread the word!

Thanks for reading ❤️

[^1]: Read more on the [RadBlock intro](https://radblock.app/blog/introducing-radblock/) page. I promise I'll write up a quantified stats page soon.
[^2]: [NSHipster](https://nshipster.com/inter-process-communication/) covers 6 possible ways to handle this. If you're not crying by the end of the article, consult a doctor.
[^3]: See [SQLite As An Application File Format](https://sqlite.org/appfileformat.html) for more info.
[^4]: At one point, bindings were the future, and you were an idiot if you weren't using them. Now its documentation lives in Apple's archive and its link will probably die soon. It's not actually _that_ cool.
[^5]: Except for Go. I fucking love Go.
[^6]: Popular SQLite wrappers for Swift also have their own threading logic, which smells like tech debt. SQLite is battle-tested and safe for concurrent access.
[^7]: Time measured on a 2017 5K iMac (4.2GHz). It takes about 10 seconds on my 2018 MacBook Air (1.6GHz).
[^8]: CloudKit is unavailable outside of the App Store, as is the RadBlock beta. The beta uses AWS.
