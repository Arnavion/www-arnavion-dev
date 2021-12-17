---
title: '2021-08-07 Intro to Zig for Rust users'
date: '2021-12-24T00:00:00Z'
---

I've been using Rust since 2016 and really like what it brings over C++. Over the years I also heard about [Zig,](https://ziglang.org/) which is described as being equally revolutionary over C. This year I came across a bunch of software using Zig that was reasonably complex as opposed to just toys and experiments; a particular example is the Wayland compositor [river.](https://github.com/riverwm/river) So I decided to learn it myself, and [Advent of Code 2021](https://adventofcode.com/2021/) was a great opportunity to do just that.

At this point, I believe I've learned enough about it that I can talk about it, specifically what it brings to the table compared to Rust for anyone who wants to write new software.

Keep in mind that, as of this writing, Zig is still pre-1.0 and openly unstable. Breaking changes happen all the time, you're expected to use `master` instead of a release, the compiler has bugs, the standard library has bugs and is incomplete, et cetera et cetera.

Before I start, I should link to a few resources that also act as intros to Zig:

- [The Zig language reference](https://ziglang.org/documentation/master/)

- [ziglearn.org - an intro tutorial](https://ziglearn.org/)

- [ziglings - tiny fill-in-the-blanks exercises](https://github.com/ratfactor/ziglings/)

- [Why Zig?](https://ziglang.org/learn/why_zig_rust_d_cpp/)

However, I don't think these are suitable for someone who wants to get an overview of Zig programming in general. The language reference is an unsorted dump of everything about the language (as it should be). ziglearn also just dumps syntax on you instead of walking you through a program. ziglings walks you through individual features but very slowly. The "Why Zig?" article just makes broad strokes without any detail.


# (TODO: Sections)

Zig is like C, but with syntax that is closer to Rust, and concepts that are surprisingly similar to JavaScript. Let's look at an example program. I've annotated each line with comments to explain it.

```zig
// src/main.zig

// Importing a library, zig's libstd in this case,
// uses `const <binding> = @import(<string literal name of the library>);`
// This is similar to how modules were imported in JavaScript before ES2015,
// namely `const <binding> = require(<string literal name of the library>);`
const std = @import("std");

// Just like libraries, sub modules of the same library are also imported
// with the same syntax, but with a filename.
//
// Note that zig does not have any concept of a module hierarchy.
// The compiler is given one entrypoint to compile, and it'll recursively
// include any `@import`'d files, but there is no super- or sub- relationship
// between them.
//
// One *can* construct a hierarchy manually by controlling what the root exports.
// I'll go into more details later.
const sub_module = @import("sub_module.zig");

// The entrypoint of the program. This is similar to Rust's syntax for
// function declarations.
//
// The return type is similar in spirit to
// `Result<(), Box<dyn std::error::Error>>`, but I'll go into more details
// of Zig's version of `Result` and errors later.
pub fn main() anyerror!void {
    // Allocations are explicit in Zig. There is no default "global allocator"
    // as in Rust, even when using the standard library.
    //
    // This line is creating an instance of the GeneralPurposeAllocator type.
    // Yes, it looks like invoking a function named GeneralPurposeAllocator instead,
    // with a weird `.{}` parameter and a weird `{}` afterwards. I'll explain later.
    var allocator = std.heap.GeneralPurposeAllocator(.{}){};

    // Zig does not have destructors, ie no equivalent of `std::ops::Drop`.
    // Types that need cleaning up provide a function conventionally named `deinit`,
    // and the caller is expected to call this when it's done with the value.
    // To make this easy for callers, arbitrary code can be scheduled to run
    // when a scope is exited by putting it in a `defer` block.
    //
    // GeneralPurposeAllocator is one of a few allocators that zig's libstd
    // comes with. It tracks allocs and frees, and its `deinit` function
    // returns a bool indicating whether a leak happened or not.
    defer {
        const leaked = allocator.deinit();
        if (leaked) {
            // Functions starting with `@` are compiler built-ins, similar to
            // `std::intrinsics` in Rust. Unlike Rust's instrinsics, these built-ins
            // are not inherently unstable with stable counterparts elsewhere.
            //
            // This particular intrinsic aborts the program with a panic message,
            // similar to the `panic!()` macro.
            @panic("memory leaked");
        }
    }

    const stdout = std.io.getStdOut().writer();

    // The `allocator` value above is of type `GeneralPurposeAllocator`
    // However code that allocates does not need to know that; it can use
    // any kind of allocator as long as that allocator implements the same "interface".
    // In Zig, that interface is represented by the struct `std.mem.Allocator`,
    // which contains functions for alloc, free, etc based on a vtable.
    //
    // Strongly typed allocators like `GeneralPurposeAllocator` generally provide
    // a function named `allocator` to create a `std.mem.Allocator` from themselves.
    //
    // The call to `sub_module.do_something` is prefixed with `try`. This is similar to
    // Rust's `?` operator, in that it returns the error from `sub_module.doSomething`
    // if there is one, otherwise evaluates to the non-error value.
    try sub_module.doSomething(allocator.allocator(), stdout);
}

// Define unit tests for this file. This is a special DSL as opposed to Rust's
// function annotated with `#[test]` approach. In particular, there's no need
// to contort the test description into a function name since it can be
// an arbitrary string literal. The block is allowed to use `try` to
// bubble up errors.
test "sub-tests" {
    // This file doesn't have any tests of its own, but it needs to tell
    // the compiler to run tests in submodules. This boiler-plate is required
    // for that.
    //
    // `@This()` here is another built-in. In this particular case,
    // it refers to the current module, ie `main.zig`. I'll talk more about it
    // later.
    std.testing.refAllDecls(@This());
}
```

```zig
// src/sub_module.zig

const std = @import("std");

// An exported function from this submodule.
//
// The return type here is similar in spirit to
// `Result<(), impl std::error::Error>`, but again I'll go into more details
// of Zig's version of `Result` and errors later.
//
// `stdout` here is of type `anytype`. For now, think of it as
// `impl std::any::Any`. I'll explain later.
pub fn doSomething(allocator: std.mem.Allocator, stdout: anytype) !void {
    // Use the allocator to allocate a slice of 10 u32's.
    // `allocated_slice` is of type `[]u32`. This is similar to Rust's `&mut [u32]`
    // Note that Zig's `[]T` is mutable by default; immutable slices are `[]const T`.
    // Also note that Zig slices do not have a leading `&` to indicate
    // that they're references; slice types are inherently references.
    const allocated_slice = try allocator.alloc(u32, 10);

    // Queue the slice to be freed when the current scope ends,
    // ie when the function returns.
    defer allocator.free(allocated_slice);

    // Fill the whole allocated slice with the u32 value 5.
    //
    // `u32`, a type, is being passed as a parameter to `std.mem.set`.
    // In Rust this would look like `std::mem::set::<u32>(allocated_slice, 5)`
    // I'll talk about types as function parameters later.
    std.mem.set(u32, allocated_slice, 5);

    // `sumSlice` (defined below) also takes a type as a function parameter.
    // Here, the type parameter is being specified via the `@TypeOf` built-in,
    // which takes an arbitrary expression and returns the type of that expression.
    // In this case, it's `u32`.
    const sum = sumSlice(@TypeOf(allocated_slice[0]), allocated_slice);

    // Just like Rust, writing to a "writer" is fallible and requires `try`.
    // The parameters are also a format string and the values to be formatted,
    // though they're being passed in a `.{}` wrapper. This wrapper is a tuple,
    // so this whole line in Rust would look like `stdout.print("sum: {}\n", (sum,))?;`
    //
    // Note that, while this is a function, the format string is nevertheless parsed
    // at compile time, just like in Rust's format macros. This is because of how
    // the format string parameter is `comptime`. I will talk about it later.
    try stdout.print("sum: {}\n", .{ sum });

    // This is similar to Rust's `debug_assert!()` macro, except it's a function.
    std.debug.assert(sum == 50);
}

// This is a non-exported function, and is thus only visible in this module.
//
// The first parameter `T` has the type `type`, which is why
// it can be set to a type like `u32`.
//
// The second parameter `slice` has the type `[]const T`, which is
// a slice of constant values, each of the type specified in
// the first parameter. Since `T` is `u32`, this parameter is a `[]const u32`.
//
// Note that we called this function with `allocated_slice` that was a `[]u32`.
// Zig transparently converted the mutable `[]u32` to immutable `[]const u32`.
//
// Lastly, the function returns a value of the same type specified `T`.
//
// In Rust, this would've been `fn sumSlice<T>(slice: &[T]) -> T`
// Actually, the Rust version would also require bounds on `T`,
// but I'll talk about that later.
fn sumSlice(comptime T: type, slice: []const T) T {
    // Create a mutable binding of the type specified by `T` and initialize it
    // to `0`.
    var result: T = 0;

    // Zig's `for` loops only take a single parameter, and that parameter
    // must be a slice. After the parameter, one can write a body that looks
    // like a Rust closure, in that it has two parameters and a body.
    // For `for` loops, the first parameter is the slice element and the second
    // is the iteration index.
    //
    // In Rust, this would've looked like
    //
    //    for (i, &n) in slice.iter().enumerate() {
    //
    // Not every `for` loop needs to capture both parameters. If the loop body
    // didn't need the iteration index, it could've just been written as
    // `for (slice) |n| {`
    //
    // Notice that `n` is a `u32`, not a `&u32` (or `*const u32` in Zig).
    // This only works in Rust if the slice element is `Copy`.
    // In Zig, as in C, all types are `Copy`. Also note that `n` is immutable,
    // even if iterating over a `[]mut u32`. So if one were to write this Rust code
    // in Zig:
    //
    //    let slice: &mut [u32] = ...;
    //    for n in slice.iter_mut() {
    //        *n += 1;
    //    }
    //
    // ... it would require capturing `n` as a reference:
    //
    //    const slice: []u32 = ...;
    //    for (slice) |*n| {
    //        n.* += 1;
    //    }
    for (slice) |n, i| {
        result += n;

        // Just like Rust's `eprintln!()` macro, this is a function for printing
        // to stderr without needing an explicit writer.
        //
        // Just like `stdout.print`, this takes a format string and a tuple
        // of values to be formatted.
        std.debug.print("processed element {} at index {}\n", .{ n, i });
    }

    // Return the result. Unlike Rust, blocks are not expressions that evaluate
    // to the value of the last expression. An explicit `return` is needed to
    // return a value from a function.
    return result;
}

// Define a unit test for this file.
test "sub_module.do_something works" {
    // We want to test `do_something`, for which we need a slice.
    // Rather than allocate a slice, we can use a local array as the storage.
    //
    // This creates an array of u32 elements of inferred length. In Rust,
    // this would've been `let arr: [u32; 3] = [3, 4, 5];` or
    // `let arr = [3_u32, 4, 5];`
    const arr = [_]u32{ 3, 4, 5 };

    // Call `sumSlice`. The first parameter, the slice element type,
    // can again be derived using `@TypeOf`. The second parameter, the slice,
    // can be created by indexing the array with a range.
    //
    // Zig allows ranges to leave off the end but not the start,
    // so the range needs to be `0..` instead of Rust's `..`.
    // Also, note that there is no `&`; as mentioned above a slice is
    // inherently a pointer.
    const result = sumSlice(@TypeOf(arr[0]), arr[0..]);

    // Tests are expected to use the `std.testing.expect*` functions
    // for assertions. These functions return an error if the assertion fails.
    // As mentioned above, test blocks are allowed to bubble up errors,
    // so the `expectEqual` function is used with `try`.
    try std.testing.expectEqual(12, result);
}
```

You've probably spotted the major themes around Zig's syntax and philosophy. The word that comes to my mind is "unification".

Why have separate syntax for defining a module vs importing it into scope? Why `mod` and `use` ? Just use `@import` and let the compiler keep track of whether it has seen a that module before or not.

Why have separate syntax for passing in types vs passing in values? Why `fn foo<T>(t: T)` ? Just pass in types as parameters like `fn foo(T: type, t: T)`.

Another case is with enums and unions. In Rust, we have:

<table>
<thead>
<tr>
<th>Enum</th>
<th>Union</th>
</tr>
</thead>
<tbody>
<tr>
<td>
```rust
enum Foo {
    Bar(u64),
    Baz(Baz),
}

struct Baz { ... }

let foo: Foo = ...;
match foo {
    Foo::Bar(bar) => dbg!(bar),
    Foo::Baz(baz) => dbg!(baz),
}
```
</td>
<td>
```rust
#[repr(C)]
union Foo {
    bar: u64,
    baz: Baz,
}

#[repr(C)]
struct Baz { ... }

let foo: Foo = ...;
if foo_is_bar {
    dbg!(foo.bar);
}
else {
    dbg!(foo.baz);
}
```
</td>
</tr>
</tbody>
</table>

`enum`s are (or rather, act like, but let's ignore that here) tagged unions, and accessing the correct variant is type-safe. `union`s are untagged and accessing the correct tag is not type-safe, and they're only meant to be used for C FFI.

In Zig, both cases are handled by unions:

<table>
<thead>
<tr>
<th>Enum</th>
<th>Union</th>
</tr>
</thead>
<tbody>
<tr>
<td>
```zig
const Foo = union(enum) {
    bar: u64,
    baz: Baz,
};

const Baz = struct { ... };

const foo: Foo = ...;
switch (foo) {
    .bar => |bar| std.debug.print(
        "bar: {}\n", .{ bar },
    ),
    .baz => |baz| std.debug.print(
        "baz: {}\n", .{ baz },
    ),
}
```
</td>
<td>
```zig
const Foo = union {
    bar: u64,
    baz: Baz,
};

const Baz = struct { ... };

if (foo_is_bar) {
    std.debug.print(
        "foo.bar: {}\n", .{ foo.bar },
    );
}
else {
    std.debug.print(
        "foo.baz: {}\n", .{ foo.baz },
    );
}
```
</td>
</tr>
</tbody>
</table>

After all, if the only difference between the two is the tagging, the only difference between the syntax should be to indicate the tagging. So in Zig, you tell the compiler to generate the automatic tag by writing one extra `(enum)` in the union declaration, and this enables the union to now be used with `switch` for type-safe matching.

Also, you might've spotted it in the above example, but types are also declared with `const <binding> = <type>;`. Types can also be renamed with `const`. Why have separate syntax for declaring variables vs declaring types?

<table>
<thead>
<tr>
<th></th>
<th>Rust</th>
<th>Zig</th>
</tr>
</thead>
<tbody>
<tr>
<td>Variable</td>
<td>
```rust
let foo = 5;
```
</td>
<td>
```zig
const foo = 5;
```
</td>
</tr>
<tr>
<td>Declare type</td>
<td>
```rust
struct Foo { ... }
enum Bar { ... }
```
</td>
<td>
```zig
const Foo = struct { ... };
const Bar = enum { ... };
```
</td>
</tr>
<tr>
<td>Import type</td>
<td>
```rust
use arrayvec::ArrayVec;
```
</td>
<td>
```zig
const ArrayList = std.ArrayList;
```
</td>
</tr>
<tr>
<td>Import type with rename</td>
<td>
```rust
use arrayvec::ArrayVec as AV;
```
</td>
<td>
```zig
const AL = std.ArrayList;
```
</td>
</tr>
<tr>
<td>Alias type with parameters</td>
<td>
```rust
type Numbers = ArrayVec<u32, 10>;
```
</td>
<td>
```zig
const Numbers = ArrayList(u32, 10);
```
</td>
</tr>
</tbody>
</table>

---

TODO:

- Elaborate on GPA's `.{}` inline instead of "later". "GPA takes a config, and the config has defaults for all fields which we want, so we pass in an anonymous struct literal with no fields overridden."

- Only loops are `for` loops and `while` loops. `loop` is `while (true)`, and the compiler understands that this is an infinite loop for when a function only returns from within the loop. `for` loops are only over slices; `ArrayList` needs `for (al.items)`, `BoundedArray` needs `for (al.constSlice())` etc. `while` loops can have post-condition. Indexed loop over non-slice requires `var i: usize = 0; while (i < end) : (i += 1) { ... }`

- Statements are not expressions. Blocks require label and `break`: `const foo = block: { ...; break :block ...; }`. `if` expressions require `@as()` when evaluating to `comptime_int` (`if cond 1 else 0` -> `error: cond is not comptime`) because of `comptime` inference, but this may be fixed eventually (link to GH issue).

- Errors are only integers, no data. Error sets. `anyerror`.

- Result is `E!T` instead of being a generic type. `try` `catch` is built-in syntax instead of combinators.

- Option is `?T` instead of being a generic type. `orelse` is built-in syntax instead of combinators.

- Special-casing of Result and Option. Pros: Most code doesn't need anything else anyway, so why not have simple syntax for annotating and returning them. `result catch |err| { ... }` (`match result { Err(err) => { ... } }`), `result catch unreachable` (`result.unwrap()`), `result catch null` (`result.ok()`), `option orelse 5` (`.unwrap_or(5)`), `option orelse return error.InvalidInput` (`option.ok_or_else(|| Error::InvalidInput)?`) are all examples of syntax unification. Bonus is no closure means flow control keywords automatically work. Cons: Special-casing wrappers means wrappers don't wrap generally, eg `??` isn't a thing (link to GH issue); `.{}` can't be used (link to GH issues).

- No inline fns or closures. `const impl = struct { fn inner() { ... } }; impl.inner` hack for inline fns. Eg consequence of no closures: sort and search require `context: anytype` parameter.

- `comptime` - powerful, unified syntax vs Rust macros. Able to pass in both types and values, ala C++ templates, as opposed to Rust where values are being bolted on on top with significant effort (const generics). The input is (AST and type info in std.meta, similar to `syn`), the output is also type-safe (std.meta again, unlike `quote!{}`), and the code has type information available (Rust macros only have AST). Cons: no inference except with `@TypeOf()` when possible, requires passing in parameters othewise.

- `anytype` - special case of inference.

- Specific result of `comptime`: Type constructors are functions that return types, not types. Nice bit of FP there. Hence why GPA in example was a function. It's also why some functions are in PascalCase and others in camelCase; just like types are in PascalCase, type constructors are also in PascalCase. Other examples: `std.math.IntFittingRange(comptime from: comptime_int, comptime to: comptime_int) type` computes the smallest integer type that can hold integers between low and high (inclusive).

- Related to `std.math.IntFittingRange` - Zig integers i# and u# can have any value of # between 0 and 65535 (though I had compiler crashes involving LLVM for # > 64). These also work with exhaustiveness in `switch`, eg `let bit: u1 = ...; switch (bit) { 0 => { ... }, 1 => { ... } }` is exhaustive.

- Another example, reading binary data. `std.meta.Int` is a function that takes signedness and number of bits as parameters, and returns the integer type of those specifications.

  ```zig
  fn readNum(comptime num_bits: comptime_int, reader: Reader) std.meta.Int(.unsigned, num_bits) {
      var result: std.meta.Int(.unsigned, num_bits) = 0;

      var i: usize = 0;
      while (i < num_bits) : (i += 1) {
          result = (result << 1) | reader.readBit();
      }

      return result;
  }

  // `version` is a `u3`
  const version = readNum(3, reader);
  ```

  In Rust, assuming that there were more unsigned integer types just like Zig, `readNum` would have to be a function-style proc macro. The macro would parse its args manually as `syn::LitInt` and `syn::Expr`, construct a `syn::Ident` for the integer type by stringifying the `LitInt`, and emit one giant `quote!{}`'d blob that contains the function body. There would be no way of knowing what it expands to without reading its code, since its signature would just be `TokenStream -> TokenStream` without any indication of what parameters it takes and what it returns. It would also need to be in a wholly separate crate. Lastly, Zig's version allows the `3` to be computed via an arbitrary `comptime` expression, but the Rust proc macro could not support anything more than a literal.

  Using const generics, a method similar to C++ `type_traits` could be done to associate every integer literal with the corresponding `u` type.

  ```rust
  trait TypeFromNumBits {
      type Ty:
          std::ops::Shl<u8, Output = Self::Ty> +
          std::ops::BitOr<u1, Output = Self::Ty> +
          num_traits::Zero;
  }
  struct TypeFromNumBitsImpl<const N: usize>;
  impl TypeFromNumBits for TypeFromNumBitsImpl<0> { type Ty = u0; }
  impl TypeFromNumBits for TypeFromNumBitsImpl<1> { type Ty = u1; }
  impl TypeFromNumBits for TypeFromNumBitsImpl<2> { type Ty = u2; }
  // 65533 more impls...

  fn read_num<const NumBits: usize>(reader: &mut Reader) ->
      <TypeFromNumBitsImpl<NumBits> as TypeFromNumBits>::Ty
  where
      TypeFromNumBitsImpl<NumBits>: TypeFromNumBits,
  {
      let mut result = num_traits::Zero::zero();
      for _ in 0..NumBits {
          result = (result << 1) | reader.read_bit();
      }
      result
  }
  ```

  ... but still, this solution requires a bespoke trait, struct and 65536 impls for parity with one single function (`std.meta.Int`) in Zig.

- Unused code triggers syntax errors but not type errors. Only used code triggers type errors.

- No traits, so no bounds / concepts.

- Implementation of `comptime` means functions are monomorphized on demand. Combined with previous two points, that means "generic" code only triggers type errors when monomorphized and a particular *syntactic* use of a type does not work. `sliceSum` is valid even though we didn't add a `CanBeInitializedToZero` bound or `CanBeAddedWithPlus` bound; it'll only complain if we call it with a `T` that doesn't support those. Same for `readNum` above. Effectively all generic code is duck-typed, ala C++.

- `defer` - Better than goto, but scope-based instead of value-based means anti-encapsulation. `errdefer` - cleanup of resources on error that would've been returned in case of success. Also, "Zig already has RAII" my ass, aka one of andrewrk's weird definitions.

- No shadowing, because of usual "once a variable is defined I don't need to read code in between to have it magically become different" bogus arguement. Even without redefinition you still have to worry about mutation. Sure if it's const you don't, but if you needed to create it you'd have to make it var, and ironically the lack of shadowing means you can't shadow the var with a const after the creation is finished. Have to resort to blocks for that. I ended up with `foo_`, `foo__` as workaround.


# Summary

- Don't think zig will ever be as good as Rust at borrow checking without a borrow checker. Runtime lints can only go as far as your tests. Community is weirdly defensive about their runtime lints. I myself forgot to `errdefer list.deinit();` a lot, and didn't notice for a long time because I never failed. ReleaseFast is recommended a lot even though everything becomes UB. But also seems to not be required, everything I wrote was already fast in ReleaseSafe and ReleaseFast didn't improve much.

- Explicit allocation is the one thing Rust should've had from day 1, and it's too late to retrofit easily now. `<A>` splitting the ecosystem is proof.

- Syntax unification is an interesting concept, but limitations of having to pass in each type parameter "twice" is annoying. Unclear why some parts of libstd use `@TypeOf` inference but most parts don't. Escape hatch of `anytype` is tempting but duck-typing is not good either.

- Young language. Even naming convention is in flux (ref: recent IRC convo between andrewrk and ifreund about changing functions from camelCase to snake_case). andrewrk hangs out in IRC channel and provides answers/feedback. Relatively chill about adding libstd features; most of those PRs are delegated (eg my BA.insert PR was handled only by BA author; even BA itself was merged by BA author without andrewrk's approval; check if this is true in general?)

- But also opposition to adding language syntax features ([representative example](https://github.com/ziglang/zig/issues/3110#issuecomment-584424303)). [Passive-aggressive issue template](https://github.com/ziglang/zig/blob/master/.github/ISSUE_TEMPLATE/proposal.yml) prevented me from asking about `BA.insert` (template doesn't differentiate between syntax proposal and libstd proposal). Others?

- "Better C" philosophy holds up. If I had to choose between C / Zig / C++, I'd choose Zig. But if Rust was an option, I'd choose Rust. But ideal language is Rust with allocators from day 1. Syntax unification is nice to have but not requirement; never felt a need for it before, and still don't miss it now.
