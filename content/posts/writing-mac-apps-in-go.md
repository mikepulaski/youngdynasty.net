---
title: "Writing Apps in Go and Swift"
date: 2019-01-29T20:05:45+01:00
author: Mikey
shortSummary: A guide for wrapping Go code in Swift for use within a native macOS or iOS application.
---

Go makes it easy to create safe, reliable and efficient software. Concurrency is part of the language, making otherwise complicated code more intuitive to write. It can compile binaries for any non-obscure platform and has a quite capable standard library with a lively developer community.

Although Swift is cross platform, it's perhaps most commonly used to develop apps for Apple's platforms. Maybe I'm just not very clever, but even after years of using [Grand Central Dispatch](https://en.wikipedia.org/wiki/Grand_Central_Dispatch) ("GCD"), I still find it hard to write maintainable multi-threaded code[^1] for macOS or iOS. Although GCD offers a great improvement over how asynchronous code was written before Snow Leopard,[^2] I couldn't help but wonder what it would be like if I could focus on creating and designing APIs without having to worry about the minutiae of parallelism (threads, semaphores, locks, barriers, etc.).

[^1]: The subtleties required to implement coordination between routines and access to shared variables, especially after periods of inactivity in the codebase, is hard.
[^2]: Back in my day, we called macOS "OS X". And we managed `NSThread` and `NSRunLoop` instances ourselves. Get off my lawn! 👴

All that to say, when I discovered a straight-forward and performant way to call Go code from Swift, it felt like I unlocked new developer super-powers!

As a demonstration, let's build a library to escape/unescape HTML tags in Go and call it from Swift. This technique should work regardless of the platform (iOS, macOS, Linux, ...), but for simplicity, this post will target macOS.

If you're curious to see an example of such a hybrid app, check out [Emporter](https://emporter.app) on the [Mac App Store](https://itunes.apple.com/us/app/emporter/id1406832001?mt=12&ls=1).

_There's a complementary project hosted on [GitHub](https://github.com/youngdynasty/go-swift) if you're a "hands on" learner._

## [Writing a Go library](#go) {#go}

### Background

It's a pretty well-known feature that Go can call C code, but since Go 1.5, it's also possible to call Go code from C. The `go build` command has a `buildmode` flag to indicate what type of object should be built.

From `go help buildmode`:

```text
-buildmode=c-archive
   Build the listed main package, plus all packages it imports,
   into a C archive file. The only callable symbols will be those
   functions exported using a cgo //export comment. Requires
   exactly one main package to be listed.
```

So what does this mean exactly? Well, if we can compile Go to C, and embed C libraries in our Mac app... well, I think we just found our golden ticket!

### [Write a C archive](#go-archive) {#go-archive}

To write a C library in Go, we need to use cgo, the bridge between C and Go. For now, it's enough just to know that the C package can convert Go values to and from C types, and vice-versa. If you want to dive-in a little deeper, the Go authors have written an excellent post about cgo on the [Go Blog](https://blog.golang.org/c-go-cgo).

As mentioned previously, to build a C archive, we need to create a main package and mark each method we want to export with a preceding `//export` cgo comment.

The entire library would look something like this:

```go
package main

import (
	"C"
	"html"
)

//export escape_html
func escape_html(input *C.char) *C.char {
	s := html.EscapeString(C.GoString(input))
	return C.CString(s)
}

//export unescape_html
func unescape_html(input *C.char) *C.char {
	s := html.UnescapeString(C.GoString(input))
	return C.CString(s)
}

// We need an entry point; it's ok for this to be empty
func main() {}
```

Notice that we also had to convert between C and Go strings using cgo, and only exposed C types in the method signatures.

### [Compile the archive](#go-compile) {#go-compile}

Assuming you're in the same directory as the Go source, the library can be compiled using the following command:

```bash
go build --buildmode=c-archive -o libhtmlescaper.a
```

We've specified an explicit name and extension to use for our library, which helps makes it a little easier to bundle for use in Xcode. The build will also output a generated header[^3] `libhtmlescaper.h` which exposes all of the exported functions / types available when linking the archive.

[^3]: The generated header is not very easy to read. In real projects, I tend to write my own headers for well-documented code.

## [Calling Go from Swift](#swift) {#swift}

### [Create a module map](#swift-module-map) {#swift-module-map}

The easiest way to use our compiled library from Swift is to create a [module map](https://clang.llvm.org/docs/Modules.html#id21). Once setup correctly (which honestly, can be painful), our library will be automatically linked, with its headers included, when imported.

Here's what part of our `module.modulemap` might look like:

```swift
module HTMLEscaper {
    header "libhtmlescaper.h"
    link "htmlescaper"
    export *
}
```

If you don't already have module maps setup for your project, you should save your module map in your Xcode project's `$(SRCROOT)` (the same directory as your `.xcodeproj` file). Afterwards, you'll need to update your target's build settings: set `LIBRARY_SEARCH_PATHS` and `SWIFT_INCLUDE_PATHS` to `$(SRCROOT)`.

I'll admit, there can be little bit of friction here, but no more than if you were to use other third-party libraries in Swift.

### [Create a wrapper](#swift-wrapper) {#swift-wrapper}

If we've setup our module correctly and Xcode is on its best behavior, all we need to do is import it.

Here's what it might look like if we wrote a `String` extension to escapes HTML using our library:

```swift
import HTMLEscaper

extension String {
    public func escapedHTMLString() -> String? {
        return self.withCString() {
            guard let v = escape_html(UnsafeMutablePointer(mutating: $0)) else { return nil }
            return String(bytesNoCopy: v, length: strlen(v), encoding: .utf8, freeWhenDone: true)
        }
    }

    public func unescapedHTMLString() -> String? {
        return self.withCString() {
            guard let v = unescape_html(UnsafeMutablePointer(mutating: $0)) else { return nil }
            return String(bytesNoCopy: v, length: strlen(v), encoding: .utf8, freeWhenDone: true)
        }
    }
}
```

And that's it! Our Go library is now just an implementation detail, and the Swift API feels right at home.

## [Was that really worth it?](#value) {#value}

Really, it depends on your project.

For [Emporter](https://emporter.app), its backend services are written in Go. By writing the client in Go, I have an easy way to run tests, without mocks, instantaneously. I seriously can't imagine having written it differently as a one-person project, based on the amount of time I've saved by keeping all of the networking code in a single repo (then exporting the client as a C library).

And if I ever grow enough to hire, expand to a different platform, or license the service, I'm ready: its core can be developed independently and works cross-platform.

Give [Emporter](https://emporter.app) a try and let me know how it compares to an Electron app. 😉

## [Conclusion](#conclusion) {#conclusion}

In this article, we've written a simple Go library which was embedded in a native Mac app. Although we've focused on macOS, this technique will work for any platform that Go supports with C bindings.

You can download an example project on [GitHub](https://github.com/youngdynasty/go-swift).
