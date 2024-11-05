# Options and Nullables

In keeping with uniffi guidelines, we have made an effort to map core Rust concepts into their Typescript equivalents wherever possible, in order to allow the Typescript code to be as idiomatic and easy to work with as possible. A returned `Result<T, E>` from Rust will result in a flat type of `T` or a thrown `E`, while an `Option<T>` will become `T | undefined`. We believed that flattened types like this would be easier to work with than wrappers at every point for such common Rust primitives. This is in keeping with the approach taken by the core uniffi team for other languages (Kotlin turns `Option<T>` into `T`?).

Note that this flattening does mean certain types which are perfectly legal (if ill advised) in Rust are not representable on the Uniffi layer. An `Option<Option<T>>` for example, could be represented in Rust, though we would assert it may be a poor stylistic choice even there. If you need to represent a tri-state, an enum with three variants feels like a clearer choice, and one that has first class support. We also note that the core uniffi project shares these limitations in some of its bindings (Kotlin), and it has not proven overly burdensome to date.

## undefined vs null
Typescript of course has two alternatives for 'absent' values, `undefinded` and `null`. Rust on the other hand has only one (Option). Deciding whether we should represent Options as either undefined or null was ultimately a choice made during development of this library. 

We settled on `undefined` largely due to the Typescript language guidelines. The `undefined` keyword has better language level support in Typescript, and [Microsofts own guidelines](https://github.com/microsoft/TypeScript/wiki/Coding-guidelines#null-and-undefined) forbid the use of `null` in favor of `undefined` throughout their own projects. Moving away from `null` seems to the the direction the language is going, and we have chosen to follow suit.

While it is true that using both `null` and `undefined` lets you represent some unique ideas, such as a directive to clear a field (`null`) vs take no action on a field (`undefined`), those types would be ultimately unrepresentable in idiomatic Rust.