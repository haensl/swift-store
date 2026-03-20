# swift-store

![Version](https://img.shields.io/github/v/tag/haensl/swift-store)
![Swift](https://img.shields.io/badge/Swift-6-orange)
![Platforms](https://img.shields.io/badge/platforms-iOS%20macOS%20tvOS%20watchOS-blue)
[![CI](https://github.com/haensl/swift-store/actions/workflows/tests.yml/badge.svg)](https://github.com/haensl/swift-store/actions/workflows/tests.yml)
![License](https://img.shields.io/badge/license-MIT-green)

A lightweight, modern Redux-style store for Swift — built with Swift Concurrency in mind.

`swift-store` provides a minimal and predictable state container inspired by Redux, without the complexity of larger frameworks. It embraces `async/await`, uses actor isolation for thread safety, and integrates naturally with SwiftUI.

## In less than 30 lines of code

```swift
struct CounterState: AppState {
  var count = 0
}

enum CounterAction: AppAction {
  case increment
}

let reducer: Reducer<CounterState> = { state, action in
  var newState = state
  switch (action) {
    case CounterAction.increment:
        newState.count = newState.count + 1

    default:
        reutrn state
  }
  return newState
}

let store = Store(
  initialState: CounterState(),
  reducer: reducer
)

Task {
  await store.dispatch(CounterAction.increment)
}
```

## ToC
* [Usage](#usage)
* [API](#api)
* [License](#license)
* [Changelog](CHANGELOG.md)

## Why swift-store?

- 🧠 **Simple mental model** — Actions → Reducers → State
- ⚡️ **Swift Concurrency-first** — built around `async/await`
- 🔒 **Thread-safe by design** — internal actor guarantees ordered, race-free updates
- 🧩 **Composable** — split state and reducers as your app grows
- 🪶 **Lightweight** — no macros, no codegen, no heavy abstractions

## Not a framework

Unlike larger solutions like TCA, `swift-store` intentionally stays minimal:

- No custom DSLs
- No opinionated architecture layers
- No boilerplate-heavy patterns

You bring your own structure — `swift-store` just gives you the core primitives.

## When to use it

`swift-store` is a great fit if you want:

- predictable state updates
- async side effects (`Thunk`s) without magic
- a small, understandable core you can extend yourself

If you’re building a SwiftUI app and want Redux-style state **without the weight**, this is for you.

## Usage <a name="usage"></a>

### Installation <a name="installation"></a>

Add via Swift Package Manager:

https://github.com/haensl/swift-store

### Import the module

```swift
import SwiftStore
```

### Redux: Mental Model

- `Action` → describes *what happened*
- `Reducer` → computes new state
- `Thunk` → performs async work
- `Middleware` → reacts to actions and state changes
- `Store` → orchestrates everything

### Design Principles

- State is the single source of truth
- Reducers are pure and synchronous
- Side effects live in Thunks or Middleware
- Updates flow in one direction: Action → Reducer → State

### Concurrency requirements

- All state ([`AppState`](#api/AppState), [`Middlewares`](#api/Middleware), [`Reducers`](#api/Reducer), ...) and captured values should conform to `Sendable` in order to ensure thread safety.
- Reducers must be synchronous and side-effect free.
- `dispatch` is `async` due to internal `actor` - call it from a `Task` or `async` context.

### Example: Define your state and reducer(s) <a name="example"></a>

Use the [`AppState`](#api/AppState), [`AppAction`](#api/AppAction), [`Middleware`](#api/Middleware) and [`Thunk`](#api/Thunk) to model your application state and business logic. Let's walk through an example:

Define your root [state](#api/AppState). It can be composed of sub-states produced by other reducers:

```swift
struct RootState: AppState {
  var user: UserState

  init() {
    self.user = UserState()
  }
}
```

Define your root [reducer](#api/Reducer). It might just invoke sub-reducers:

```swift
@Sendable
func RootReducer(state: RootState, action: AppAction) -> RootState {
  // Create a mutable copy
  var newState = state

  // Apply your sub-reducers
  newState.user = UserReducer(state: newState.user, action: action)

  return newState
}
```

Define your sub state(s):

```swift
struct UserState: AppState {
  var name: String = ""

  var updateInProgress: Bool = false

  // ...
}
```

Define [actions](#api/AppAction) to manipulate `UserState`:

```swift
enum UserAction: AppAction {
  /// Sets ``UserState/name``
  case setName(String)

  /**
   Signals that a PATCH at the Users API has finished
   - Parameter : Potential error that occurred.
   */
  case updateFinished(Error? = nil)

  /// Signals that a PATCH at the Users API is ongoing
  case updateInProgress
}
```

Handle the actions in the [`Reducer`](#api/Reducer):

```swift
@Sendable
func UserReducer(state: UserState, action: AppAction) -> UserState {
  // Create a mutable copy
  var newState = state

  switch (action) {
    case UserAction.setName(let name):
      newState.name = name

    case UserAction.updateFinished(let error):
      if let error {
        Log.error("User profile update failing \(String(describing: error))")
      }
      newState.updateInProgress = false

    case UserAction.updateInProgress:
      newState.updateInProgress = true

    default:
      // If nothing changed -> return original state
      return state
  }

  return newState
}
```

Define asynchronous operations ([thunks](#api/Thunk)):
```swift
struct UserThunk {
  /**
   Updates the user profile.

   Performs the given patch at the Users API.

   - Parameter patch: The ``User`` patch to apply.

   - Returns: A ``Thunk`` that updates ``UserState``
   */
  static func update(patch: User) -> Thunk<RootState> {
    return { [patch] store in
      // Get current state
      let state = await store.getState()

      if (state.user.updateInProgress) {
        Log.info("Update in progress.")
        return
      }

      await store.dispatch(UserAction.updateInProgress)

      do {
        try await UsersService.shared.update(patch: patch)
        await store.dispatch(UserAction.updateFinished(nil))
      } catch {
        await store.dispatch(UserAction.updateFinished(error))
      }
    }
  }
}
```

Use [middlewares](#api/Middleware) to drive your application:

```swift
// All middlewares follow this signature
@Sendable
func UserMiddleware(
  // Store to dispatch to
  store: Store<RootState>,
  // Action that lead to current state
  action: AppAction,
  // Current application state
  state: RootState,
  // State before action was applied
  previous: RootState
) async -> Void {
  switch (action) {
    // Load user profile on sign in
    case UserAction.signInSuccess:
      await store.dispatch(UserThunk.load())

    // ...
  }
}
```

### Instantiate your Store

Instantiate your app's store at an appropriate place for your platform.

#### Example: SwiftUI

Use your `App` to hold the store and pass it to your `View`s:

```swift
import SwiftUI
import SwiftStore

@main
struct MyApp: App {
  @StateObject private var store = Store<RootState>(
    initialState: RootState(),
    reducer: RootReducer.self,
    middlewares: [
      UserMiddleware
    ]
  )

  var body: some Scene {
    WindowGroup {
      NavigationStack {
        // ...
      }
      .environmentObject(store) // Pass store to view hierarchy
    }
  }
}
```

### Use it in your views

Use the store to drive your views:

```swift
import SwiftUI

struct OnboardingNameView: View {
  @EnvironmentObject var store: Store<RootState> // Store passed down via environment

  // ...
  private var username: Binding<String> {
    .init(
      get {
        store.state.user.name
      }
      set { newValue in
        Task { [newValue] in
          await store.dispatch(UserAction.setName(newValue))
        }
      }
    )
  }

  var body: some View {
    VStack {
      TextField(
        "",
        text: username,
        prompt: Text("Please enter your name.")
      )

      // ...
    }
  }
}
```

## Gotchas <a name="faq"></a>

- Reducers must be pure — no async work or side effects.
- State should be value types (`struct`) for best results.
- Use [`Thunk`s](#api/Thunk) for initiating async work (API calls, workflows)
- Use [`Middleware`](#api/Middleware) for reacting to actions (logging, chaining, orchestration)
- [`dispatch`](#api/Store/dispatchAction) is `async` - the [`Store`](#api/Store) is `actor`-isolated and guarantees ordered, thread-safe updates.
- Middlewares are executed in the order they are provided.

## API <a name="api"></a>

* [`AppAction`](#api/AppAction)
* [`AppState`](#api/AppState)
* [`Middleware`](#api/Middleware)
* [`Reducer`](#api/Reducer)
* [`Store`](#api/Store)
* [`Thunk`](#api/Thunk)

### AppAction <a name="api/AppAction"></a>

`AppAction` is a protocol type to mark your types as Redux store actions:

```swift
// Sendable via AppAction protocol
enum UserAction: AppAction {
  case setName(String)

  case updateFinished(Error? = nil)

  case updateInProgress
}
```

Actions are dispatched to the [`Store`](#api/Store):

```swift
await store.dispatch(UserAction.updateInProgress)
```

It is common practice to use `enum` types as `AppAction`, though other types are possible.

### AppState <a name="api/AppState"></a>

`AppState` is a protocol type to mark your types as Redux state:

```swift
// Sendable via AppState protocol
struct UserState: AppState {
  var name: String = ""
  var updateInProgress: Bool = false
}
```

It is common to use `struct` types for `AppState` since value types harmonize with redux principles, but other types are possible as long as they adhere to `@Sendable`.

### Middleware <a name="api/Middleware"></a>

`Middleware` is a function type. It defines the signature for your middlewares:

```swift
typealias Middleware<T: AppState> = @Sendable (
  _ store: Store<T>,
  _ action: AppAction,
  _ state: T,
  _ previous: T
) async -> Void
```

**Example:**

```swift
// Sendable via Middleware protocol
let UserMiddleware: Middleware<RootState> = { store, action, state, previous in
  switch (action) {
      // Load user profile on sign in
      case UserAction.signInSuccess:
        await store.dispatch(UserThunk.load())

      // ...
  }
}
```

This is equivalent to writing:

```swift
@Sendable
func UserMiddleware(store: Store<RootState>, action: AppAction, state: RootState, previous: RootState) async -> Void {
  // ...
}
```

Middlewares are invoked with the store, the current action, the current state and the previous state (before `action` was applied). Middlewares are awaited sequentially after each action is reduced.

### Reducer <a name="api/Reducer"></a>

`Reducer` is a function type and defines the signature of your reducers:

```swift
typealias Reducer<T: AppState> = @Sendable (T, AppAction) -> T
```

**Example:**

```swift
// Sendable via Reducer protocol
let UserReducer: Reducer = { state, action in
  var newState = state

  switch (action) {
    case UserAction.setName(let name):
      newState.name = name

    default:
      return state
  }

  return newState
}
```

This is equivalent to writing:
```swift
@Sendable
func UserReducer(state: UserState, action: AppAction) -> UserState {
  // ...
}
```

**Attention:**
Avoid side-effects in reducers. Use [thunks](#api/Thunk) or [middleware](#api/Middleware) instead.


### Store <a name="api/Store"></a>

A simple redux store implementation.

`Store<T: AppState>` is a `@MainActor` class backed by an internal `actor` for thread-safe mutations. It manages a composable [`AppState`](#api/AppState) and allows for dispatching of [actions](#api/AppAction) and [thunks](#api/Thunk). Add [`Middleware`s](#api/Middleware) to your store to host your business logic.

```swift
import SwiftUI
import SwiftStore

@main
struct MyApp: App {
    @StateObject private var store = Store<RootState>(
      initialState: RootState(),
      reducer: RootReducer.self,
      middlewares: [
        UserMiddleware
      ]
    )

    var body: some Scene {
      WindowGroup {
        NavigationStack {
          // ...
        }
        .environmentObject(store) // Pass store to view hierarchy
      }
    }
}
```

#### Store.state <a name="api/Store/state"></a>

The current root state.

```swift
@Published var state: T
```

The published current root [`T: AppState`](#api/AppState). For `@MainActor` contexts like SwiftUI `View`s, this is the primary access path to current application state:

```swift
import SwiftUI

struct OnboardingNameView: View {
  @EnvironmentObject var store: Store<RootState> // Store passed down via environment

  // ...
  private var username: Binding<String> {
    .init(
      get {
        store.state.user.name // Access current state
      }
      set { newValue in
        Task { [newValue] in
          await store.dispatch(UserAction.setName(newValue))
        }
      }
    )
  }

  var body: some View {
    VStack {
      TextField(
        "",
        text: username,
        prompt: Text("Please enter your name.")
      )

      // ...
    }
  }
}
```

#### Store.init(initialState: T: AppState, reducer: Reducer, middlewares: [Middleware]) <a name="api/Store/init"></a>

Creates a new store.

```swift
init(
  initialState: T,
  reducer: @escaping Reducer<T>,
  middlewares: [Middleware<T>] = []
)
```

##### Parameters

`initialState: T`

Provide the initial state for the store. `T` must be an [`AppState`](#api/AppState).

`reducer: Reducer`

The root [reducer](#api/Reducer) for this store. Reducers can be composed of sub-reducers as shown in the [example above](#example).

`middlewares: [Middleware]`

The [middlewares](#api/Middleware) to run after each state mutation. Middlewares are `await`ed sequentially.

#### Store.dispatch(_ action: AppAction) <a name="api/Store/dispatchAction"></a>

Dispatches an [`AppAction`](#api/AppAction) to the store. Dispatches are processed in order (FIFO) and are thread-safe.

```swift
func dispatch(_ action: AppAction) async
```

The store is backed by its own `actor` to ensure thread safety. You therefore need to `await` dispatching:


```swift
await store.dispatch(UserAction.setName("new name"))
```

#### Store.dispatch(_ thunk: Thunk) <a name="api/Store/dispatchThunk"></a>

Dispatches a [`Thunk`](#api/Thunk) to the store. Thunks can perform side-effects and asynchronous work.

```swift
func dispatch(_ thunk: Thunk<T>) async
```

The store is backed by it's own `actor` to ensure thread safety. You therefore need to `await` dispatching:


```swift
await store.dispatch(UserThunk.update(patch: patch))
```

#### Store.getState() -> T <a name="api/Store/getState"></a>

Returns the current application state.

```swift
func getState() -> T
```

`getState()` is `@MainActor`-isolated. Access it directly from SwiftUI `View`s, or `await` it from `async` contexts like [`Thunk`s](#api/Thunk).

```swift
// e.g. in your thunk:
let state = await store.getState()
```

#### Store.postpone(tag: String, _ thunk: Thunk) <a name="api/Store/postpone"></a>

Postpone a thunk. Sets the given thunk aside for later execution under the given tag. Preserves order (FIFO).

```swift
func postpone(tag: String, _ thunk: @escaping Thunk<T>) async
```



##### Parameters

`tag: String`

A tag to associate with this thunk. This is useful to create execution buckets that can later be run via [`runPostponed()`](#api/Store/runPostponed).

`thunk: Thunk<T>`

The [`Thunk`](#api/Thunk) to postpone.

#### Store.runPostponed(tag: String) <a name="api/Store/runPostponed"></a>

Run postponed thunks associated with the given tag.

```swift
func runPostponed(tag: String) async
```

* Running postponed thunks removes them from queue.
* Postponed thunks are dispatched in the order they were postponed (FIFO).

##### Parameters

`tag: String`

The tag of the thunks to run.

### Thunk <a name="api/Thunk"></a>

`Thunk` is a type of action that manipulates the state by dispatching other actions. Use it for your asynchronous work, e.g. API requests, etc.

```swift
typealias Thunk<T: AppState> = @Sendable (Store<T>) async -> Void
```

**Example:**

```swift
struct UserThunk {
  /**
   Updates the user profile.

   Performs the given patch at the Users API.

   - Parameter patch: The ``User`` patch to apply.

   - Returns: A ``Thunk`` that updates ``UserState``
   */
  static func update(patch: User) -> Thunk<RootState> {
    return { [patch] store in // Sendable via Thunk protocol
      // Get current state
      let state = await store.getState()

      if (state.user.updateInProgress) {
        Log.info("Update in progress.")
        return
      }

      await store.dispatch(UserAction.updateInProgress)

      do {
        try await UsersService.shared.update(patch: patch)
        await store.dispatch(UserAction.updateFinished(nil))
      } catch {
        await store.dispatch(UserAction.updateFinished(error))
      }
    }
  }
}
```

Thunks are typically created from parameterizable functions and dispatched to the store:

```swift
await store.dispatch(UserThunk.update(patch: User(name: "new name")))
```


## License

[MIT License](LICENSE)

## [Changelog](CHANGELOG.md)
