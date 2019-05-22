---
title: "Say Hello to YDCommandKit"
date: 2019-05-22T19:48:19+02:00
author: Mikey
summary: Write native macOS apps for the command-line using YDCommandKit.
---

I recently created a command-line interface (CLI) create secure URLs to a Mac by automating [Emporter.app](https://emporter.app). Quite naturally, I didn't want to write my own code to do perform the basics, such as parsing command-line arguments or handling options in a type-safe way.

Much to my surprise, there were not any viable libraries that could help me do this. Seriously. Let me elaborate.

Our collective effort, as Apple developers, over the past few years has been largely focused on Swift. Swift, however, has only recently become stable enough for its runtime to be included with _very_ recent releases of macOS (and iOS). As a consequence, when you ship a Swift app, it needs be bundled with the Swift runtime. And to make matters worse, third party Swift libraries are not static and therefore must be bundled within the app. This is fine in most cases, but not for something that's intended to be shipped as a single binary, like, you know... a CLI. _Uh oh._

__So here I am, introducing a brand new static Objective-C library, in 2019: [YDCommandKit](https://github.com/youngdynasty/YDCommandKit).__

You may be wondering why the hell anyone would bother writing a single binary using Apple's frameworks rather than using something like Go. In short, because you can make some _really_ awesome stuff. You can completely automate native macOS applications, right from the command-line, in a way that is delightful for users. And installation couldn't be more simple: just unarchive a single file into your `$PATH` and that's it.

I encourage you to take a minute to [watch this video](https://emporter.app/video?id=cli) and see the `emporter` tool unlock the full power of _Emporter.app_ in just a few keystrokes.

# Writing your own CLI

Rather than getting into the nitty-gritty details here, check out [YDCommandKit](https://github.com/youngdynasty/YDCommandKit) on GitHub. I expect the project will continue to evolve (a full wiki is coming soon).

Here's how it'll help you write your own CLI:

- It's fully self-contained (no dependencies, embeddable)
- Arguments/options are parsed in an expressive, type-safe way
- Color output is fully supported
- Tabbed output is well-aligned (tables)
- Commands can be synthesized to create subcommands
- Implementions are easily tested
- Code is well-documented (interfaces with Xcode Quick Help)

Also, there's a killer open source example of it being used: `emporter` is also on [GitHub](https://github.com/youngdynasty/emporter-cli).

Enjoy!
