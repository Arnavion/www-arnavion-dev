---
title: '2020-04-07 Rust: The unfortunate bits'
date: '2020-04-07T00:00:00Z'
---

This is an assortment of unfortunate, regrettable decisions made by the Rust standard library. They're all very minor, inconsequential things - gotchas that you notice the first time you hit them and then learn to live with them. So this article isn't meant to be a rant or anything of that sort. It's just a list that's been mulling in my mind for a long time that I decided to put to paper. I've also needed to reference these points when talking on IRC, so it'll be easier to just provide URLs.

I link to the libstd docs when relevant, but I assume basic Rust knowledge from the reader.

This list is neither objective nor complete. It's built from my own experience using Rust since 2016, as well as the discussions I've seen in its IRC channels involving experienced users and new users alike.

All of these things *could* be resolved in a Rust "2.0", ie a release that is allowed to make backward-incompatible changes from the current "1.x". I personally hope that such a release never happens, despite being the author of this list, because I don't know any backward-incompatible forks of languages that have gone well. The editions system that Rust has cannot be used to fix these, because every crate uses the same libstd regardless of what edition it has. Hypothetically, libstd could be made to appear differently to crates depending on what edition they're compiled for, but this is not a feature that exists today or may ever exist. It would also cause even greater havoc with macros than the 2015 -> 2018 edition transition did, because things like trait impls are program-global, not crate-scoped.


# Changing these would be backward-incompatible

- <a href="#iteratorext" id="iteratorext">`#iteratorext`</a> The [`Iterator`](https://doc.rust-lang.org/stable/std/iter/trait.Iterator.html){ rel=nofollow } trait is the largest trait in the standard library. It's so large because Rust has a lot of combinators defined for iterators, and they're all methods of this trait. At one point, the docs page of this trait would kill browsers because the page would attempt to expand all the impls of `Iterator` for the ~200 types in libstd that implement it, leading to an extremely long web page.

    In general, when a trait contains default methods, it's because it wants to give you the ability to override them. For example, [`Iterator::try_fold`](https://doc.rust-lang.org/stable/std/iter/trait.Iterator.html#method.try_fold){ rel=nofollow } and [`Iterator::nth`](https://doc.rust-lang.org/stable/std/iter/trait.Iterator.html#method.nth){ rel=nofollow } have default impls in terms of `Iterator::next`, but may be overridden if the type can impl more efficiently.

    However, the methods that return other iterators have return types that can only be instantiated by libstd, so it is not possible for a user impl to override them. For example, [`Iterator::map`](https://doc.rust-lang.org/stable/std/iter/trait.Iterator.html#method.map){ rel=nofollow } returns [`std::iter::Map<Self, F>`,](https://doc.rust-lang.org/stable/std/iter/struct.Map.html){ rel=nofollow } and this type is opaque outside libstd. Since it also references both `Self` and `F`, it is not even possible to return the result of invoking `Iterator::map` on any *other* iterator instead of `Self`, say if you wanted to delegate to an inner iterator's impl. The only possible way to implement this method is the implementation that is already in libstd.

    Outside of libstd, a common convention is to have two separate traits. There is one `trait Foo`, which contain methods that either must be implemented or could be useful to override. The other is `trait FooExt: Foo` with a blanket impl for all `T: Foo`, which contains extra methods that need not / should not / can not be overridden. For example, see [`futures::stream::Stream`](https://docs.rs/futures/0.3.4/futures/stream/trait.Stream.html){ rel=nofollow } and [`futures::stream::StreamExt`](https://docs.rs/futures/0.3.4/futures/stream/trait.StreamExt.html){ rel=nofollow } (a direct analogue to `Iterator`), or [`tokio::io::AsyncRead`](https://docs.rs/tokio/0.2.14/tokio/io/trait.AsyncRead.html){ rel=nofollow } and [`tokio::io::AsyncReadExt`](https://docs.rs/tokio/0.2.14/tokio/io/trait.AsyncReadExt.html){ rel=nofollow }

    Unfortunately it's too late to split `Iterator` into `IteratorExt` now, since moving methods out of it would be backward-incompatible.


- <a href="#cow" id="cow">`#cow`</a> The [`Cow`](https://doc.rust-lang.org/stable/std/borrow/enum.Cow.html){ rel=nofollow } type, as its documentation says, is a "clone-on-write" smart pointer. This type is an enum of `Borrowed(&B)` and `Owned(T)` variants, eg a `Cow<str>` can be either a `Borrowed(&str)` or an `Owned(String)`. I believe, based on the code I've written personally as well as my day job's codebase, that most of the uses of `Cow` are for the ability to hold either a borrow or an owned value. For example, consider code like this:

    ```rust
    fn get_by_id(id: Option<&str>) {
        let query = match id {
            Some(id) => format!("#{}", id),
            None => "*",
        };
        execute(&query); // execute only needs a &str
    }
    ```

    This won't compile because one of the `match` arms returns a `String` and the other a `&'static str`. One way to solve this would be to use `.to_owned()` on the `&'static str` to make it a `String` too, but this is a wasteful allocation since `execute` only needs a `&str` anyway. `Cow` is a better approach:

    ```rust
        let query: Cow<'static, str> = match id {
            Some(id) => format!("#{}", id).into(), // Creates a Cow::Owned(String)
            None => "*".into(),                    // Creates a Cow::Borrowed(&'static str)
        };
        execute(&query);
    ```

    But what exactly does "clone-on-write" mean anyway, given it was important enough to name the type after? The answer lies in one of the two methods that `Cow` impls:

    ```
    fn to_mut(&mut self) -> &mut B::Owned
    ```

    For example, if used on a `Cow::Borrowed(&str)`, this method will clone the `&str` into a `String`, change `self` to be a `Cow::Owned(String)` instead, and then return a `&mut String`. If it was already a `Cow::Owned(String)`, it just returns a `&mut String` from the same string. So it is indeed a "clone-on-write" operation.

    However, of all the times I've used `Cow`, I've used this method very rarely. Most of my uses have been to just store either a borrow or an owned value, as mentioned above. Occasionally I've used the other method that `Cow` impls, `fn into_owned(self) -> B::Owned`, but this is just "clone", not "clone-on-write", since it consumes the `Cow`.

    In fact, `Cow` does impl the standard [`Clone`](https://doc.rust-lang.org/stable/std/clone/trait.Clone.html){ rel=nofollow } and [`ToOwned`](https://doc.rust-lang.org/stable/std/borrow/trait.ToOwned.html){ rel=nofollow } traits (the latter via its blanket impl for all `T: Clone`). But `clone`ing or `to_owned`ing a `&Cow::<'a, B>::Borrowed(B)` gives another `Cow::<'a, B>::Borrowed(B)`, not a `Cow::<'static, B>::Owned(B::Owned)`. (It couldn't do that anyway, because `Clone::clone` must return `Self`, so the lifetimes need to match.) So `Cow` has two methods of cloning itself that are unlike the other two methods of cloning it has, and specifically the method named `to_owned` doesn't necessarily produce an `Owned` value.

    The end result is that new users trying to figure out how to store either a `&str` or a `String` don't realize that the type they're looking for is named `Cow`. And when they ask why it's named that, they learn that it's because, out of the many other ways it can be used, one specific one is "clone-on-write".

    It may have been a better state of affairs if it was called something else, like `MaybeOwned`. But it's too late now.


- <a href="#tryfrom-fromstr" id="tryfrom-fromstr">`#tryfrom-fromstr`</a> The [`TryFrom`](https://doc.rust-lang.org/stable/std/convert/trait.TryFrom.html){ rel=nofollow } and [`TryInto`](https://doc.rust-lang.org/stable/std/convert/trait.TryInto.html){ rel=nofollow } traits represent fallible conversions from one type to another. However these traits were only added in 1.34.0; before that fallible conversions were performed using ad-hoc methods. However, one special kind of fallible conversion was there since 1.0, represented by the [`FromStr` trait](https://doc.rust-lang.org/stable/std/str/trait.FromStr.html){ rel=nofollow } and [`str::parse` method](https://doc.rust-lang.org/stable/std/primitive.str.html#method.parse){ rel=nofollow } - that of fallible conversion between a type and a `str`

    Unfortunately, when the `TryFrom` trait was stabilized, a blanket impl for `T: FromStr` was not also added - it would've conflicted with the other blanket impl of `TryFrom` for all `T: From`. Therefore `FromStr` and `TryFrom` exist independently, and as a result libstd has two kinds of fallible conversions when the source is a `str`. Furthermore, none of the libstd types that impl `FromStr` also impl `TryFrom<&str>`, and in my experience third-party crates also follow this principle.

    As a result, one cannot write code that is generic on `TryFrom` and expect it to work automatically with types that only impl `FromStr`.


- <a href="#err-error" id="err-error">`#err-error`</a> Speaking of [`TryFrom`](https://doc.rust-lang.org/stable/std/convert/trait.TryFrom.html){ rel=nofollow } and [`FromStr`,](https://doc.rust-lang.org/stable/std/str/trait.FromStr.html){ rel=nofollow } the former names its assoc type `Error` even though the latter named its type `Err`. The initial implementation of `TryFrom` did use `Err` to be consistent with `FromStr`, but this was changed to `Error` before stabilization so as to not perpetuate the `Err` name in new code. Nevertheless, it remains an unfortunate inconsistency.


# These can't be changed, but they can be deprecated in favor of new alternatives

- <a href="#result-option-intoiterator" id="result-option-intoiterator">`#result-option-intoiterator`</a> The [`Result`](https://doc.rust-lang.org/stable/std/result/enum.Result.html){ rel=nofollow } type impls [`IntoIterator`](https://doc.rust-lang.org/stable/std/iter/trait.IntoIterator.html){ rel=nofollow }, ie it's convertible to an `Iterator` that yields zero or one elements (if it was `Err` or `Ok` respectively). Functional language users will find this familiar, since `Either` being convertible to a sequence of zero (`Left`) or one (`Right`) elements is common in those languages. The problem with Rust's approach is that the `IntoIterator` trait is implicitly used by for-loops.

    Let's say you want to enumerate the entries of the `/` directory. You might start with this:

    ```rust
    for entry in std::fs::read_dir("/") {
        println!("found {:?}", entry);
    }
    ```

    But rather than printing the contents of `/`, this will print just one line that reads `found ReadDir("/")`. `ReadDir` here refers to `std::fs::ReadDir`, which is the iterator of directory entries returned by `std::fs::read_dir`. But why is the loop variable `entry` receiving the whole iterator instead of the elements of the iterator? The reason is that `read_dir` actually returns a `Result<std::fs::ReadDir, std::io::Error>`, so the loop actually needs to be written like `for entry in std::fs::read_dir("/")? {`; notice the `?` at the end.

    Of course, this only happens to compile because `println!("{:?}")` is an operation that can be done on both `Result<ReadDir>` and `Result<DirEntry>`. Other things that could successfully compile are serialization, and converting to `std::any::Any` trait objects. Otherwise, if you actually tried to use `entry` like a `Result<DirEntry>`, you would likely get compiler errors, which would at least prevent bad programs though they might still be confusing.

    This problem wouldn't have happened if `Result` had a dedicated function to convert to an `Iterator` instead of implementing `IntoIterator`. It could be solved by adding this new function and deprecating the existing `IntoIterator` impl, though at this point the compiler does not support deprecating trait impls.

    The [`Option`](https://doc.rust-lang.org/stable/std/option/enum.Option.html){ rel=nofollow } type also has the same problem since it also impls [`IntoIterator`](https://doc.rust-lang.org/stable/std/iter/trait.IntoIterator.html){ rel=nofollow }, ie it's convertible to an `Iterator` that yields zero or one elements (if it was `None` or `Some` respectively). Again, this mimics functional languages where `Option` / `Maybe` are convertible to a sequence of zero or one elements. But again, the implicit use of `IntoIterator` with for-loops in Rust leads to problems with code like this:

    ```rust
    let map: HashMap<Foo, Vec<Bar>> = ...;
    let values = map.get(&some_key);
    for value in values {
        println!("{:?}", value);
    }
    ```

    The intent of this code is to print every `Bar` in the map corresponding to the key `some_key`. Unfortunately `map.get` returns not a `&Vec<Bar>` but an `Option<&Vec<Bar>>`, which means `value` inside the loop is actually a `&Vec<Bar>`. As a result, it prints all the `Bar`s in a single line like a slice instead of one `Bar` per line.

    This problem wouldn't have happened if `Option` had a dedicated function to convert to an `Iterator` instead of implementing `IntoIterator`.

    At least clippy has [a lint for this.](https://rust-lang.github.io/rust-clippy/master/index.html#for_loops_over_fallibles){ rel=nofollow }


- <a href="#insert-unit" id="insert-unit">`#insert-unit`</a> All the libstd collection methods that insert elements into the collection return `()` or some other value that is unrelated to the element that was just inserted. This means if you write code that inserts the value and then wants to do something with the inserted value, you have to do a separate lookup to get the value you just inserted. For example:

    ```rust
    // Inserts a new String into the given Vec, and returns a borrow of the newly-inserted value.
    fn foo(v: &mut Vec<String>) -> &str {
        let new_element = bar();
        v.push(new_element);

        // This is accessing the element that was just inserted, so there's no way this could fail.
        //
        // But still, to satisfy the typesystem, one must write .unwrap().
        // The compiler is also not smart enough to detect that `last()` can ever return `None`,
        // so it will still emit the panic machinery for this unreachable case.
        let new_element = v.last().unwrap();

        &**new_element
    }
    ```

    The same issue exists with [`BTreeMap::insert`,](https://doc.rust-lang.org/stable/std/collections/struct.BTreeMap.html#method.insert){ rel=nofollow } [`BTreeSet::insert`,](https://doc.rust-lang.org/stable/std/collections/struct.BTreeSet.html#method.insert){ rel=nofollow } [`HashMap::insert`,](https://doc.rust-lang.org/stable/std/collections/struct.HashMap.html#method.insert){ rel=nofollow }[`HashSet::insert`,](https://doc.rust-lang.org/stable/std/collections/struct.HashSet.html#method.insert){ rel=nofollow } [`VecDeque::push_back`,](https://doc.rust-lang.org/stable/std/collections/struct.VecDeque.html#method.push_back){ rel=nofollow } and [`VecDeque::push_front`.](https://doc.rust-lang.org/stable/std/collections/struct.VecDeque.html#method.push_front){ rel=nofollow } It's even worse for `BTreeSet` and `HashSet`, since you have to use a borrow of the value itself to look it up from the set, so you'd probably have to have `clone()`d it before you inserted it.

    There is a workaround for `BTreeMap` and `HashMap`, which is to use their `entry()` APIs which do have a way to get a `&mut V` of the value that was just inserted. Unfortunately this is much more verbose than a simple call to `insert()`. And even these APIs don't return a `&K` borrowed from the map that can be used after the entry has been inserted.

    These functions can't be changed due to backward-compatibility. Even the functions that return `()` cannot be changed to return non-unit values, since they may be used in contexts where the return type is used to drive further inference. But new functions could be added that do return borrows of the newly inserted values.
