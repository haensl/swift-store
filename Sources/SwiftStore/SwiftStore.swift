//
//  SwiftStore.swift
//
//  Created by Hans-Peter Dietz on 10.11.21.
//

import Foundation

/**
 An application (sub-)state.
 
 State should be value types, e.g. `struct`, for best results.
 */
public protocol AppState: Sendable {}

/**
 A Redux-like reducer.
 
 A ``Reducer`` is a function that processes an ``AppAction`` dispatched to an ``AppStater`` and returns the resulting ``AppStater``.
 
 - Attention: ``Reducer``s must be pure - no `async`  work or side-effects.
 
 - Parameter $1: The current application (sub-)state
 - Parameter $2: The action to process.
 
 - Returns: An updated application (sub-)state.
 
 See also: ``Store/dispatch(action:)``
 */
public typealias Reducer<T: AppState> = @Sendable (T, AppAction) -> T

/**
 An action that can be dispatched to the ``Store``.
 
 See also: ``Store/dispatch(action:)``
 */
public protocol AppAction: Sendable {}

/**
 A Redux-like thunk.
 
 A ``Thunk`` is a type of action that carries out side-effects and asynchronous work. It manipulates the ``AppStater`` by dispatching other actions.
 
 - Parameter $0: The store to dispatch to.
 
 - Returns: A function that manipulates the application state.
 */
public typealias Thunk<T: AppState> = @Sendable (Store<T>) async -> Void

/**
 A Redux-like middleware.
 
 A ``Middleware`` reacts to ``AppAction``s being dispatched to the store and state changes. It may dispatch ``AppAction``s and ``Thunk``s.
 
 - Attention: Avoid long running tasks in ``Middleware`` - use ``Thunk`` instead.
 
 - Parameter store: The store. Use it to dispatch actions to and get the _latest_ (--> concurrency is a thing).
 - Parameter action: The action that was processed between `previous` and `current`.
 - Parameter state: The current app state.
 - Parameter previous: The previous app state.
 */
public typealias Middleware<T: AppState> = @Sendable (
  _ store: Store<T>,
  _ action: AppAction,
  _ state: T,
  _ previous: T
) async -> Void

/**
 Actor to drive a ``Store``.
 */
fileprivate actor StoreActor<T: AppState> {
  private var state: T
  private let reducer: Reducer<T>
  private var postponed: [String: [Thunk<T>]] = [:]
  
  init(
    initialState: T,
    reducer: @escaping Reducer<T>
  ) {
    self.reducer = reducer
    self.state = initialState
  }
}

// MARK: Methods
extension StoreActor {
  fileprivate func dispatch(_ action: AppAction) {
    let newState = reducer(state, action)
    state = newState
  }
  
  func getState() async -> T {
    state
  }
  
  /**
   Postpone an action.
   
   - Parameter thunk: The action(s) to postpone.
   - Parameter tag: A tag to associate with this thunk. Use this tag to later with ``Store/runPostponed(tagged:)`` and ``drainPostponed(tagged:)``   to run postponed actions.
   */
  func postpone(_ thunk: @escaping Thunk<T>, tagged tag: String) {
    postponed[tag, default: []].append(thunk)
  }
  
  /**
   Drain postponed actions.
   
   Returns all actions associated with the given `tag` **in insertion order** and removes them from the queue.
   
   - Parameter tag: The tag associated with the actions to fetch.
   */
  func drainPostponed(tagged tag: String) -> [Thunk<T>] {
    postponed.removeValue(forKey: tag) ?? []
  }
}


/**
 Redux-like store.
 
 A ``Store`` manages application state. `dispatch` actions to manipulate application state. A ``Store`` is created from a ``Reducer`` and can have ``Middleware``s attached that are invoked _after_ each ``Action`` has been processed.
 */
@MainActor
public final class Store<T: AppState>: ObservableObject {
  @Published public private(set) var state: T
  
  private let actor: StoreActor<T>
  private let middlewares: [Middleware<T>]
  
  public init(
    initialState: T,
    reducer: @escaping Reducer<T>,
    middlewares: [Middleware<T>] = []
  ) {
    self.actor = StoreActor(
      initialState: initialState,
      reducer: reducer
    )
    self.middlewares = middlewares
    self.state = initialState
  }
  
  /**
   Dispatches a thunk to the store.
   
   - Parameter thunk: The ``Thunk`` to dispatch.
   */
  public func dispatch(_ thunk: @escaping Thunk<T>) async {
    await thunk(self)
  }
  
  /**
   Dispatches an action to the store.
   
   Actions are run asynchronously (i.e. non-blocking) ** in order** (FIFO).
   
   After each ``AppAction`` is processed, all ``Middleware``s attached to this ``Store`` are invoked **asynchronously in the order they were provided**.
   
   - Parameter action: The ``AppAction`` to dispatch.
   */
  public func dispatch(_ action: AppAction) async {
    let previous = state
    await actor.dispatch(action)
    let newState = await actor.getState()
    state = newState
    
    for middleware in middlewares {
      await middleware(self, action, newState, previous)
    }
    
    state = await actor.getState()
  }
  
  /**
   Returns the current application state.
   */
  public func getState() -> T {
    state
  }
  
  /**
   Postpone an action.
   
   - Parameter thunk: The action(s) to postpone.
   - Parameter tag: A tag to associate with this thunk. Use this tag to later with ``runPostponed(tagged:)``   to run postponed actions.
   */
  public func postpone(tag: String, _ thunk: @escaping Thunk<T>) async {
    await actor.postpone(thunk, tagged: tag)
  }
  
  /**
   Run postponed actions.
   
   Runs all actions associated with the given `tag` **in insertion order**.
   
   - Parameter tag: The tag associated with the actions to run.
   */
  public func runPostponed(tag: String) async {
    let thunks = await actor.drainPostponed(tagged: tag)
    for thunk in thunks {
      await dispatch(thunk)
    }
  }
}
